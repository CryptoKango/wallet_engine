import '../../chain/chain_adapter.dart';
import '../../chain/chain_session.dart';
import '../../config/chain_family.dart';
import '../../config/wallet_chain_config.dart';
import '../../rpc/rpc_client.dart';
import 'bitcoin_chain_session.dart';
import 'electrum_transport.dart';

typedef ElectrumTransportFactory = ElectrumTransport Function();

final class BitcoinChainAdapter implements ChainAdapter {
  factory BitcoinChainAdapter({
    ElectrumTransportFactory transportFactory = _defaultTransport,
  }) {
    return BitcoinChainAdapter._(transportFactory);
  }

  const BitcoinChainAdapter._(this._transportFactory);

  final ElectrumTransportFactory _transportFactory;

  @override
  ChainFamily get family => ChainFamily.bitcoin;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return BitcoinChainSession(
      config: config,
      rpc: rpc,
      transport: _transportFactory(),
    );
  }

  static ElectrumTransport _defaultTransport() {
    return const SocketElectrumTransport();
  }
}
