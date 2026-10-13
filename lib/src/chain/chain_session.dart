import '../config/wallet_chain_config.dart';

/// Runtime context for a configured chain.
///
/// Concrete sessions own transient RPC health state. They must not persist
/// credentials, private keys, signed transactions, or configuration snapshots.
abstract interface class ChainSession {
  WalletChainConfig get config;

  Future<void> close();
}
