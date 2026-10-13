import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('TransactionConfirmationWaiter', () {
    test('returns after the completion predicate succeeds', () async {
      var calls = 0;
      final result = await TransactionConfirmationWaiter.wait<int>(
        lookup: () async => ++calls,
        isConfirmed: (value) => value >= 3,
        transactionId: 'tx',
        chainKey: 'chain',
        policy: const TransactionConfirmationPolicy(
          timeout: Duration(seconds: 1),
          pollInterval: Duration(milliseconds: 1),
        ),
      );

      expect(result, 3);
      expect(calls, 3);
    });

    test('supports cooperative cancellation with a stable code', () async {
      final token = WalletCancellationToken()..cancel();

      await expectLater(
        TransactionConfirmationWaiter.wait<int>(
          lookup: () async => null,
          isConfirmed: (_) => false,
          transactionId: 'tx',
          chainKey: 'chain',
          cancellationToken: token,
        ),
        throwsA(
          isA<WalletTransactionException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.transactionConfirmationCancelled,
          ),
        ),
      );
    });

    test('times out with retryable diagnostics', () async {
      var now = DateTime.utc(2026);

      await expectLater(
        TransactionConfirmationWaiter.wait<int>(
          lookup: () async => null,
          isConfirmed: (_) => false,
          transactionId: 'tx',
          chainKey: 'chain',
          policy: const TransactionConfirmationPolicy(
            timeout: Duration(milliseconds: 2),
            pollInterval: Duration(milliseconds: 1),
          ),
          clock: () => now,
          delay: (duration) async => now = now.add(duration),
        ),
        throwsA(
          isA<WalletTransactionException>()
              .having(
                (error) => error.publicCode,
                'publicCode',
                WalletErrorCode.transactionConfirmationTimeout,
              )
              .having((error) => error.retryable, 'retryable', isTrue),
        ),
      );
    });
  });
}
