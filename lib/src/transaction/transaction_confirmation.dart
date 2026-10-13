import '../error/wallet_error.dart';

/// Polling policy shared by chain-specific transaction confirmation helpers.
final class TransactionConfirmationPolicy {
  const TransactionConfirmationPolicy({
    this.timeout = const Duration(minutes: 2),
    this.pollInterval = const Duration(seconds: 2),
  });

  final Duration timeout;
  final Duration pollInterval;

  void validate() {
    if (timeout <= Duration.zero) {
      throw const WalletValidationException(
        field: 'timeout',
        message: 'Transaction confirmation timeout must be positive.',
      );
    }
    if (pollInterval <= Duration.zero) {
      throw const WalletValidationException(
        field: 'pollInterval',
        message: 'Transaction confirmation poll interval must be positive.',
      );
    }
  }
}

/// Cooperative cancellation token for long-running confirmation polling.
final class WalletCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Stable transaction lifecycle failure exposed to host applications.
final class WalletTransactionException implements WalletError {
  const WalletTransactionException({
    required this.publicCode,
    required this.message,
    this.retryable = false,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  @override
  WalletErrorCategory get category => WalletErrorCategory.transaction;

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
  String toString() => 'WalletTransactionException($errorCode): $message';
}

/// Transport-independent polling implementation used by every adapter.
abstract final class TransactionConfirmationWaiter {
  static Future<T> wait<T>({
    required Future<T?> Function() lookup,
    required bool Function(T value) isConfirmed,
    required String transactionId,
    required String chainKey,
    TransactionConfirmationPolicy policy =
        const TransactionConfirmationPolicy(),
    WalletCancellationToken? cancellationToken,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  }) async {
    policy.validate();
    final now = clock ?? DateTime.now;
    final pause = delay ?? Future<void>.delayed;
    final deadline = now().add(policy.timeout);

    while (true) {
      if (cancellationToken?.isCancelled ?? false) {
        throw WalletTransactionException(
          publicCode: WalletErrorCode.transactionConfirmationCancelled,
          message: 'Transaction confirmation was cancelled.',
          context: <String, Object?>{
            'chainKey': chainKey,
            'transactionId': transactionId,
          },
        );
      }

      final value = await lookup();
      if (value != null && isConfirmed(value)) return value;

      final remaining = deadline.difference(now());
      if (remaining <= Duration.zero) {
        throw WalletTransactionException(
          publicCode: WalletErrorCode.transactionConfirmationTimeout,
          message: 'Transaction confirmation timed out.',
          retryable: true,
          context: <String, Object?>{
            'chainKey': chainKey,
            'transactionId': transactionId,
            'timeoutMs': policy.timeout.inMilliseconds,
          },
        );
      }
      await pause(
        remaining < policy.pollInterval ? remaining : policy.pollInterval,
      );
    }
  }
}
