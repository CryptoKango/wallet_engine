import '../../chain/chain_adapter.dart';
import '../../chain/chain_session.dart';
import '../../config/chain_family.dart';
import '../../config/wallet_chain_config.dart';
import '../../rpc/json_rpc_client.dart';
import '../../rpc/rpc_client.dart';
import 'evm_chain_session.dart';

/// Default adapter for EVM-compatible chains.
final class EvmChainAdapter implements ChainAdapter {
  const EvmChainAdapter();

  @override
  ChainFamily get family => ChainFamily.evm;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return EvmChainSession(
      config: config,
      rpc: JsonRpcClient(rpc: rpc),
    );
  }
}
