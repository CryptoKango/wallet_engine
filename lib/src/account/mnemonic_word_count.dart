/// BIP-39 mnemonic sizes supported by wallet_engine.
enum MnemonicWordCount {
  words12(12, 128),
  words24(24, 256);

  const MnemonicWordCount(this.value, this.strengthBits);

  /// Number of words returned to the caller.
  final int value;

  /// Entropy strength used by BIP-39 generation.
  final int strengthBits;
}
