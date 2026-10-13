import 'chain_family.dart';
import 'rpc_endpoint.dart';
import 'rpc_logging_config.dart';
import 'rpc_pool_config.dart';
import 'rpc_retry_config.dart';
import 'rpc_transport_config.dart';
import 'wallet_chain_config.dart';
import 'wallet_engine_config.dart';

/// Built-in public test-network configuration for development and smoke tests.
///
/// Public endpoints are shared, rate-limited infrastructure. Applications can
/// replace any endpoint list while retaining the canonical network metadata.
abstract final class WalletEngineTestnetPreset {
  static const int presetVersion = 1;

  static const String ethereumSepoliaKey = 'ethereum-sepolia';
  static const String solanaDevnetKey = 'solana-devnet';
  static const String tronNileKey = 'tron-nile';
  static const String bitcoinTestnetKey = 'bitcoin-testnet';
  static const String suiTestnetKey = 'sui-testnet';

  /// Creates the default test suite.
  ///
  /// Sui is included only when [suiEndpoints] is provided because the official
  /// Sui public fullnode has retired the JSON-RPC protocol currently used by
  /// [SuiChainSession].
  static WalletEngineConfig create({
    int revision = 0,
    String version = 'wallet-engine-testnet-v1',
    Iterable<RpcEndpoint>? ethereumEndpoints,
    Iterable<RpcEndpoint>? solanaEndpoints,
    Iterable<RpcEndpoint>? tronEndpoints,
    Iterable<RpcEndpoint>? bitcoinEndpoints,
    Iterable<RpcEndpoint>? suiEndpoints,
    RpcTransportConfig transport = const RpcTransportConfig(),
    RpcRetryConfig retry = const RpcRetryConfig(),
    RpcLoggingConfig rpcLogging = const RpcLoggingConfig(),
  }) {
    return WalletEngineConfig(
      revision: revision,
      version: version,
      transport: transport,
      retry: retry,
      rpcLogging: rpcLogging,
      chains: <WalletChainConfig>[
        ethereumSepolia(endpoints: ethereumEndpoints),
        solanaDevnet(endpoints: solanaEndpoints),
        tronNile(endpoints: tronEndpoints),
        bitcoinTestnet(endpoints: bitcoinEndpoints),
        if (suiEndpoints != null) suiTestnet(endpoints: suiEndpoints),
      ],
    );
  }

  static WalletChainConfig ethereumSepolia({Iterable<RpcEndpoint>? endpoints}) {
    return WalletChainConfig(
      key: ethereumSepoliaKey,
      family: ChainFamily.evm,
      network: 'sepolia',
      chainId: '11155111',
      nativeSymbol: 'ETH',
      nativeDecimals: 18,
      rpcPool: _pool(endpoints, <String>[
        'https://ethereum-sepolia-rpc.publicnode.com',
        'https://rpc.sepolia.ethpandaops.io',
      ]),
    );
  }

  static WalletChainConfig solanaDevnet({Iterable<RpcEndpoint>? endpoints}) {
    return WalletChainConfig(
      key: solanaDevnetKey,
      family: ChainFamily.solana,
      network: 'devnet',
      nativeSymbol: 'SOL',
      nativeDecimals: 9,
      rpcPool: _pool(endpoints, const <String>[
        'https://api.devnet.solana.com',
      ]),
    );
  }

  static WalletChainConfig tronNile({Iterable<RpcEndpoint>? endpoints}) {
    return WalletChainConfig(
      key: tronNileKey,
      family: ChainFamily.tron,
      network: 'nile',
      nativeSymbol: 'TRX',
      nativeDecimals: 6,
      rpcPool: _pool(endpoints, const <String>['https://nile.trongrid.io']),
    );
  }

  static WalletChainConfig bitcoinTestnet({Iterable<RpcEndpoint>? endpoints}) {
    return WalletChainConfig(
      key: bitcoinTestnetKey,
      family: ChainFamily.bitcoin,
      network: 'testnet',
      chainId:
          '000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943',
      nativeSymbol: 'BTC',
      nativeDecimals: 8,
      rpcPool: _pool(endpoints, const <String>[
        'tls://electrum.blockstream.info:60002',
      ]),
    );
  }

  /// Legacy JSON-RPC Sui Testnet metadata.
  ///
  /// An endpoint is intentionally required; migrate the Sui adapter to gRPC
  /// before making this part of the default preset.
  static WalletChainConfig suiTestnet({
    required Iterable<RpcEndpoint> endpoints,
  }) {
    return WalletChainConfig(
      key: suiTestnetKey,
      family: ChainFamily.sui,
      network: 'testnet',
      nativeSymbol: 'SUI',
      nativeDecimals: 9,
      rpcPool: _pool(endpoints, const <String>[]),
    );
  }

  static RpcPoolConfig _pool(
    Iterable<RpcEndpoint>? endpoints,
    List<String> defaults,
  ) {
    final resolved =
        endpoints?.toList(growable: false) ??
        defaults.map(RpcEndpoint.parse).toList(growable: false);
    return RpcPoolConfig(endpoints: resolved);
  }
}
