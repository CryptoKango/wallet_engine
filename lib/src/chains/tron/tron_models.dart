import 'package:decimal/decimal.dart';

final class TronBlockHeader {
  const TronBlockHeader({
    required this.timestamp,
    required this.txTrieRoot,
    required this.parentHash,
    required this.number,
    required this.witnessAddress,
    required this.version,
  });

  final BigInt timestamp;
  final String txTrieRoot;
  final String parentHash;
  final BigInt number;
  final String witnessAddress;
  final int version;
}

final class TronTransactionReceipt {
  TronTransactionReceipt({
    required this.txHash,
    required this.success,
    required this.blockNumber,
    required this.fee,
    BigInt? energyUsage,
    BigInt? netUsage,
    this.result,
    this.error,
  }) : energyUsage = energyUsage ?? BigInt.zero,
       netUsage = netUsage ?? BigInt.zero;

  final String txHash;
  final bool success;
  final BigInt blockNumber;
  final Decimal fee;
  final BigInt energyUsage;
  final BigInt netUsage;
  final String? result;
  final String? error;
}

final class TronFeeSchedule {
  const TronFeeSchedule({
    required this.transactionFee,
    required this.energyFee,
    required this.createAccountFee,
  });

  final Decimal transactionFee;
  final Decimal energyFee;
  final Decimal createAccountFee;
}
