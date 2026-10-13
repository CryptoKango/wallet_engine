import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('AmountCodec', () {
    test('converts decimal amounts to exact base units', () {
      expect(
        AmountCodec.toBaseUnits(Decimal.parse('1.000000001'), decimals: 9),
        BigInt.from(1000000001),
      );
    });

    test('converts base units to decimal amounts', () {
      expect(
        AmountCodec.fromBaseUnits(BigInt.from(1234567), decimals: 6),
        Decimal.parse('1.234567'),
      );
    });

    test('rejects precision beyond chain decimals', () {
      expect(
        () => AmountCodec.toBaseUnits(Decimal.parse('0.0000001'), decimals: 6),
        throwsA(
          isA<WalletValidationException>().having(
            (error) => error.errorCode,
            'errorCode',
            'validation.invalidArgument',
          ),
        ),
      );
    });

    test('rounds fee rates upward only at protocol boundary', () {
      expect(AmountCodec.ceilToBigInt(Decimal.parse('1.01')), BigInt.two);
    });
  });
}
