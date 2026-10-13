/// Immutable provenance requirements for the native Wallet Core bridge.
final class WalletCoreBridgeManifest {
  const WalletCoreBridgeManifest({
    required this.abiVersion,
    required this.upstreamVersion,
    required this.upstreamCommit,
    required this.sourceRepository,
    required this.license,
  });

  /// Version of the C ABI owned by `wallet_engine`.
  final int abiVersion;

  /// Pinned upstream Trust Wallet Core release.
  final String upstreamVersion;

  /// Full Git commit required at runtime and during artifact production.
  final String upstreamCommit;

  /// Canonical source repository used by the reproducible build pipeline.
  final String sourceRepository;

  /// SPDX identifier reviewed for the pinned source.
  final String license;
}

/// Production pin for the first-party native bridge.
///
/// Keep this value synchronized with `native/wallet-core.lock.json`. Native
/// artifacts with different metadata are rejected before signing is enabled.
const walletCoreProductionManifest = WalletCoreBridgeManifest(
  abiVersion: 2,
  upstreamVersion: '4.8.4',
  upstreamCommit: 'd40d24a63d92619167903369308bf0e2f7eb3a59',
  sourceRepository: 'https://github.com/trustwallet/wallet-core.git',
  license: 'Apache-2.0',
);
