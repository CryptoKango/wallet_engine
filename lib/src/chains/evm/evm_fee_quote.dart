import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../error/wallet_error.dart';

/// Host-selectable EVM fee calculation policy.
final class EvmFeePolicy {
  const EvmFeePolicy({
    this.preferEip1559 = true,
    this.baseFeeMultiplierNumerator = 2,
    this.baseFeeMultiplierDenominator = 1,
  }) : assert(baseFeeMultiplierNumerator > 0),
       assert(baseFeeMultiplierDenominator > 0);

  final bool preferEip1559;
  final int baseFeeMultiplierNumerator;
  final int baseFeeMultiplierDenominator;
}

/// Estimated gas limit and fee fields suitable for transaction construction.
final class EvmFeeQuote {
  const EvmFeeQuote.legacy({required this.gasLimit, required this.gasPrice})
    : maxPriorityFeePerGas = null,
      maxFeePerGas = null;

  const EvmFeeQuote.eip1559({
    required this.gasLimit,
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
  }) : gasPrice = null;

  final BigInt gasLimit;
  final BigInt? gasPrice;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? maxFeePerGas;

  bool get isEip1559 => maxFeePerGas != null;

  EvmFeeQuote withGasLimit(BigInt value) {
    if (value.isNegative) {
      throw const WalletValidationException(
        field: 'value',
        message: 'Gas limit must not be negative.',
      );
    }
    return isEip1559
        ? EvmFeeQuote.eip1559(
            gasLimit: value,
            maxPriorityFeePerGas: maxPriorityFeePerGas!,
            maxFeePerGas: maxFeePerGas!,
          )
        : EvmFeeQuote.legacy(gasLimit: value, gasPrice: gasPrice!);
  }

  BigInt get maximumCostBaseUnits {
    final unitPrice = maxFeePerGas ?? gasPrice;
    if (unitPrice == null) {
      throw const WalletStateException(message: 'Fee quote has no unit price.');
    }
    return gasLimit * unitPrice;
  }

  Decimal maximumCost({required int nativeDecimals}) {
    return AmountCodec.fromBaseUnits(
      maximumCostBaseUnits,
      decimals: nativeDecimals,
    );
  }
}
