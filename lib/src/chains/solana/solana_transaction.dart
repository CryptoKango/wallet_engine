import 'package:decimal/decimal.dart';

import '../../signing/transaction_signer.dart';

sealed class SolanaUnsignedTransaction {
  const SolanaUnsignedTransaction({
    required this.recentBlockhash,
    this.priorityFeeLimit,
    this.priorityFeePrice,
  });

  final String recentBlockhash;
  final int? priorityFeeLimit;
  final BigInt? priorityFeePrice;
}

final class SolanaTransferTransaction extends SolanaUnsignedTransaction {
  SolanaTransferTransaction({
    required super.recentBlockhash,
    required this.recipient,
    required this.amount,
    super.priorityFeeLimit,
    super.priorityFeePrice,
  }) : assert(recipient != '', 'recipient must not be empty'),
       assert(amount > Decimal.zero, 'amount must be positive');

  final String recipient;
  final Decimal amount;
}

final class SolanaTokenTransferTransaction extends SolanaUnsignedTransaction {
  SolanaTokenTransferTransaction({
    required super.recentBlockhash,
    required this.recipientMainAddress,
    required this.tokenMintAddress,
    required this.senderTokenAddress,
    required this.amount,
    required this.decimals,
    this.recipientTokenAddress,
    this.token2022 = false,
    super.priorityFeeLimit,
    super.priorityFeePrice,
  }) : assert(recipientMainAddress != ''),
       assert(tokenMintAddress != ''),
       assert(senderTokenAddress != ''),
       assert(amount > Decimal.zero),
       assert(decimals >= 0);

  final String recipientMainAddress;
  final String tokenMintAddress;
  final String senderTokenAddress;
  final String? recipientTokenAddress;
  final Decimal amount;
  final int decimals;
  final bool token2022;
}

final class SolanaSignedTransaction {
  const SolanaSignedTransaction({required this.base64Transaction});

  final String base64Transaction;
}

abstract interface class SolanaTransactionSigner
    implements
        TransactionSigner<SolanaUnsignedTransaction, SolanaSignedTransaction> {}
