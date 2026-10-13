final class BitcoinTransactionReceipt {
  const BitcoinTransactionReceipt({
    required this.txHash,
    required this.confirmations,
    this.blockHeight,
  });

  final String txHash;
  final int confirmations;
  final int? blockHeight;
}
