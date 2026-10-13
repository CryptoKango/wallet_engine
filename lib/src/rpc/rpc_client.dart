import '../config/rpc_endpoint.dart';
import '../config/rpc_logging_config.dart';
import '../config/rpc_pool_config.dart';
import '../config/rpc_retry_config.dart';
import '../config/rpc_transport_config.dart';
import '../error/wallet_error.dart';
import 'rpc_endpoint_pool.dart';
import 'rpc_log_event.dart';
import 'rpc_request.dart';
import 'rpc_response.dart';
import 'rpc_transport.dart';

/// Chain-scoped RPC client with endpoint selection and failover.
final class RpcClient {
  factory RpcClient({
    required String chainKey,
    required RpcPoolConfig poolConfig,
    required RpcRetryConfig retryConfig,
    required RpcTransportConfig transportConfig,
    RpcLoggingConfig loggingConfig = const RpcLoggingConfig(),
    required RpcTransport transport,
    RpcLogSink? logSink,
  }) {
    return RpcClient._(
      transportConfig,
      transport,
      RpcEndpointPool(
        chainKey: chainKey,
        config: poolConfig,
        retry: retryConfig,
        logging: loggingConfig,
        logSink: logSink,
      ),
    );
  }

  RpcClient._(this._transportConfig, this._transport, this._pool);

  final RpcTransportConfig _transportConfig;
  final RpcTransport _transport;
  final RpcEndpointPool _pool;

  Future<RpcResponse> send(
    RpcRequest request, {
    RpcRetryPredicate? shouldRetry,
  }) {
    return execute<RpcResponse>(
      request,
      decode: (response) => response,
      shouldRetry: shouldRetry,
    );
  }

  /// Executes a protocol-specific operation against the managed endpoint pool.
  ///
  /// This is used by non-HTTP protocols such as Bitcoin Electrum while keeping
  /// endpoint ordering, cooldown, sanitized logging, and failover centralized.
  Future<T> executeOnEndpoint<T>({
    required String operation,
    required Future<T> Function(RpcEndpoint endpoint) attempt,
    RpcRetryPredicate? shouldRetry,
    Object? requestBody,
  }) {
    Object? latestResponseBody;
    return _pool.execute<T>(
      operation: operation,
      attempt: (endpoint) async {
        latestResponseBody = null;
        final result = await attempt(endpoint);
        latestResponseBody = result;
        return result;
      },
      shouldRetry: shouldRetry ?? _defaultRetryPredicate,
      requestBody: requestBody,
      responseBody: (result) => result,
      failureResponseBody: () => latestResponseBody,
    );
  }

  /// Sends and decodes inside the failover boundary so malformed protocol
  /// responses can retry another endpoint.
  Future<T> execute<T>(
    RpcRequest request, {
    required T Function(RpcResponse response) decode,
    RpcRetryPredicate? shouldRetry,
  }) {
    Object? latestResponseBody;
    return _pool.execute<T>(
      operation: request.operation,
      attempt: (endpoint) async {
        latestResponseBody = null;
        final response = await _transport.send(
          endpoint: endpoint,
          request: request,
          config: _transportConfig,
        );
        latestResponseBody = response.data;
        return decode(response);
      },
      shouldRetry: shouldRetry ?? _defaultRetryPredicate,
      requestBody: request.body,
      responseBody: (_) => latestResponseBody,
      failureResponseBody: () => latestResponseBody,
    );
  }

  static bool _defaultRetryPredicate(Object error) {
    return error is WalletError && error.retryable;
  }
}
