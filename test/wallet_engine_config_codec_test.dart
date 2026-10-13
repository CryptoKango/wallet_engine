import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletEngineConfigCodec', () {
    test('round-trips a complete configuration snapshot', () {
      final original = WalletEngineConfig(
        revision: 7,
        version: '2026.10.12',
        issuedAt: DateTime.utc(2026, 10, 12),
        expiresAt: DateTime.utc(2026, 10, 13),
        transport: const RpcTransportConfig(
          connectTimeout: Duration(seconds: 3),
          sendTimeout: Duration(seconds: 4),
          receiveTimeout: Duration(seconds: 5),
        ),
        retry: const RpcRetryConfig(
          maxAttempts: 2,
          endpointCooldown: Duration(seconds: 11),
        ),
        rpcLogging: const RpcLoggingConfig(
          includeRequestBody: true,
          includeResponseBody: true,
          maxBodyCharacters: 2048,
        ),
        chains: <WalletChainConfig>[
          WalletChainConfig(
            key: 'ethereum',
            family: ChainFamily.evm,
            network: 'mainnet',
            chainId: '1',
            nativeSymbol: 'ETH',
            nativeDecimals: 18,
            rpcPool: RpcPoolConfig(
              strategy: RpcSelectionStrategy.roundRobin,
              endpoints: <RpcEndpoint>[
                RpcEndpoint.parse(
                  'https://rpc.example.com/path',
                  priority: 3,
                  headers: const <String, String>{'X-Client': 'wallet'},
                ),
                RpcEndpoint.parse(
                  'http://127.0.0.1:8545',
                  allowInsecureTransport: true,
                ),
              ],
            ),
          ),
        ],
      );

      final decoded = WalletEngineConfigCodec.decode(
        WalletEngineConfigCodec.encode(original),
      );

      expect(decoded.revision, 7);
      expect(decoded.version, '2026.10.12');
      expect(decoded.expiresAt, DateTime.utc(2026, 10, 13));
      expect(decoded.transport.receiveTimeout, const Duration(seconds: 5));
      expect(decoded.retry.endpointCooldown, const Duration(seconds: 11));
      expect(decoded.retry.initialBackoff, const Duration(milliseconds: 200));
      expect(decoded.retry.maxBackoff, const Duration(seconds: 2));
      expect(decoded.rpcLogging.bodyMode, RpcLogBodyMode.redacted);
      expect(
        decoded.chains['ethereum']!.rpcPool.strategy,
        RpcSelectionStrategy.roundRobin,
      );
      expect(
        decoded.chains['ethereum']!.rpcPool.endpoints.first.headers,
        const <String, String>{'X-Client': 'wallet'},
      );
      expect(
        decoded
            .chains['ethereum']!
            .rpcPool
            .endpoints
            .last
            .allowInsecureTransport,
        isTrue,
      );
    });

    test('rejects an unsupported schema version with a stable code', () {
      expect(
        () => WalletEngineConfigCodec.decode(<String, Object?>{
          'schemaVersion': 99,
        }),
        throwsA(
          isA<WalletError>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.configurationSchemaUnsupported,
          ),
        ),
      );
    });
  });

  test('WalletEngine rejects an expired snapshot', () {
    final config = WalletEngineConfig(
      revision: 1,
      version: 'expired',
      issuedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 2),
      chains: <WalletChainConfig>[
        WalletChainConfig(
          key: 'ethereum',
          family: ChainFamily.evm,
          network: 'mainnet',
          chainId: '1',
          nativeSymbol: 'ETH',
          nativeDecimals: 18,
          rpcPool: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('https://rpc.example.com'),
            ],
          ),
        ),
      ],
    );

    expect(
      () => WalletEngine(
        config: config,
        adapters: const <ChainAdapter>[],
        transport: _NoopTransport(),
        clock: () => DateTime.utc(2026, 1, 3),
      ),
      throwsA(
        isA<WalletError>().having(
          (error) => error.publicCode,
          'publicCode',
          WalletErrorCode.configurationExpired,
        ),
      ),
    );
  });
}

final class _NoopTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) {
    throw StateError('RPC must not run while validating an expired snapshot.');
  }
}
