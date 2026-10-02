import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_local_executable.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart';

void main() {
  test('local RPC and event stream use the configured loopback port', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final eventRequest = Completer<Uri>();
    final subscription = server.listen((request) async {
      if (request.uri.path == '/event-stream') {
        eventRequest.complete(request.uri);
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.bufferOutput = false;
        request.response.write('data: {"source":"isolated"}\n\n');
        await request.response.close();
        return;
      }

      received.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'result': 'mock-kdf'}));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final config = LocalConfig(
      https: false,
      rpcPassword: 'test-only-rpc-password',
      rpcPort: server.port,
    );
    expect(LocalConfig.fromJson(config.toJson()).rpcPort, server.port);
    expect(LocalConfig(https: false, rpcPassword: 'default').rpcPort, 7783);

    final operations = KdfOperationsLocalExecutable.create(
      logCallback: (_) {},
      config: config,
    );
    addTearDown(operations.dispose);
    expect(await operations.version(), 'mock-kdf');
    expect(received.single['method'], 'version');
    expect(received.single['userpass'], 'test-only-rpc-password');

    final event = Completer<Object?>();
    final unsubscribe = connectEventStream(
      hostConfig: config,
      onFirstByte: () {},
      onMessage: event.complete,
    );
    addTearDown(unsubscribe);
    expect(await event.future.timeout(const Duration(seconds: 5)), {
      'source': 'isolated',
    });
    expect((await eventRequest.future).queryParameters['id'], '0');
    expect(received.last['userpass'], 'test-only-rpc-password');
  });
}
