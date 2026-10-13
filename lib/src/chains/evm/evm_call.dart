import '../../error/wallet_error.dart';

/// EVM call/transaction fields shared by `eth_call` and `eth_estimateGas`.
final class EvmCall {
  const EvmCall({required this.to, this.from, this.data, this.valueBaseUnits})
    : assert(to != '', 'to must not be empty');

  final String to;
  final String? from;
  final String? data;

  /// Protocol-level native value in wei-like base units.
  final BigInt? valueBaseUnits;

  Map<String, Object> toJson() {
    final encodedValue = valueBaseUnits == null
        ? null
        : _encodeQuantity(valueBaseUnits!);
    return <String, Object>{
      'to': to,
      'from': ?from,
      'data': ?data,
      'value': ?encodedValue,
    };
  }

  static String _encodeQuantity(BigInt value) {
    if (value.isNegative) {
      throw const WalletValidationException(
        field: 'valueBaseUnits',
        message: 'EVM value must not be negative.',
      );
    }
    return '0x${value.toRadixString(16)}';
  }
}
