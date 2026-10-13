import 'package:decimal/decimal.dart';

import '../../signing/transaction_signer.dart';

final class ProvenanceTransferTransaction {
  const ProvenanceTransferTransaction({
    required this.accountNumber,
    required this.chainId,
    required this.sequence,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.decimals,
    required this.denom,
    required this.feeAmount,
    required this.feeDecimals,
    required this.feeDenom,
    required this.gas,
    this.memo = '',
  });

  final BigInt accountNumber;
  final String chainId;
  final BigInt sequence;
  final String fromAddress;
  final String toAddress;
  final Decimal amount;
  final int decimals;
  final String denom;
  final Decimal feeAmount;
  final int feeDecimals;
  final String feeDenom;
  final BigInt gas;
  final String memo;
}

final class ProvenanceSignedTransaction {
  const ProvenanceSignedTransaction({required this.base64Signature});

  final String base64Signature;
}

abstract interface class ProvenanceTransactionSigner
    implements
        TransactionSigner<
          ProvenanceTransferTransaction,
          ProvenanceSignedTransaction
        > {}
