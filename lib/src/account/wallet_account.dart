import '../config/chain_family.dart';
import 'mnemonic_word_count.dart';

enum WalletAccountSource { hd, privateKey }

/// Derived key material for one chain account.
///
/// This value is intentionally not serializable by wallet_engine. The host
/// application owns encrypted persistence and access control for key material.
final class WalletAccount {
  const WalletAccount({
    required this.family,
    required this.network,
    required this.account,
    required this.derivationPath,
    required this.address,
    required this.publicKey,
    this.privateKey,
    this.source = WalletAccountSource.hd,
    this.changeAddress,
    this.changePublicKey,
    this.changePrivateKey,
  });

  final ChainFamily family;
  final String network;
  final int account;
  final String derivationPath;
  final String address;
  final String publicKey;

  /// Chain-specific private-key export.
  ///
  /// EVM and most chains use lowercase hex. Solana uses a base58-encoded
  /// 64-byte keypair for compatibility with common Solana tooling.
  /// Optional high-risk export, produced only when the caller explicitly sets
  /// `exposePrivateKey: true` on an account operation.
  final String? privateKey;
  final WalletAccountSource source;

  /// BIP-84 internal/change account material. Present only for Bitcoin.
  final String? changeAddress;
  final String? changePublicKey;
  final String? changePrivateKey;

  @override
  String toString() {
    return 'WalletAccount(family: ${family.name}, network: $network, '
        'source: ${source.name}, '
        'account: $account, address: $address, '
        'derivationPath: $derivationPath, publicKey: <redacted>, '
        'privateKey: <redacted>, changePrivateKey: <redacted>)';
  }
}

/// Result returned only when a new BIP-39 wallet is created.
///
/// [mnemonic] is returned once and is never cached or persisted by
/// wallet_engine. The host must transfer it immediately to protected storage.
final class CreatedWallet {
  const CreatedWallet({
    required this.mnemonic,
    required this.wordCount,
    required this.wallet,
  });

  final String mnemonic;
  final MnemonicWordCount wordCount;
  final WalletAccount wallet;

  @override
  String toString() {
    return 'CreatedWallet(wordCount: ${wordCount.value}, mnemonic: <redacted>, '
        'wallet: $wallet)';
  }
}

/// A validated address-only account that never contains signing material.
final class WatchOnlyWallet {
  const WatchOnlyWallet({
    required this.family,
    required this.network,
    required this.address,
  });

  final ChainFamily family;
  final String network;
  final String address;

  @override
  String toString() {
    return 'WatchOnlyWallet(family: ${family.name}, network: $network, '
        'address: $address)';
  }
}
