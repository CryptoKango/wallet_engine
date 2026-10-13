import 'dart:typed_data';

import '../../signing/transaction_signer.dart';

final class TronUnsignedTransaction {
  TronUnsignedTransaction({required Uint8List rawData, required this.txId})
    : rawData = Uint8List.fromList(rawData);

  final Uint8List rawData;
  final String txId;
}

final class TronTransactionBuildResult {
  const TronTransactionBuildResult({
    required this.transaction,
    this.energyUsed,
  });

  final TronUnsignedTransaction transaction;
  final BigInt? energyUsed;
}

final class TronSignedTransaction {
  const TronSignedTransaction({
    required this.encodedTransaction,
    required this.txId,
  });

  /// Serialized TRON Transaction protobuf as lowercase hex.
  final String encodedTransaction;
  final String txId;
}

abstract interface class TronTransactionSigner
    implements
        TransactionSigner<TronUnsignedTransaction, TronSignedTransaction> {}
