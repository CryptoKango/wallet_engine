import '../chain/chain_adapter.dart';
import '../chains/bitcoin/bitcoin_chain_adapter.dart';
import '../chains/evm/evm_chain_adapter.dart';
import '../chains/solana/solana_chain_adapter.dart';
import '../chains/sui/sui_chain_adapter.dart';
import '../chains/tron/tron_chain_adapter.dart';

/// Built-in adapters implemented by wallet_engine.
///
/// The default Sui adapter uses the legacy JSON-RPC compatibility gateway.
/// Production applications should override [sui] with a gRPC v2-backed
/// [SuiChainAdapter].
List<ChainAdapter> walletEngineDefaultAdapters({
  SuiChainAdapter sui = const SuiChainAdapter(),
}) {
  return <ChainAdapter>[
    const EvmChainAdapter(),
    const SolanaChainAdapter(),
    sui,
    const TronChainAdapter(),
    BitcoinChainAdapter(),
  ];
}
