import '../../chain/chain_adapter.dart';
import '../../chain/chain_session.dart';
import '../../config/chain_family.dart';
import '../../config/wallet_chain_config.dart';
import '../../rpc/rpc_client.dart';
import 'sui_chain_session.dart';
import 'sui_gateway.dart';

final class SuiChainAdapter implements ChainAdapter {
  const SuiChainAdapter({this.gatewayFactory});

  /// Inject a current Sui gRPC v2 implementation for production. When absent,
  /// the adapter uses deprecated JSON-RPC compatibility mode.
  final SuiGatewayFactory? gatewayFactory;

  @override
  ChainFamily get family => ChainFamily.sui;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return SuiChainSession.withGateway(
      config: config,
      gateway:
          gatewayFactory?.call(config, rpc) ?? LegacySuiJsonRpcGateway(rpc),
    );
  }
}
