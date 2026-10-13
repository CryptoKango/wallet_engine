/// Minimal, stable EVM transaction receipt representation.
final class EvmTransactionReceipt {
  const EvmTransactionReceipt({
    required this.transactionHash,
    required this.blockNumber,
    required this.success,
    required this.gasUsed,
  });

  final String transactionHash;
  final BigInt? blockNumber;
  final bool? success;
  final BigInt? gasUsed;
}
