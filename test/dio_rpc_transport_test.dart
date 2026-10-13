import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('DioRpcTransport', () {
    test('sends JSON and decodes a successful response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      Object? received;
      server.listen((request) async {
        received = jsonDecode(await utf8.decoder.bind(request).join());
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{'result': '0x1'}));
        await request.response.close();
      });
      final transport = DioRpcTransport();
      addTearDown(transport.close);

      final response = await transport.send(
        endpoint: _endpoint(server),
        request: RpcRequest(
          operation: 'eth_chainId',
          body: const <String, Object?>{'method': 'eth_chainId'},
        ),
        config: const RpcTransportConfig(),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.data, <String, Object?>{'result': '0x1'});
      expect(received, <String, Object?>{'method': 'eth_chainId'});
    });

    test(
      'normalizes HTTP status and Retry-After without response leakage',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) async {
          request.response
            ..statusCode = HttpStatus.tooManyRequests
            ..headers.set(HttpHeaders.retryAfterHeader, '4')
            ..write('provider secret response');
          await request.response.close();
        });
        final transport = DioRpcTransport();
        addTearDown(transport.close);

        await expectLater(
          transport.send(
            endpoint: _endpoint(server),
            request: RpcRequest(operation: 'rate-limited'),
            config: const RpcTransportConfig(),
          ),
          throwsA(
            isA<RpcTransportException>()
                .having((error) => error.statusCode, 'statusCode', 429)
                .having((error) => error.retryable, 'retryable', isTrue)
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 4),
                )
                .having(
                  (error) => error.toString(),
                  'sanitized message',
                  isNot(contains('provider secret')),
                ),
          ),
        );
      },
    );

    test('rejects requests after it is closed', () async {
      final transport = DioRpcTransport();
      await transport.close();

      await expectLater(
        transport.send(
          endpoint: RpcEndpoint.parse('https://rpc.example.com'),
          request: RpcRequest(operation: 'closed'),
          config: const RpcTransportConfig(),
        ),
        throwsA(
          isA<RpcTransportException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.rpcTransportCancelled,
          ),
        ),
      );
    });
  });
}

RpcEndpoint _endpoint(HttpServer server) {
  return RpcEndpoint.parse(
    'http://${server.address.address}:${server.port}',
    allowInsecureTransport: true,
  );
}
