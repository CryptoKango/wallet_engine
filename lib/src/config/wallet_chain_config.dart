import 'chain_family.dart';
import 'rpc_pool_config.dart';

/// Immutable configuration for one host-defined chain.
final class WalletChainConfig {
  const WalletChainConfig({
    required this.key,
    required this.family,
    required this.network,
    required this.nativeSymbol,
    required this.nativeDecimals,
    required this.rpcPool,
    this.chainId,
  }) : assert(key != '', 'key must not be empty'),
       assert(network != '', 'network must not be empty'),
       assert(nativeSymbol != '', 'nativeSymbol must not be empty'),
       assert(nativeDecimals >= 0, 'nativeDecimals must not be negative');

  /// Stable identifier chosen by the host, such as `ethereum` or `tron`.
  final String key;

  final ChainFamily family;
  final String network;

  /// String representation avoids integer precision loss at integration
  /// boundaries and supports protocols that do not use numeric chain IDs.
  final String? chainId;

  final String nativeSymbol;
  final int nativeDecimals;
  final RpcPoolConfig rpcPool;
}
