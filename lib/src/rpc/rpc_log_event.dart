/// RPC lifecycle event. It always excludes URLs, paths, headers, and
/// credentials. Request and response bodies are present only when explicitly
/// enabled by the host configuration.
final class RpcLogEvent {
  const RpcLogEvent({
    required this.type,
    required this.chainKey,
    required this.operation,
    required this.endpointHost,
    required this.attempt,
    required this.endpointCount,
    this.duration,
    this.errorType,
    this.errorCode,
    this.retryable,
    this.requestBody,
    this.responseBody,
  });

  final RpcLogEventType type;
  final String chainKey;
  final String operation;
  final String endpointHost;
  final int attempt;
  final int endpointCount;
  final Duration? duration;
  final String? errorType;
  final String? errorCode;
  final bool? retryable;

  /// Serialized, length-limited request body. May contain sensitive data.
  final String? requestBody;

  /// Serialized, length-limited response body. May contain sensitive data.
  final String? responseBody;
}

enum RpcLogEventType { attempt, success, failure }

typedef RpcLogSink = void Function(RpcLogEvent event);
