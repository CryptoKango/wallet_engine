import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  test(
    'Sui adapter delegates through an injected production gateway',
    () async {
      final gateway = _FakeSuiGateway();
      final engine = WalletEngine(
        config: _config(),
        adapters: <ChainAdapter>[
          SuiChainAdapter(gatewayFactory: (_, _) => gateway),
        ],
        transport: const _UnusedTransport(),
      );

      final session = engine.sessionAs<SuiChainSession>('sui');
      expect(
        await session.getBalance('0x${'1'.padLeft(64, '0')}'),
        Decimal.parse('0.000000042'),
      );
      expect(gateway.operations, <String>['getBalanceBaseUnits']);

      await engine.close();
      expect(gateway.closed, isTrue);
    },
  );
}

WalletEngineConfig _config() {
  return WalletEngineConfig(
    revision: 1,
    version: 'sui-gateway-test',
    chains: <WalletChainConfig>[
      WalletChainConfig(
        key: 'sui',
        family: ChainFamily.sui,
        network: 'mainnet',
        nativeSymbol: 'SUI',
        nativeDecimals: 9,
        rpcPool: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://fullnode.example.com'),
          ],
        ),
      ),
    ],
  );
}

final class _FakeSuiGateway implements SuiGateway {
  final List<String> operations = <String>[];
  bool closed = false;

  @override
  Future<BigInt> getBalanceBaseUnits({
    required String address,
    String? coinType,
  }) async {
    operations.add('getBalanceBaseUnits');
    return BigInt.from(42);
  }

  @override
  Future<void> close() async => closed = true;

  @override
  Future<SuiGasCostSummary> dryRun(String txBytes) =>
      throw StateError('Unexpected Sui dry-run.');

  @override
  Future<String> executeTransaction(SuiSignedTransaction transaction) =>
      throw StateError('Unexpected Sui transaction execution.');

  @override
  Future<SuiCoinPage> getCoins({
    required String address,
    String? coinType,
    String? cursor,
    required int limit,
  }) => throw StateError('Unexpected Sui coin query.');

  @override
  Future<String> getChainIdentifier() =>
      throw StateError('Unexpected Sui chain identifier query.');

  @override
  Future<String> getLatestCheckpointSequenceNumber() =>
      throw StateError('Unexpected Sui checkpoint query.');

  @override
  Future<BigInt> getReferenceGasPrice() =>
      throw StateError('Unexpected Sui gas-price query.');

  @override
  Future<SuiTransactionReceipt?> getTransactionReceipt(String digest) =>
      throw StateError('Unexpected Sui transaction query.');
}

final class _UnusedTransport implements RpcTransport {
  const _UnusedTransport();

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) {
    throw StateError('Injected Sui gateway must bypass the legacy transport.');
  }
}
