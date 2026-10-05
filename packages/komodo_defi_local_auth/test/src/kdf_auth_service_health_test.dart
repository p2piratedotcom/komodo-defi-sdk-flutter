import 'dart:async';

import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _FakeKdfOperations implements IKdfOperations {
  _FakeKdfOperations({required this.responsesByMethod});

  final Map<String, Map<String, dynamic>> responsesByMethod;
  bool _running = true;
  int stops = 0;
  int starts = 0;
  bool unavailable = false;
  bool failStop = false;
  Completer<void>? stopGate;
  Completer<void>? versionGate;

  @override
  String get operationsName => 'fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    starts++;
    _running = true;
    unavailable = false;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      _running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    stops++;
    await stopGate?.future;
    if (failStop) throw StateError("stop failed");
    _running = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<String?> version() async {
    await versionGate?.future;
    return _running && !unavailable ? 'test-version' : null;
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    final method = request['method'] as String?;
    if (method == null) {
      return {'mmrpc': '2.0', 'result': <String, dynamic>{}};
    }

    return responsesByMethod[method] ??
        <String, dynamic>{'mmrpc': '2.0', 'result': <String, dynamic>{}};
  }

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  Future<(KdfAuthService, _FakeKdfOperations)> create({
    bool authenticated = true,
  }) async {
    final operations = _FakeKdfOperations(
      responsesByMethod: {
        'get_wallet_names': {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': 'test-wallet',
          },
        },
      },
    );
    final config = LocalConfig(
      https: false,
      rpcPassword: 'test-only',
      rpcPort: 17783,
    );
    final framework = KomodoDefiFramework.createWithOperations(
      kdfOperations: operations,
      hostConfig: config,
    );
    final service = KdfAuthService(framework, config);
    if (authenticated) {
      final user = KdfUser(
        walletId: WalletId.fromName(
          'test-wallet',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      );
      await SecureLocalStorage().saveUser(user);
      await service.restoreSession(user);
    }
    addTearDown(() async {
      operations.failStop = false;
      operations.stopGate?.complete();
      operations.stopGate = null;
      await service.dispose();
    });
    return (service, operations);
  }

  test(
    'unavailable version preserves active session and never stops KDF',
    () async {
      final (service, operations) = await create();
      final emissions = <KdfUser?>[];
      final sub = service.authStateChanges.listen(emissions.add);
      addTearDown(sub.cancel);
      operations.unavailable = true;
      expect(await service.ensureKdfHealthy(), isFalse);
      expect(operations.stops, 0);
      expect(operations.starts, 0);
      expect((await service.getActiveUser())?.walletId.name, 'test-wallet');
      expect(emissions.where((user) => user == null), isEmpty);
    },
  );

  test(
    'a version response slower than two seconds does not end the session',
    () async {
      final (service, operations) = await create();
      operations.versionGate = Completer<void>();
      final timer = Timer(const Duration(seconds: 3), () {
        operations.versionGate!.complete();
      });
      addTearDown(timer.cancel);
      expect(await service.ensureKdfHealthy(), isTrue);
      operations.versionGate = null;
      expect(operations.stops, 0);
      expect(operations.starts, 0);
      expect((await service.getActiveUser())?.walletId.name, 'test-wallet');
    },
  );

  test('healthy version does not restart or stop KDF', () async {
    final (service, operations) = await create();
    expect(await service.ensureKdfHealthy(), isTrue);
    expect(operations.stops, 0);
    expect(operations.starts, 0);
  });

  test('recovery waits for shutdown and does not start if it fails', () async {
    final (service, operations) = await create(authenticated: false);
    operations.unavailable = true;
    operations.stopGate = Completer<void>();
    final recovery = service.ensureKdfHealthy();
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(operations.stops, 1);
    expect(operations.starts, 0);
    operations.failStop = true;
    operations.stopGate!.complete();
    operations.stopGate = null;
    expect(await recovery, isFalse);
    expect(operations.starts, 0);
  });

  test('shutdown failure prevents starting a replacement KDF', () async {
    final (service, operations) = await create(authenticated: false);
    operations.unavailable = true;
    operations.failStop = true;
    expect(await service.ensureKdfHealthy(), isFalse);
    expect(operations.starts, 0);
  });
}
