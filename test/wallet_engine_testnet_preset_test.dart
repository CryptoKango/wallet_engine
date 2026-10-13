import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletEngineTestnetPreset', () {
    test('creates the runnable default test network suite', () {
      final config = WalletEngineTestnetPreset.create();

      expect(config.version, 'wallet-engine-testnet-v1');
      expect(config.chains.keys, <String>[
        WalletEngineTestnetPreset.ethereumSepoliaKey,
        WalletEngineTestnetPreset.solanaDevnetKey,
        WalletEngineTestnetPreset.tronNileKey,
        WalletEngineTestnetPreset.bitcoinTestnetKey,
      ]);
      expect(
        config.chains[WalletEngineTestnetPreset.ethereumSepoliaKey]!.chainId,
        '11155111',
      );
      expect(
        config.chains[WalletEngineTestnetPreset.bitcoinTestnetKey]!.chainId,
        '000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943',
      );
      expect(
        config.chains.values.map((chain) => chain.family).toSet(),
        <ChainFamily>{
          ChainFamily.evm,
          ChainFamily.solana,
          ChainFamily.tron,
          ChainFamily.bitcoin,
        },
      );
    });

    test('allows endpoint overrides without changing network metadata', () {
      final endpoint = RpcEndpoint.parse('https://sepolia.example.test');
      final chain = WalletEngineTestnetPreset.ethereumSepolia(
        endpoints: <RpcEndpoint>[endpoint],
      );

      expect(chain.rpcPool.endpoints, <RpcEndpoint>[endpoint]);
      expect(chain.network, 'sepolia');
      expect(chain.chainId, '11155111');
      expect(chain.nativeDecimals, 18);
    });

    test('includes legacy Sui only with an explicit endpoint', () {
      final endpoint = RpcEndpoint.parse('https://sui.example.test');
      final config = WalletEngineTestnetPreset.create(
        suiEndpoints: <RpcEndpoint>[endpoint],
      );

      final chain = config.chains[WalletEngineTestnetPreset.suiTestnetKey];
      expect(chain, isNotNull);
      expect(chain!.family, ChainFamily.sui);
      expect(chain.rpcPool.endpoints.single, same(endpoint));
    });

    test('default adapters cover every default preset chain', () {
      final configuredFamilies = WalletEngineTestnetPreset.create()
          .chains
          .values
          .map((chain) => chain.family)
          .toSet();
      final adapterFamilies = walletEngineDefaultAdapters()
          .map((adapter) => adapter.family)
          .toSet();

      expect(adapterFamilies, containsAll(configuredFamilies));
    });
  });
}
