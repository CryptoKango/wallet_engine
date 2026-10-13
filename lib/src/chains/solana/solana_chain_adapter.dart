import '../../chain/chain_adapter.dart';
import '../../chain/chain_session.dart';
import '../../config/chain_family.dart';
import '../../config/wallet_chain_config.dart';
import '../../rpc/json_rpc_client.dart';
import '../../rpc/rpc_client.dart';
import 'solana_chain_session.dart';

final class SolanaChainAdapter implements ChainAdapter {
  const SolanaChainAdapter();

  @override
  ChainFamily get family => ChainFamily.solana;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return SolanaChainSession(
      config: config,
      rpc: JsonRpcClient(rpc: rpc),
    );
  }
}
