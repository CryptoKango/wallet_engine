import 'package:decimal/decimal.dart';

import '../../signing/transaction_signer.dart';

final class SuiObjectRef {
  const SuiObjectRef({
    required this.objectId,
    required this.version,
    required this.digest,
  });

  final String objectId;
  final BigInt version;
  final String digest;
}

final class SuiCoinRef extends SuiObjectRef {
  const SuiCoinRef({
    required super.objectId,
    required super.version,
    required super.digest,
    required this.coinType,
    required this.balance,
  });

  final String coinType;
  final Decimal balance;
}

sealed class SuiUnsignedTransaction {
  const SuiUnsignedTransaction();
}

final class SuiRawJsonTransaction extends SuiUnsignedTransaction {
  const SuiRawJsonTransaction({required this.rawJson});

  final String rawJson;
}

final class SuiPaySuiTransaction extends SuiUnsignedTransaction {
  const SuiPaySuiTransaction({
    required this.inputCoins,
    required this.recipients,
    required this.amounts,
    required this.decimals,
    required this.gasBudget,
    required this.referenceGasPrice,
  });

  final List<SuiObjectRef> inputCoins;
  final List<String> recipients;
  final List<Decimal> amounts;
  final int decimals;
  final BigInt gasBudget;
  final BigInt referenceGasPrice;
}

final class SuiPayTransaction extends SuiUnsignedTransaction {
  const SuiPayTransaction({
    required this.inputCoins,
    required this.recipients,
    required this.amounts,
    required this.decimals,
    required this.gas,
    required this.gasBudget,
    required this.referenceGasPrice,
  });

  final List<SuiObjectRef> inputCoins;
  final List<String> recipients;
  final List<Decimal> amounts;
  final int decimals;
  final SuiObjectRef gas;
  final BigInt gasBudget;
  final BigInt referenceGasPrice;
}

final class SuiSignedTransaction {
  const SuiSignedTransaction({required this.txBytes, required this.signature});

  final String txBytes;
  final String signature;
}

abstract interface class SuiTransactionSigner
    implements
        TransactionSigner<SuiUnsignedTransaction, SuiSignedTransaction> {}
