final class SuiTransactionReceipt {
  const SuiTransactionReceipt({
    required this.digest,
    required this.status,
    this.error,
    this.checkpoint,
    this.timestampMs,
  });

  final String digest;
  final String status;
  final String? error;
  final String? checkpoint;
  final String? timestampMs;

  bool get success => status == 'success';
}

final class SuiGasCostSummary {
  const SuiGasCostSummary({
    required this.computationCost,
    required this.storageCost,
    required this.storageRebate,
  });

  final BigInt computationCost;
  final BigInt storageCost;
  final BigInt storageRebate;

  BigInt get netCost {
    final value = computationCost + storageCost - storageRebate;
    return value.isNegative ? BigInt.zero : value;
  }
}
