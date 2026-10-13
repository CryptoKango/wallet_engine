import 'package:decimal/decimal.dart';

import '../error/wallet_error.dart';

/// Exact conversion between user-facing decimal amounts and protocol base
/// units. Floating-point values are deliberately not accepted.
final class AmountCodec {
  AmountCodec._();

  static BigInt toBaseUnits(
    Decimal amount, {
    required int decimals,
    bool allowZero = true,
  }) {
    if (decimals < 0) {
      throw const WalletValidationException(
        field: 'decimals',
        message: 'Decimals must not be negative.',
      );
    }
    if (amount < Decimal.zero || (!allowZero && amount == Decimal.zero)) {
      throw const WalletValidationException(
        field: 'amount',
        message: 'Amount must be positive.',
      );
    }
    final shifted = amount.shift(decimals);
    if (!shifted.isInteger) {
      throw WalletValidationException(
        field: 'amount',
        message: 'Amount has more than $decimals fractional digits.',
      );
    }
    return shifted.toBigInt();
  }

  static Decimal fromBaseUnits(BigInt amount, {required int decimals}) {
    if (decimals < 0) {
      throw const WalletValidationException(
        field: 'decimals',
        message: 'Decimals must not be negative.',
      );
    }
    return Decimal.fromBigInt(amount).shift(-decimals);
  }

  static BigInt ceilToBigInt(Decimal value) => value.ceil().toBigInt();
}
