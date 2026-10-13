import '../error/wallet_error.dart';

/// Transport failure category used by the default failover policy.
enum RpcTransportFailure {
  timeout,
  connection,
  invalidResponse,
  httpStatus,
  cancelled,
  unknown,
}

/// Sanitized transport exception.
///
/// The exception deliberately excludes endpoint URLs, credentials, request
/// bodies, and response bodies.
final class RpcTransportException implements WalletError {
  const RpcTransportException({
    required this.failure,
    required this.message,
    required this.retryable,
    this.statusCode,
    this.retryAfter,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final RpcTransportFailure failure;

  @override
  final String message;

  @override
  final bool retryable;

  final int? statusCode;
  final Duration? retryAfter;

  @override
  WalletErrorCategory get category => WalletErrorCategory.transport;

  @override
  WalletErrorCode get publicCode => switch (failure) {
    RpcTransportFailure.timeout => WalletErrorCode.rpcTransportTimeout,
    RpcTransportFailure.connection => WalletErrorCode.rpcTransportConnection,
    RpcTransportFailure.invalidResponse =>
      WalletErrorCode.rpcTransportInvalidResponse,
    RpcTransportFailure.httpStatus => WalletErrorCode.rpcTransportHttpStatus,
    RpcTransportFailure.cancelled => WalletErrorCode.rpcTransportCancelled,
    RpcTransportFailure.unknown => WalletErrorCode.rpcTransportUnknown,
  };

  @override
  String get errorCode => publicCode.value;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'RpcTransportException(${failure.name}): $message';
}
