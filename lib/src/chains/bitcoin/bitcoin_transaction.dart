import 'package:decimal/decimal.dart';

import '../../signing/transaction_signer.dart';

final class BitcoinUtxo {
  const BitcoinUtxo({
    required this.txHash,
    required this.vout,
    required this.amount,
    required this.script,
  });

  final String txHash;
  final int vout;
  final Decimal amount;
  final String script;
}

final class BitcoinUnsignedTransaction {
  const BitcoinUnsignedTransaction({
    required this.utxos,
    required this.toAddress,
    required this.changeAddress,
    required this.amount,
    required this.feeRateSatPerVbyte,
  });

  final List<BitcoinUtxo> utxos;
  final String toAddress;
  final String changeAddress;
  final Decimal amount;
  final Decimal feeRateSatPerVbyte;
}

final class BitcoinSignedTransaction {
  const BitcoinSignedTransaction({required this.hex});

  final String hex;
}

abstract interface class BitcoinTransactionSigner
    implements
        TransactionSigner<
          BitcoinUnsignedTransaction,
          BitcoinSignedTransaction
        > {}
