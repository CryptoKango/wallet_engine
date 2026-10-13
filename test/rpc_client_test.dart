import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  test('RpcClient delegates retries to endpoint pool', () async {
    final transport = _ScriptedTransport(<Object>[
      const RpcTransportException(
        failure: RpcTransportFailure.connection,
        message: 'offline',
        retryable: true,
      ),
      RpcResponse(statusCode: 200, data: 'ok'),
    ]);
    final client = RpcClient(
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
    );

    final response = await client.send(RpcRequest(operation: 'eth_chainId'));

    expect(response.data, 'ok');
    expect(transport.hosts, <String>[
      'first.example.com',
      'second.example.com',
    ]);
  });

  test('logs configured request and response bodies', () async {
    final events = <RpcLogEvent>[];
    final client = RpcClient(
      chainKey: 'ethereum',
      poolConfig: RpcPoolConfig(
        endpoints: <RpcEndpoint>[RpcEndpoint.parse('https://rpc.example.com')],
      ),
      retryConfig: const RpcRetryConfig(),
      transportConfig: const RpcTransportConfig(),
      loggingConfig: const RpcLoggingConfig(
        includeRequestBody: true,
        includeResponseBody: true,
      ),
      transport: _ScriptedTransport(<Object>[
        RpcResponse(
          statusCode: 200,
          data: <String, Object?>{'jsonrpc': '2.0', 'result': '0x1'},
        ),
      ]),
      logSink: events.add,
    );

    await client.send(
      RpcRequest(
        operation: 'eth_chainId',
        body: <String, Object?>{'method': 'eth_chainId', 'params': <Object?>[]},
      ),
    );

    expect(events, hasLength(2));
    expect(events.first.requestBody, '{"method":"eth_chainId","params":[]}');
    expect(events.last.responseBody, '{"jsonrpc":"2.0","result":"0x1"}');
  });

  test('does not expose bodies unless explicitly configured', () async {
    final events = <RpcLogEvent>[];
    final client = RpcClient(
      chainKey: 'ethereum',
      poolConfig: RpcPoolConfig(
        endpoints: <RpcEndpoint>[RpcEndpoint.parse('https://rpc.example.com')],
      ),
      retryConfig: const RpcRetryConfig(),
      transportConfig: const RpcTransportConfig(),
      transport: _ScriptedTransport(<Object>[
        RpcResponse(statusCode: 200, data: 'secret-response'),
      ]),
      logSink: events.add,
    );

    await client.send(
      RpcRequest(operation: 'eth_chainId', body: 'secret-request'),
    );

    expect(events.every((event) => event.requestBody == null), isTrue);
    expect(events.every((event) => event.responseBody == null), isTrue);
  });

  test('redacts signed transaction payloads by default', () async {
    final events = <RpcLogEvent>[];
    final client = RpcClient(
      chainKey: 'ethereum',
      poolConfig: RpcPoolConfig(
        endpoints: <RpcEndpoint>[RpcEndpoint.parse('https://rpc.example.com')],
      ),
      retryConfig: const RpcRetryConfig(),
      transportConfig: const RpcTransportConfig(),
      loggingConfig: const RpcLoggingConfig(includeRequestBody: true),
      transport: _ScriptedTransport(<Object>[
        RpcResponse(statusCode: 200, data: '0xhash'),
      ]),
      logSink: events.add,
    );

    await client.send(
      RpcRequest(
        operation: 'eth_sendRawTransaction',
        body: <String, Object?>{
          'method': 'eth_sendRawTransaction',
          'params': <Object?>['0xsecret-signed-transaction'],
        },
      ),
    );

    expect(events.first.requestBody, contains('<redacted>'));
    expect(events.first.requestBody, isNot(contains('0xsecret')));
  });
}

final class _ScriptedTransport implements RpcTransport {
  _ScriptedTransport(this._results);

  final List<Object> _results;
  final List<String> hosts = <String>[];
  int _index = 0;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    hosts.add(endpoint.uri.host);
    final result = _results[_index++];
    if (result is RpcResponse) return result;
    throw result;
  }
}
