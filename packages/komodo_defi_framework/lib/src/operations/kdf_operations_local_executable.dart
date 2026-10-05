import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_tor_config.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_exception.dart';
import 'package:komodo_defi_framework/src/native/kdf_executable_finder.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class KdfOperationsLocalExecutable
    implements IKdfOperations, IKdfConfirmedTermination {
  KdfOperationsLocalExecutable._(
    this._logCallback,
    this._kdfRemote, {
    Duration startupTimeout = const Duration(seconds: 30),
    KdfExecutableFinder? executableFinder,
    this.executableName = 'kdf',
  }) : _startupTimeout = startupTimeout,
       _executableFinder =
           executableFinder ?? KdfExecutableFinder(logCallback: _logCallback);

  factory KdfOperationsLocalExecutable.create({
    required void Function(String) logCallback,
    required LocalConfig config,
    Duration startupTimeout = const Duration(seconds: 30),
    String executableName = 'kdf',
  }) {
    return KdfOperationsLocalExecutable._(
      logCallback,
      KdfOperationsRemote.create(
        logCallback: logCallback,
        rpcUrl: Uri(scheme: 'http', host: '127.0.0.1', port: config.rpcPort),
        userpass: config.rpcPassword,
      ),
      startupTimeout: startupTimeout,
      executableName: executableName,
    );
  }

  final KdfOperationsRemote _kdfRemote;
  final Duration _startupTimeout;
  final void Function(String) _logCallback;
  final KdfExecutableFinder _executableFinder;
  final String executableName;

  // Use nullable fields instead of late, for the process and listeners,
  // because it is not guaranteed that they will be initialized before
  // they are used. E.g. if the process fails to start, or during the
  // cleanup process.
  Process? _process;
  Process? _lastExitedProcess;

  @override
  bool get hasConfirmedStopped =>
      _lastExitedProcess != null &&
      (_process == null || _process == _lastExitedProcess);
  StreamSubscription<List<int>>? stdoutSub;
  StreamSubscription<List<int>>? stderrSub;

  @override
  String get operationsName => 'Local Executable';

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    try {
      return await _executableFinder.findExecutable(
            executableName: executableName,
          ) !=
          null;
    } catch (e) {
      _logCallback('Error checking availability: $e');
      return false;
    }
  }

  Future<Process> _startKdf(JsonMap params) async {
    final executablePath = (await _executableFinder.findExecutable(
      executableName: executableName,
    ))?.absolute.path;
    if (executablePath == null) {
      throw KdfException(
        'KDF executable not found in any of the expected locations. '
        'Please ensure KDF is properly installed or included in your bundle.',
        type: KdfExceptionType.executableNotFound,
      );
    }

    await _verifyExecutablePermissions(executablePath);

    if (!params.containsKey('coins')) {
      throw ArgumentError.value(
        params['coins'],
        'params',
        'Missing coins list.',
      );
    }

    Directory? coinsTempDir;
    try {
      final coinsList = params.value<List<JsonMap>>('coins');
      final sensitiveArgs = JsonMap.of(params)..remove('coins');

      // Store the coins list in a temp file to avoid command line argument and
      // environment variable value size limits (varies from 4-128 KB).
      // Pass the config directly to the executable as an argument.
      final tempDir = await getTemporaryDirectory();
      coinsTempDir = await tempDir.createTemp('mm_coins_');
      final coinsConfigFile = File(p.join(coinsTempDir.path, 'kdf_coins.json'));
      await coinsConfigFile.writeAsString(
        coinsList.toJsonString(),
        flush: true,
      );

      final environment = Map<String, String>.of(Platform.environment)
        ..['MM_COINS_PATH'] = coinsConfigFile.path;

      if (KdfTorConfig.enabled) {
        KdfTorConfig.ensureConfigured();
        final libraryPath = KdfTorConfig.torsocksLibraryPath!;
        final configPath = KdfTorConfig.torsocksConfigPath!;
        if (!File(libraryPath).existsSync() || !File(configPath).existsSync()) {
          throw StateError('Tor KDF transport files are missing');
        }
        environment['LD_PRELOAD'] = libraryPath;
        environment['TORSOCKS_CONF_FILE'] = configPath;
        await _verifyTorPreload(executablePath, libraryPath, environment);
        _logCallback(
          'Starting KDF NetID ${params['netid']} via Tor SOCKS on '
          '127.0.0.1:${KdfTorConfig.socksPort}',
        );
      }

      final newProcess = await Process.start(executablePath, [
        sensitiveArgs.toJsonString(),
      ], environment: environment);

      _logCallback('Launched executable: $executablePath');
      _attachProcessListeners(newProcess, coinsTempDir);

      return newProcess;
    } catch (e, stackTrace) {
      // Clean up the temporary directory if an error occurs. Exceptions can
      // be thrown before process listeners are attached, so ensure that the
      // dangling resources are cleaned up.
      await coinsTempDir?.delete(recursive: true).catchError((Object error) {
        _logCallback('Failed to delete temporary directory: $error');
        return Directory('');
      });
      if (e is KdfException) {
        rethrow;
      }
      throw KdfException(
        'Failed to start KDF: $e',
        type: KdfExceptionType.startupFailed,
        stackTrace: stackTrace,
      );
    }
  }

  /// A separately installed executable is owned by its installer, not the GUI.
  Future<void> _verifyExecutablePermissions(String executablePath) async {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('test', ['-x', executablePath]);
      if (result.exitCode != 0) {
        throw KdfException(
          'KDF is not executable: $executablePath',
          type: KdfExceptionType.permissionError,
          stackTrace: StackTrace.current,
        );
      }
    }
  }

  void _attachProcessListeners(Process newProcess, Directory tempDir) {
    stdoutSub = newProcess.stdout.listen((event) {
      _logCallback('[INFO]: ${String.fromCharCodes(event)}');
    });

    stderrSub = newProcess.stderr.listen((event) {
      _logCallback('[ERROR]: ${String.fromCharCodes(event)}');
    });

    final processStdout = stdoutSub;
    final processStderr = stderrSub;
    newProcess.exitCode
        .then(
          (exitCode) async => _cleanUpOnProcessExit(
            newProcess,
            exitCode,
            tempDir,
            processStdout,
            processStderr,
          ),
        )
        .ignore();
  }

  Future<void> _cleanUpOnProcessExit(
    Process process,
    int exitCode,
    Directory tempDir,
    StreamSubscription<List<int>>? processStdout,
    StreamSubscription<List<int>>? processStderr,
  ) async {
    // Release only this exited instance; delayed cleanup cannot erase a new one.
    _lastExitedProcess = process;
    if (_process == process) _process = null;
    try {
      _logCallback('KDF process exited with code: $exitCode');
      await processStdout?.cancel();
      await processStderr?.cancel();

      await tempDir.delete(recursive: true);
      _logCallback('Temporary directory deleted successfully.');
    } catch (error) {
      _logCallback('Failed to delete temporary directory: $error');
    }
  }

  @override
  Future<KdfStartupResult> kdfMain(JsonMap params, {int? logLevel}) async {
    if (_process != null && _process!.pid != 0) {
      return KdfStartupResult.alreadyRunning;
    }

    final coinsCount = params.valueOrNull<List<dynamic>>('coins')?.length;
    _logCallback(
      'Starting KDF with parameters: ${{...params, 'coins': '{{OMITTED $coinsCount ITEMS}}', 'log_level': logLevel ?? 3}.censored().toJsonString()}',
    );

    try {
      _process = await _startKdf(params);

      final timer = Stopwatch()..start();

      int? exitCode;
      unawaited(_process?.exitCode.then((code) => exitCode = code));

      while (timer.elapsed < _startupTimeout) {
        if (await isRunning()) {
          break;
        }

        if (exitCode != null) {
          return KdfStartupResult.tryFromDefaultInt(exitCode!);
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (await isRunning()) {
        return KdfStartupResult.ok;
      }

      return KdfStartupResult.spawnError;
    } catch (e) {
      _logCallback('Error starting KDF: $e');
      if (e is ArgumentError) {
        return KdfStartupResult.invalidParams;
      }
      return KdfStartupResult.initError;
    }
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    final process = _process;
    if (process == null || process.pid <= 0) return MainStatus.notRunning;
    try {
      if (await _kdfRemote.isRunning()) return MainStatus.rpcIsUp;
    } catch (_) {
      // An owned child with an unavailable RPC is not a confirmed exit.
    }
    return _process == null ? MainStatus.notRunning : MainStatus.noRpc;
  }

  @override
  Future<StopStatus> kdfStop() async {
    var stopStatus = StopStatus.ok;
    final process = _process;
    var processExited = false;
    try {
      stopStatus = await _kdfRemote.kdfStop().catchError(
        (_) => StopStatus.errorStopping,
      );

      if (process == null || process.pid == 0) {
        _logCallback('Process is not running, skipping shutdown.');
        return StopStatus.notRunning;
      }

      await Future.wait([
        stdoutSub?.cancel() ?? Future<void>.value(),
        stderrSub?.cancel() ?? Future<void>.value(),
      ]);

      if (process.pid != 0) {
        await process.exitCode
            .then((code) {
              processExited = true;
              return code;
            })
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                _logCallback('KDF Process did not terminate in time.');
                stopStatus = StopStatus.errorStopping;
                return -1; // not used
              },
            );
      }

      if (processExited) {
        // The owned child's exit is stronger evidence than a lost RPC reply.
        stopStatus = StopStatus.ok;
        if (_process == process) _process = null;
      }
      _logCallback(
        processExited
            ? 'KDF process cleanup complete'
            : 'KDF shutdown uncertain; retaining owned process',
      );
    } catch (e, stack) {
      stopStatus = StopStatus.errorStopping;
      _logCallback('Critical error during KDF cleanup: $e\n$stack');
    }

    return stopStatus;
  }

  @override
  Future<bool> isRunning() async {
    return (await kdfMainStatus()) == MainStatus.rpcIsUp;
  }

  @override
  Future<String?> version() => _kdfRemote.version();

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) =>
      _kdfRemote.mm2Rpc(request);

  @override
  Future<void> validateSetup() async {
    if (_process == null) {
      throw KdfException(
        'KDF executable is not running. Please start it first.',
        type: KdfExceptionType.notRunning,
      );
    }
  }

  @override
  void resetHttpClient() {
    // Delegate to remote operations
    _kdfRemote.resetHttpClient();
  }

  @override
  void dispose() {
    // Cancel and clean up subscriptions
    stdoutSub?.cancel().ignore();
    stdoutSub = null;
    stderrSub?.cancel().ignore();
    stderrSub = null;

    // Gracefully stop the process if running
    final capturedProcess = _process;
    if (capturedProcess != null) {
      _kdfRemote.kdfStop().timeout(const Duration(seconds: 3)).ignore();
      unawaited(_gracefulProcessShutdown(capturedProcess));
    }

    // Clean up remote resources
    _kdfRemote.dispose();
  }

  Future<void> _gracefulProcessShutdown(Process capturedProcess) async {
    try {
      await capturedProcess.exitCode
          .timeout(const Duration(seconds: 5))
          .catchError((_) {
            capturedProcess.kill();
            return -1; // Return an int to match Future<int>
          });
    } finally {
      // Only set _process = null if it still equals the captured instance
      if (_process == capturedProcess) {
        _process = null;
      }
    }
  }
}

