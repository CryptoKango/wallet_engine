import '../config/rpc_endpoint.dart';

/// Supplies runtime-only authorization headers for an RPC endpoint.
///
/// Implementations must never persist credentials in an engine configuration
/// snapshot or include them in logs.
abstract interface class RpcCredentialProvider {
  Future<Map<String, String>> headersFor(RpcEndpoint endpoint);
}
