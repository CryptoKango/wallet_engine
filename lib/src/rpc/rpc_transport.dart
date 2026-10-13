import '../config/rpc_endpoint.dart';
import '../config/rpc_transport_config.dart';
import 'rpc_request.dart';
import 'rpc_response.dart';

/// Performs one request against one selected endpoint.
///
/// Endpoint selection, cooldown, and failover are handled by [RpcClient].
abstract interface class RpcTransport {
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  });
}

/// Optional lifecycle implemented by transports that own sockets or clients.
abstract interface class ClosableRpcTransport {
  Future<void> close();
}
