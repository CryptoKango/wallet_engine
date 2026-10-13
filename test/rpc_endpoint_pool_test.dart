import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('RpcEndpointPool', () {
    test('retries the next endpoint after a retryable failure', () async {
      final endpoints = <RpcEndpoint>[
        RpcEndpoint.parse('https://first.example.com'),
        RpcEndpoint.parse('https://second.example.com'),
      ];
      final pool = _pool(endpoints);
      final attempted = <Uri>[];

      final result = await pool.execute<String>(
        operation: 'eth_blockNumber',
        attempt: (endpoint) async {
          attempted.add(endpoint.uri);
          if (endpoint == endpoints.first) throw _retryableFailure;
          return '0x10';
        },
        shouldRetry: _shouldRetry,
      );

      expect(result, '0x10');
      expect(attempted, <Uri>[endpoints.first.uri, endpoints.last.uri]);
    });

    test('does not retry a deterministic failure', () async {
      final endpoints = <RpcEndpoint>[
        RpcEndpoint.parse('https://first.example.com'),
        RpcEndpoint.parse('https://second.example.com'),
      ];
      final pool = _pool(endpoints);
      var attempts = 0;

      await expectLater(
        pool.execute<void>(
          operation: 'eth_estimateGas',
          attempt: (_) async {
            attempts++;
            throw StateError('execution reverted');
          },
          shouldRetry: _shouldRetry,
        ),
        throwsA(
          isA<NormalizedWalletException>()
              .having(
                (error) => error.errorCode,
                'errorCode',
                'internal.invalidState',
              )
              .having(
                (error) => error.context['operation'],
                'operation',
                'eth_estimateGas',
              ),
        ),
      );
      expect(attempts, 1);
    });

    test('moves a cooling endpoint behind healthy endpoints', () async {
      final endpoints = <RpcEndpoint>[
        RpcEndpoint.parse('https://first.example.com'),
        RpcEndpoint.parse('https://second.example.com'),
        RpcEndpoint.parse('https://third.example.com'),
      ];
      final pool = _pool(endpoints);

      await pool.execute<String>(
        operation: 'first-call',
        attempt: (endpoint) async {
          if (endpoint == endpoints.first) throw _retryableFailure;
          return endpoint.uri.host;
        },
        shouldRetry: _shouldRetry,
      );

      final attempted = <Uri>[];
      await pool.execute<String>(
        operation: 'second-call',
        attempt: (endpoint) async {
          attempted.add(endpoint.uri);
          return endpoint.uri.host;
        },
        shouldRetry: _shouldRetry,
      );

      expect(attempted.single, endpoints.last.uri);
    });

    test('cooldown is fail-open when every endpoint is cooling', () async {
      final endpoints = <RpcEndpoint>[
        RpcEndpoint.parse('https://first.example.com'),
        RpcEndpoint.parse('https://second.example.com'),
      ];
      final pool = _pool(endpoints);

      await expectLater(
        pool.execute<void>(
          operation: 'prime-cooldown',
          attempt: (_) async => throw _retryableFailure,
          shouldRetry: _shouldRetry,
        ),
        throwsA(isA<RpcTransportException>()),
      );

      var attempts = 0;
      await expectLater(
        pool.execute<void>(
          operation: 'all-cooling',
          attempt: (_) async {
            attempts++;
            throw _retryableFailure;
          },
          shouldRetry: _shouldRetry,
        ),
        throwsA(isA<RpcTransportException>()),
      );
      expect(attempts, 2);
    });

    test('logs only sanitized endpoint hosts', () async {
      final events = <RpcLogEvent>[];
      final endpoint = RpcEndpoint.parse(
        'https://rpc.example.com/private/project-key?region=query-secret',
      );
      final pool = _pool(<RpcEndpoint>[endpoint], logSink: events.add);

      await pool.execute<String>(
        operation: 'eth_chainId',
        attempt: (_) async => '0x1',
        shouldRetry: _shouldRetry,
      );

      expect(events, hasLength(2));
      expect(
        events.every((event) => event.endpointHost == 'rpc.example.com'),
        isTrue,
      );
      expect(events.join(), isNot(contains('project-key')));
      expect(events.join(), isNot(contains('query-secret')));
    });

    test('retries a single endpoint up to maxAttempts with backoff', () async {
      final endpoint = RpcEndpoint.parse('https://only.example.com');
      final delays = <Duration>[];
      final pool = _pool(
        <RpcEndpoint>[endpoint],
        maxAttempts: 3,
        initialBackoff: const Duration(milliseconds: 10),
        delay: (duration) async => delays.add(duration),
      );
      var attempts = 0;

      await expectLater(
        pool.execute<void>(
          operation: 'single-node',
          attempt: (_) async {
            attempts++;
            throw _retryableFailure;
          },
          shouldRetry: _shouldRetry,
        ),
        throwsA(isA<RpcTransportException>()),
      );

      expect(attempts, 3);
      expect(delays, const <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ]);
    });

    test('honors a bounded Retry-After delay', () async {
      final delays = <Duration>[];
      final pool = _pool(
        <RpcEndpoint>[RpcEndpoint.parse('https://only.example.com')],
        maxAttempts: 2,
        initialBackoff: Duration.zero,
        maxBackoff: const Duration(seconds: 2),
        delay: (duration) async => delays.add(duration),
      );

      await expectLater(
        pool.execute<void>(
          operation: 'rate-limited',
          attempt: (_) async => throw const RpcTransportException(
            failure: RpcTransportFailure.httpStatus,
            message: 'rate limited',
            retryable: true,
            statusCode: 429,
            retryAfter: Duration(seconds: 30),
          ),
          shouldRetry: _shouldRetry,
        ),
        throwsA(isA<RpcTransportException>()),
      );

      expect(delays, const <Duration>[Duration(seconds: 2)]);
    });
  });
}

RpcEndpointPool _pool(
  List<RpcEndpoint> endpoints, {
  RpcLogSink? logSink,
  int? maxAttempts,
  Duration initialBackoff = Duration.zero,
  Duration maxBackoff = const Duration(seconds: 2),
  Future<void> Function(Duration duration)? delay,
}) {
  return RpcEndpointPool(
    chainKey: 'ethereum',
    config: RpcPoolConfig(
      endpoints: endpoints,
      strategy: RpcSelectionStrategy.roundRobin,
    ),
    retry: RpcRetryConfig(
      maxAttempts: maxAttempts ?? endpoints.length,
      initialBackoff: initialBackoff,
      maxBackoff: maxBackoff,
    ),
    logSink: logSink,
    delay: delay,
  );
}

const _retryableFailure = RpcTransportException(
  failure: RpcTransportFailure.timeout,
  message: 'timeout',
  retryable: true,
);

bool _shouldRetry(Object error) {
  return error is RpcTransportException && error.retryable;
}
