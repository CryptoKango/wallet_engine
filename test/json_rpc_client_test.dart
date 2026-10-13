import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('JsonRpcClient', () {
    test('retries a malformed response on another endpoint', () async {
      final transport = _ScriptedTransport(<Object?>[
        'not-an-object',
        <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'result': '0x1'},
      ]);
      final client = _client(transport);

      final result = await client.call<String>(
        method: 'eth_chainId',
        decode: (value) => value! as String,
      );

      expect(result, '0x1');
      expect(transport.hosts, <String>[
        'first.example.com',
        'second.example.com',
      ]);
    });

    test('does not retry a deterministic JSON-RPC error', () async {
      final transport = _ScriptedTransport(<Object?>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'error': <String, Object?>{
            'code': -32602,
            'message': 'invalid params',
          },
        },
      ]);
      final client = _client(transport);

      await expectLater(
        client.call<Object?>(method: 'eth_call', decode: (value) => value),
        throwsA(
          isA<JsonRpcException>()
              .having((error) => error.code, 'code', -32602)
              .having((error) => error.retryable, 'retryable', isFalse)
              .having((error) => error.context['rpcCode'], 'rpcCode', -32602),
        ),
      );
      expect(transport.hosts, hasLength(1));
    });

    test('keeps raw server text out of safe diagnostics', () async {
      final transport = _ScriptedTransport(<Object?>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'error': <String, Object?>{
            'code': -32000,
            'message': 'failed for secret-account-and-payload',
          },
        },
      ]);
      final client = _client(transport);

      try {
        await client.call<Object?>(
          method: 'eth_call',
          decode: (value) => value,
        );
        fail('Expected a JSON-RPC error.');
      } on JsonRpcException catch (error) {
        expect(error.cause, contains('secret-account'));
        expect(error.toString(), isNot(contains('secret-account')));
        expect(
          error.toDiagnosticMap().toString(),
          isNot(contains('secret-account')),
        );
      }
    });

    test('retries a transient JSON-RPC error', () async {
      final transport = _ScriptedTransport(<Object?>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'error': <String, Object?>{
            'code': -32005,
            'message': 'rate limit exceeded',
          },
        },
        <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'result': '0x2'},
      ]);
      final client = _client(transport);

      final result = await client.call<String>(
        method: 'eth_chainId',
        decode: (value) => value! as String,
      );

      expect(result, '0x2');
      expect(transport.hosts, hasLength(2));
    });
  });
}

JsonRpcClient _client(RpcTransport transport) {
  return JsonRpcClient(
    rpc: RpcClient(
      chainKey: 'ethereum',
      poolConfig: RpcPoolConfig(
        endpoints: <RpcEndpoint>[
          RpcEndpoint.parse('https://first.example.com'),
          RpcEndpoint.parse('https://second.example.com'),
        ],
      ),
      retryConfig: const RpcRetryConfig(),
      transportConfig: const RpcTransportConfig(),
      transport: transport,
    ),
  );
}

final class _ScriptedTransport implements RpcTransport {
  _ScriptedTransport(this._results);

  final List<Object?> _results;
  final List<String> hosts = <String>[];
  int _index = 0;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    hosts.add(endpoint.uri.host);
    return RpcResponse(statusCode: 200, data: _results[_index++]);
  }
}
