import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:komodo_defi_framework/src/config/kdf_tor_config.dart';

class TorSeedResolver {
  TorSeedResolver._();

  static Future<String> resolve(String host) async {
    if (InternetAddress.tryParse(host) != null) return host;
    KdfTorConfig.ensureConfigured();

    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      KdfTorConfig.socksPort!,
      timeout: const Duration(seconds: 10),
    );
    final iterator = StreamIterator<List<int>>(socket);
    final pending = Queue<int>();
    // A caller-side Future.timeout does not cancel a stalled SOCKS read.
    final handshakeDeadline = Timer(
      const Duration(seconds: 15),
      socket.destroy,
    );

    Future<int> readByte() async {
      while (pending.isEmpty) {
        if (!await iterator.moveNext()) {
          throw const SocketException('Tor SOCKS connection closed');
        }
        pending.addAll(iterator.current);
      }
      return pending.removeFirst();
    }

    try {
      socket.add([5, 1, 0]);
      await socket.flush();
      if (await readByte() != 5 || await readByte() != 0) {
        throw const SocketException('Tor SOCKS authentication failed');
      }

      final bytes = host.codeUnits;
      if (bytes.isEmpty || bytes.length > 255 || bytes.any((b) => b > 127)) {
        throw ArgumentError.value(host, 'host', 'Invalid seed hostname');
      }
      socket.add([5, 0xF0, 0, 3, bytes.length, ...bytes, 0, 0]);
      await socket.flush();
      if (await readByte() != 5 || await readByte() != 0) {
        throw SocketException('Tor could not resolve $host');
      }
      await readByte();
      final addressType = await readByte();
      if (addressType != 1) {
        throw SocketException('Tor did not return an IPv4 seed for $host');
      }
      final address = <int>[];
      for (var i = 0; i < 4; i++) {
        address.add(await readByte());
      }
      await readByte();
      await readByte();
      return InternetAddress.fromRawAddress(
        Uint8List.fromList(address),
      ).address;
    } finally {
      handshakeDeadline.cancel();
      await iterator.cancel();
      socket.destroy();
    }
  }

  static Future<List<String>> resolveAll(Iterable<String> hosts) async {
    final resolved = <String>[];
    for (final host in hosts) {
      try {
        resolved.add(await resolve(host));
      } catch (_) {
        // Another seed can still provide connectivity; never resolve locally.
      }
    }
    if (resolved.isEmpty) {
      throw StateError('No Pirate KDF seed could be resolved through Tor');
    }
    return resolved;
  }
}
