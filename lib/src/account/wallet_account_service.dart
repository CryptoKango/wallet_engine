import '../config/chain_family.dart';
import 'mnemonic_word_count.dart';
import 'wallet_account.dart';

/// Stateless public API for BIP-39 generation and HD account derivation.
abstract interface class WalletAccountService {
  /// Creates a 12-word wallet and derives [account] for [family].
  Future<CreatedWallet> createWallet12({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  });

  /// Creates a 24-word wallet and derives [account] for [family].
  Future<CreatedWallet> createWallet24({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  });

  /// Creates a wallet using an explicit supported BIP-39 word count.
  Future<CreatedWallet> createWallet({
    required ChainFamily family,
    required MnemonicWordCount wordCount,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  });

  /// Derives one account without retaining or returning the mnemonic.
  Future<WalletAccount> deriveAccount({
    required String mnemonic,
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  });

  /// Imports a raw private key for a chain family with a production adapter.
  Future<WalletAccount> importPrivateKey({
    required String privateKey,
    required ChainFamily family,
    String network = 'mainnet',
    bool exposePrivateKey = false,
  });

  /// Creates an address-only account after chain-aware validation.
  WatchOnlyWallet createWatchOnly({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  });

  /// Validates a 12- or 24-word English BIP-39 mnemonic.
  bool validateMnemonic(String mnemonic);

  /// Validates an address without performing network I/O.
  bool validateAddress({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  });

  /// Validates an accepted private-key export without retaining it.
  bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  });
}
