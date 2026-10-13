final class SolanaTransactionReceipt {
  const SolanaTransactionReceipt({
    required this.signature,
    required this.slot,
    required this.confirmationStatus,
    required this.success,
  });

  final String signature;
  final int? slot;
  final String? confirmationStatus;
  final bool success;

  bool get finalized => confirmationStatus == 'finalized';
}