/// Ask the interpreter embedded in this exact KDF ELF to resolve its
/// libraries without executing KDF. A probe against another executable could
/// pass even when KDF is static or uses an incompatible loader.
Future<void> _verifyTorPreload(
  String executablePath,
  String libraryPath,
  Map<String, String> environment,
) async {
  final executable = File(executablePath);
  if ((await executable.stat()).mode & 0xC00 != 0) {
    throw StateError('Privileged KDF executables cannot be used with Tor');
  }
  final interpreter = await _readElfInterpreter(executable);
  final probe = await Process.run(interpreter, [
    '--list',
    executablePath,
  ], environment: environment).timeout(const Duration(seconds: 10));
  final configured = File(libraryPath).absolute.path;
  final resolved = File(libraryPath).resolveSymbolicLinksSync();
  final output = probe.stdout.toString();
  if (probe.exitCode != 0 ||
      !output
          .split('\n')
          .any(
            (line) =>
                line.trimLeft().startsWith('$configured ') ||
                line.trimLeft().startsWith('$resolved '),
          )) {
    throw StateError('KDF loader did not load the Tor transport library');
  }
}

Future<String> _readElfInterpreter(File executable) async {
  final file = await executable.open();
  try {
    final size = await file.length();
    final headerBytes = await file.read(64);
    if (headerBytes.length != 64 ||
        headerBytes[0] != 0x7f ||
        headerBytes[1] != 0x45 ||
        headerBytes[2] != 0x4c ||
        headerBytes[3] != 0x46 ||
        headerBytes[4] != 2 ||
        headerBytes[5] != 1) {
      throw StateError('Tor requires a dynamic Linux x86-64 KDF executable');
    }
    final header = ByteData.sublistView(Uint8List.fromList(headerBytes));
    if (header.getUint16(18, Endian.little) != 62) {
      throw StateError('Tor requires a Linux x86-64 KDF executable');
    }
    final offset = header.getUint64(32, Endian.little);
    final entrySize = header.getUint16(54, Endian.little);
    final count = header.getUint16(56, Endian.little);
    if (entrySize < 56 ||
        count == 0 ||
        count > 256 ||
        offset + entrySize * count > size) {
      throw StateError('Invalid KDF ELF program headers');
    }
    for (var i = 0; i < count; i++) {
      await file.setPosition(offset + i * entrySize);
      final bytes = await file.read(56);
      if (bytes.length != 56) break;
      final entry = ByteData.sublistView(Uint8List.fromList(bytes));
      if (entry.getUint32(0, Endian.little) != 3) continue; // PT_INTERP
      final pathOffset = entry.getUint64(8, Endian.little);
      final pathSize = entry.getUint64(32, Endian.little);
      if (pathSize < 2 || pathSize > 4096 || pathOffset + pathSize > size) {
        break;
      }
      await file.setPosition(pathOffset);
      final pathBytes = await file.read(pathSize);
      final terminator = pathBytes.indexOf(0);
      if (terminator < 1) break;
      final interpreter = utf8.decode(pathBytes.sublist(0, terminator));
      if (interpreter.startsWith('/')) return interpreter;
      break;
    }
    throw StateError('KDF has no usable dynamic ELF interpreter');
  } finally {
    await file.close();
  }
}
