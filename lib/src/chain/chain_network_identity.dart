import '../config/chain_family.dart';

/// Observed network identity returned by a chain node.
final class ChainNetworkIdentity {
  const ChainNetworkIdentity({
    required this.family,
    required this.configured,
    required this.observed,
  });

  final ChainFamily family;
  final String configured;
  final String observed;

  bool get matches => configured == observed;
}

/// Optional capability implemented by sessions whose protocol exposes a
/// stable network identifier.
abstract interface class ChainNetworkIdentityVerifier {
  Future<ChainNetworkIdentity> verifyNetworkIdentity();
}
