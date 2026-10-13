import '../error/wallet_error.dart';

/// JSON-RPC 2.0 failure returned by a node or detected while decoding it.
final class JsonRpcException implements WalletError {
  const JsonRpcException({
    required this.message,
    required this.retryable,
    this.code,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final int? code;

  @override
  final String message;

  @override
  final bool retryable;

  @override
  WalletErrorCategory get category => WalletErrorCategory.rpc;

  @override
  WalletErrorCode get publicCode => code == null
      ? WalletErrorCode.rpcJsonRpcInvalidResponse
      : WalletErrorCode.rpcJsonRpcServerError;

  @override
  String get errorCode => publicCode.value;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() {
    final codeText = code == null ? '' : ' $code';
    return 'JsonRpcException$codeText: $message';
  }
}
