import '../config/chain_family.dart';
import '../config/wallet_chain_config.dart';
import '../rpc/rpc_client.dart';
import 'chain_session.dart';

/// Opens runtime sessions for one protocol family.
abstract interface class ChainAdapter {
  ChainFamily get family;

  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  });
}
