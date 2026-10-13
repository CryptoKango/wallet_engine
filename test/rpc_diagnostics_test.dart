import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('RPC diagnostics and API', () {
    test('failure event exposes stable code and retry decision', () async {
      final events = <RpcLogEvent>[];
      final pool = RpcEndpointPool(
        chainKey: 'ethereum',
        config: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://rpc.example.com'),
          ],
        ),
        retry: const RpcRetryConfig(maxAttempts: 1),
        logSink: events.add,
      );

      await expectLater(
        pool.execute<void>(
          operation: 'eth_chainId',
          attempt: (_) async => throw _timeout,
          shouldRetry: (error) => error is WalletError && error.retryable,
        ),
        throwsA(isA<RpcTransportException>()),
      );

      final failure = events.last;
      expect(failure.type, RpcLogEventType.failure);
      expect(failure.errorCode, 'rpc.transport.timeout');
      expect(failure.retryable, isTrue);
      expect(failure.endpointHost, 'rpc.example.com');
    });

    test('host log sink failure never changes an RPC result', () async {
      final pool = RpcEndpointPool(
        chainKey: 'ethereum',
        config: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://rpc.example.com'),
          ],
        ),
        retry: const RpcRetryConfig(maxAttempts: 1),
        logSink: (_) => throw StateError('logger unavailable'),
      );

      final result = await pool.execute<String>(
        operation: 'eth_chainId',
        attempt: (_) async => '0x1',
        shouldRetry: (_) => false,
      );

      expect(result, '0x1');
    });

    test(
      'redacts failure response bodies and truncates large bodies',
      () async {
        final events = <RpcLogEvent>[];
        final pool = RpcEndpointPool(
          chainKey: 'ethereum',
          config: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('https://rpc.example.com'),
            ],
          ),
          retry: const RpcRetryConfig(maxAttempts: 1),
          logging: const RpcLoggingConfig(
            includeRequestBody: true,
            includeResponseBody: true,
            maxBodyCharacters: 32,
          ),
          logSink: events.add,
        );

        await expectLater(
          pool.execute<void>(
            operation: 'custom_operation',
            requestBody: <String, Object?>{
              'value': 'abcdefghijklmnopqrstuvwxyz0123456789',
            },
            failureResponseBody: () => <String, Object?>{
              'signature': 'must-not-leak',
            },
            attempt: (_) async => throw _timeout,
            shouldRetry: (_) => false,
          ),
          throwsA(isA<RpcTransportException>()),
        );

        expect(events.first.requestBody, endsWith('…'));
        expect(events.first.requestBody, isNot(contains('0123456789')));
        expect(events.last.responseBody, contains('<redacted>'));
        expect(events.last.responseBody, isNot(contains('must-not-leak')));
      },
    );

    test(
      'full body mode is explicit and preserves diagnostic payload',
      () async {
        final events = <RpcLogEvent>[];
        final client = RpcClient(
          chainKey: 'ethereum',
          poolConfig: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('https://rpc.example.com'),
            ],
          ),
          retryConfig: const RpcRetryConfig(maxAttempts: 1),
          transportConfig: const RpcTransportConfig(),
          loggingConfig: const RpcLoggingConfig(
            includeRequestBody: true,
            bodyMode: RpcLogBodyMode.full,
          ),
          transport: _StaticTransport(RpcResponse(statusCode: 200, data: 'ok')),
          logSink: events.add,
        );

        await client.send(
          RpcRequest(
            operation: 'developer_diagnostic',
            body: <String, Object?>{'privateKey': 'unsafe-debug-value'},
          ),
        );

        expect(events.first.requestBody, contains('unsafe-debug-value'));
      },
    );

    test(
      'priority failover starts with the highest priority endpoint',
      () async {
        final low = RpcEndpoint.parse('https://low.example.com', priority: 1);
        final high = RpcEndpoint.parse(
          'https://high.example.com',
          priority: 10,
        );
        final pool = RpcEndpointPool(
          chainKey: 'ethereum',
          config: RpcPoolConfig(
            endpoints: <RpcEndpoint>[low, high],
            strategy: RpcSelectionStrategy.priorityFailover,
          ),
          retry: const RpcRetryConfig(maxAttempts: 1),
        );

        final selected = await pool.execute<String>(
          operation: 'select-node',
          attempt: (endpoint) async => endpoint.uri.host,
          shouldRetry: (_) => false,
        );

        expect(selected, 'high.example.com');
      },
    );

    test(
      'Dio transport injects runtime credentials and resolves path/query',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        HttpRequest? received;
        server.listen((request) async {
          received = request;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'ok': true}));
          await request.response.close();
        });
        final transport = DioRpcTransport(
          credentialProvider: _CredentialProvider(),
        );
        addTearDown(transport.close);
        final endpoint = RpcEndpoint.parse(
          'http://${server.address.address}:${server.port}/base?region=cn',
          allowInsecureTransport: true,
          headers: const <String, String>{'x-client': 'wallet-app'},
        );

        final response = await transport.send(
          endpoint: endpoint,
          request: RpcRequest(
            operation: 'account-status',
            method: RpcHttpMethod.get,
            path: 'v1/status',
            queryParameters: const <String, String>{'account': '7'},
            headers: const <String, String>{'x-request': 'request-value'},
          ),
          config: const RpcTransportConfig(),
        );

        expect(response.data, <String, Object?>{'ok': true});
        expect(received?.uri.path, '/base/v1/status');
        expect(received?.uri.queryParameters, <String, String>{
          'region': 'cn',
          'account': '7',
        });
        expect(
          received?.headers.value('authorization'),
          'Bearer runtime-token',
        );
        expect(received?.headers.value('x-client'), 'wallet-app');
        expect(received?.headers.value('x-request'), 'request-value');
      },
    );

    test(
      'JSON-RPC validates method and supports a custom error boundary',
      () async {
        final client = JsonRpcClient(
          rpc: RpcClient(
            chainKey: 'tron',
            poolConfig: RpcPoolConfig(
              endpoints: <RpcEndpoint>[
                RpcEndpoint.parse('https://rpc.example.com'),
              ],
            ),
            retryConfig: const RpcRetryConfig(maxAttempts: 1),
            transportConfig: const RpcTransportConfig(),
            transport: _StaticTransport(
              RpcResponse(
                statusCode: 200,
                data: <String, Object?>{
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': <String, Object?>{
                    'code': -32000,
                    'message': 'provider-specific failure',
                  },
                },
              ),
            ),
          ),
          errorDecoder: (code, message, retryable, context) {
            return NormalizedWalletException(
              category: WalletErrorCategory.chain,
              publicCode: WalletErrorCode.chainTronRpc,
              message: 'TRON RPC failed.',
              retryable: retryable,
              context: context,
            );
          },
        );

        expect(
          () => client.call<Object?>(method: ' ', decode: (value) => value),
          throwsA(isA<WalletValidationException>()),
        );
        await expectLater(
          client.call<Object?>(
            method: 'wallet/getnowblock',
            decode: (value) => value,
          ),
          throwsA(
            isA<WalletError>().having(
              (error) => error.publicCode,
              'publicCode',
              WalletErrorCode.chainTronRpc,
            ),
          ),
        );
      },
    );
  });
}

const _timeout = RpcTransportException(
  failure: RpcTransportFailure.timeout,
  message: 'RPC request timed out.',
  retryable: true,
);

final class _StaticTransport implements RpcTransport {
  const _StaticTransport(this.response);

  final RpcResponse response;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async => response;
}

final class _CredentialProvider implements RpcCredentialProvider {
  @override
  Future<Map<String, String>> headersFor(RpcEndpoint endpoint) async {
    return const <String, String>{'Authorization': 'Bearer runtime-token'};
  }
}
