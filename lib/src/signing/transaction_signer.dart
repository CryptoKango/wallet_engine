/// Chain-independent boundary between transaction preparation and signing.
///
/// RPC clients and chain sessions depend on this abstraction and never receive
/// private keys. Local keys, hardware wallets, UKey devices, and MPC services
/// can each provide their own implementation.
abstract interface class TransactionSigner<TUnsigned, TSigned> {
  Future<TSigned> sign(TUnsigned transaction);
}
