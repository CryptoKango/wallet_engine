import '../../chain/chain_adapter.dart';
import '../../chain/chain_session.dart';
import '../../config/chain_family.dart';
import '../../config/wallet_chain_config.dart';
import '../../rpc/rpc_client.dart';
import 'tron_chain_session.dart';

final class TronChainAdapter implements ChainAdapter {
  const TronChainAdapter();

  @override
  ChainFamily get family => ChainFamily.tron;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return TronChainSession(config: config, rpc: rpc);
  }
}
