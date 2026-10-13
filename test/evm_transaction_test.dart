import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('EvmSignedTransaction', () {
    test('normalizes the hex prefix', () {
      expect(EvmSignedTransaction('abcd').rawTransaction, '0xabcd');
      expect(EvmSignedTransaction('0Xabcd').rawTransaction, '0xabcd');
    });

    test('rejects an empty raw transaction', () {
      final matcher = throwsA(isA<WalletValidationException>());
      expect(() => EvmSignedTransaction('  '), matcher);
      expect(() => EvmSignedTransaction('0x'), matcher);
      expect(() => EvmSignedTransaction('0xnot-hex'), matcher);
    });
  });

  test('fee quote can replace gas limit without changing fee mode', () {
    final quote = EvmFeeQuote.eip1559(
      gasLimit: BigInt.from(21000),
      maxPriorityFeePerGas: BigInt.two,
      maxFeePerGas: BigInt.from(10),
    );

    final updated = quote.withGasLimit(BigInt.from(30000));

    expect(updated.gasLimit, BigInt.from(30000));
    expect(updated.isEip1559, isTrue);
    expect(updated.maxPriorityFeePerGas, BigInt.two);
    expect(updated.maxFeePerGas, BigInt.from(10));
  });
}
