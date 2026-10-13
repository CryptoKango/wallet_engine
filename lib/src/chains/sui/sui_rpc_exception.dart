import '../../error/wallet_error.dart';

/// Stable Sui-specific classification of node failures.
final class SuiRpcException implements WalletError {
  const SuiRpcException({
    required this.publicCode,
    required this.message,
    required this.retryable,
    this.rpcCode,
    this.transactionNotFound = false,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  factory SuiRpcException.fromNode(
    int? code,
    String message,
    bool retryable,
    Map<String, Object?> context,
  ) {
    final normalized = message.toLowerCase();
    final publicCode = switch (normalized) {
      final value
          when value.contains('insufficientgas') ||
              value.contains('insufficient gas') =>
        WalletErrorCode.chainSuiInsufficientGas,
      final value
          when value.contains('balancetoolow') ||
              value.contains('insufficientbalance') ||
              value.contains('balance too low') =>
        WalletErrorCode.chainSuiInsufficientBalance,
      final value
          when value.contains('version mismatch') ||
              value.contains('objectnotfound') ||
              value.contains('object not found') ||
              value.contains('conflictingtransaction') =>
        WalletErrorCode.chainSuiObjectVersionConflict,
      final value
          when value.contains('invalidtransaction') ||
              value.contains('invalid transaction') =>
        WalletErrorCode.chainSuiInvalidTransaction,
      _ => WalletErrorCode.chainSuiRpc,
    };
    return SuiRpcException(
      publicCode: publicCode,
      message: _safeMessage(publicCode),
      retryable: retryable,
      rpcCode: code,
      transactionNotFound:
          normalized.contains('could not find') ||
          normalized.contains('not found') ||
          normalized.contains('no transaction'),
      context: context,
    );
  }

  final int? rpcCode;
  final bool transactionNotFound;

  @override
  WalletErrorCategory get category => WalletErrorCategory.chain;

  @override
  final WalletErrorCode publicCode;

  @override
  String get errorCode => publicCode.value;

  @override
  final String message;

  @override
  final bool retryable;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'SuiRpcException($errorCode): $message';

  static String _safeMessage(WalletErrorCode code) => switch (code) {
    WalletErrorCode.chainSuiInsufficientGas =>
      'Sui transaction has insufficient gas.',
    WalletErrorCode.chainSuiInsufficientBalance =>
      'Sui transaction has insufficient balance.',
    WalletErrorCode.chainSuiInvalidTransaction => 'Sui transaction is invalid.',
    WalletErrorCode.chainSuiObjectVersionConflict =>
      'Sui transaction inputs are stale and must be refreshed.',
    _ => 'Sui RPC operation failed.',
  };
}
