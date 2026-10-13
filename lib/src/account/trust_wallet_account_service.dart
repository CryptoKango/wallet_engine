import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:blockchain_utils/blockchain_utils.dart'
    show
        Base58Decoder,
        Base58Encoder,
        Bech32Encoder,
        P2WPKHAddrEncoder,
        QuickCrypto,
        Substrate,
        SubstrateCoins;
import '../chains/bitcoin/bitcoin_network.dart';
import '../config/chain_family.dart';
import '../error/wallet_error.dart';
import '../native_bridge/wallet_core_native_bridge.dart';
import '../native_bridge/wallet_core_native_runtime.dart';
import 'mnemonic_word_count.dart';
import 'wallet_account.dart';
import 'wallet_account_exception.dart';
import 'wallet_account_service.dart';
import 'wallet_address_validator.dart';

/// Account service backed by the wallet_engine-owned Wallet Core artifact.
final class WalletCoreAccountService implements WalletAccountService {
  const WalletCoreAccountService({required this.runtime});

  final WalletCoreNativeRuntime runtime;

  @override
  Future<CreatedWallet> createWallet12({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    return createWallet(
      family: family,
      wordCount: MnemonicWordCount.words12,
      network: network,
      account: account,
      passphrase: passphrase,
      exposePrivateKey: exposePrivateKey,
    );
  }

  @override
  Future<CreatedWallet> createWallet24({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    return createWallet(
      family: family,
      wordCount: MnemonicWordCount.words24,
      network: network,
      account: account,
      passphrase: passphrase,
      exposePrivateKey: exposePrivateKey,
    );
  }

  @override
  Future<CreatedWallet> createWallet({
    required ChainFamily family,
    required MnemonicWordCount wordCount,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) async {
    _validateAccount(account);
    runtime.ensureInitialized();
    try {
      final mnemonic = bip39.generateMnemonic(strength: wordCount.strengthBits);
      final wallet = await deriveAccount(
        mnemonic: mnemonic,
        family: family,
        network: network,
        account: account,
        passphrase: passphrase,
        exposePrivateKey: exposePrivateKey,
      );
      return CreatedWallet(
        mnemonic: mnemonic,
        wordCount: wordCount,
        wallet: wallet,
      );
    } on WalletAccountException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletAccountException(
          code: WalletAccountErrorCode.generationFailed,
          message: 'BIP-39 wallet generation failed.',
          cause: error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'family': family.name,
            'wordCount': wordCount.value,
          },
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<WalletAccount> deriveAccount({
    required String mnemonic,
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) async {
    _validateAccount(account);
    final normalized = _normalizeMnemonic(mnemonic);
    runtime.ensureInitialized();
    final normalizedNetwork = network.trim().toLowerCase();
    if (normalizedNetwork.isEmpty) {
      throw const WalletValidationException(
        message: 'Network must not be empty.',
        field: 'network',
      );
    }

    try {
      if (family == ChainFamily.polkadot) {
        return _derivePolkadot(
          mnemonic: normalized,
          passphrase: passphrase,
          network: normalizedNetwork,
          account: account,
          exposePrivateKey: exposePrivateKey,
        );
      }
      return _deriveWallet(
        mnemonic: normalized,
        passphrase: passphrase,
        family: family,
        network: normalizedNetwork,
        account: account,
        exposePrivateKey: exposePrivateKey,
      );
    } on WalletAccountException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletAccountException(
          code: WalletAccountErrorCode.derivationFailed,
          message: 'HD wallet account derivation failed.',
          cause: error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'family': family.name,
            'network': normalizedNetwork,
            'account': account,
          },
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<WalletAccount> importPrivateKey({
    required String privateKey,
    required ChainFamily family,
    String network = 'mainnet',
    bool exposePrivateKey = false,
  }) async {
    if (!WalletAddressValidator.supports(family)) {
      throw WalletAccountException(
        code: WalletAccountErrorCode.unsupportedChain,
        message: 'Private-key import is unavailable for this chain family.',
        context: <String, Object?>{'family': family.name},
      );
    }
    if (!validatePrivateKey(privateKey: privateKey, family: family)) {
      throw const WalletAccountException(
        code: WalletAccountErrorCode.invalidPrivateKey,
        message: 'Private key has an invalid format for this chain family.',
      );
    }
    final normalizedNetwork = network.trim().toLowerCase();
    if (normalizedNetwork.isEmpty) {
      throw const WalletValidationException(
        message: 'Network must not be empty.',
        field: 'network',
      );
    }
    runtime.ensureInitialized();

    try {
      final suppliedBytes = family == ChainFamily.solana
          ? Base58Decoder.decode(privateKey.trim())
          : _decodeHex(privateKey);
      try {
        final keyBytes = Uint8List.fromList(
          suppliedBytes.length == 64
              ? suppliedBytes.sublist(0, 32)
              : suppliedBytes,
        );
        try {
          final key = runtime.inspectKey(
            coinType: _coinType(family),
            privateKey: keyBytes,
            publicKeyMode: _publicKeyMode(family),
          );
          return _importedAccount(
            key: key,
            suppliedBytes: suppliedBytes,
            family: family,
            network: normalizedNetwork,
            exposePrivateKey: exposePrivateKey,
          );
        } finally {
          keyBytes.fillRange(0, keyBytes.length, 0);
        }
      } finally {
        suppliedBytes.fillRange(0, suppliedBytes.length, 0);
      }
    } on WalletAccountException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletAccountException(
          code: WalletAccountErrorCode.derivationFailed,
          message: 'Private-key account import failed.',
          cause: error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'family': family.name,
            'network': normalizedNetwork,
          },
        ),
        stackTrace,
      );
    }
  }

  @override
  WatchOnlyWallet createWatchOnly({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    if (!WalletAddressValidator.supports(family)) {
      throw WalletAccountException(
        code: WalletAccountErrorCode.unsupportedChain,
        message: 'Watch-only accounts are unavailable for this chain family.',
        context: <String, Object?>{'family': family.name},
      );
    }
    final normalizedNetwork = network.trim().toLowerCase();
    if (normalizedNetwork.isEmpty) {
      throw const WalletValidationException(
        message: 'Network must not be empty.',
        field: 'network',
      );
    }
    if (!validateAddress(
      address: address,
      family: family,
      network: normalizedNetwork,
    )) {
      throw const WalletAccountException(
        code: WalletAccountErrorCode.invalidAddress,
        message: 'Address has an invalid format for this chain and network.',
      );
    }
    return WatchOnlyWallet(
      family: family,
      network: normalizedNetwork,
      address: address.trim(),
    );
  }

  @override
  bool validateMnemonic(String mnemonic) {
    final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return false;
    final words = normalized.split(' ').length;
    return (words == 12 || words == 24) && bip39.validateMnemonic(normalized);
  }

  @override
  bool validateAddress({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    return WalletAddressValidator.validateAddress(
      address: address,
      family: family,
      network: network,
    );
  }

  @override
  bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  }) {
    return WalletAddressValidator.validatePrivateKey(
      privateKey: privateKey,
      family: family,
    );
  }

  WalletAccount _importedAccount({
    required WalletCoreKeyInfo key,
    required List<int> suppliedBytes,
    required ChainFamily family,
    required String network,
    required bool exposePrivateKey,
  }) {
    try {
      if (family == ChainFamily.solana) {
        if (suppliedBytes.length == 64 &&
            !_bytesEqual(suppliedBytes.sublist(32), key.publicKey)) {
          throw const WalletAccountException(
            code: WalletAccountErrorCode.invalidPrivateKey,
            message: 'Solana keypair public key does not match its seed.',
          );
        }
        final pair = Uint8List(64)
          ..setRange(0, 32, key.privateKey)
          ..setRange(32, 64, key.publicKey);
        try {
          return WalletAccount(
            family: family,
            network: network,
            account: 0,
            derivationPath: '',
            address: key.address,
            publicKey: Base58Encoder.encode(key.publicKey),
            privateKey: exposePrivateKey ? Base58Encoder.encode(pair) : null,
            source: WalletAccountSource.privateKey,
          );
        } finally {
          pair.fillRange(0, pair.length, 0);
        }
      }
      final address = family == ChainFamily.bitcoin
          ? P2WPKHAddrEncoder().encodeKey(
              key.publicKey,
              hrp: _bitcoinHrp(network),
            )
          : key.address;
      return WalletAccount(
        family: family,
        network: network,
        account: 0,
        derivationPath: '',
        address: address,
        publicKey: _hex(key.publicKey),
        privateKey: exposePrivateKey ? _hex(key.privateKey) : null,
        source: WalletAccountSource.privateKey,
      );
    } finally {
      key.privateKey.fillRange(0, key.privateKey.length, 0);
    }
  }

  WalletAccount _deriveWallet({
    required String mnemonic,
    required String passphrase,
    required ChainFamily family,
    required String network,
    required int account,
    required bool exposePrivateKey,
  }) {
    if (family == ChainFamily.provenance) {
      final path = "m/44'/505'/0'/0/$account";
      final key = runtime.deriveKey(
        coinType: _coinType(ChainFamily.cosmos),
        mnemonic: mnemonic,
        passphrase: passphrase,
        derivationPath: path,
        publicKeyMode: WalletCorePublicKeyMode.secp256k1Compressed,
      );
      try {
        return WalletAccount(
          family: family,
          network: network,
          account: account,
          derivationPath: path,
          address: Bech32Encoder.encode(
            'pb',
            QuickCrypto.hash160(key.publicKey),
          ),
          publicKey: _hex(key.publicKey),
          privateKey: exposePrivateKey ? _hex(key.privateKey) : null,
        );
      } finally {
        key.privateKey.fillRange(0, key.privateKey.length, 0);
      }
    }

    final path = _derivationPath(family, account, network);
    final key = runtime.deriveKey(
      coinType: _coinType(family),
      mnemonic: mnemonic,
      passphrase: passphrase,
      derivationPath: path,
      publicKeyMode: _publicKeyMode(family),
    );
    try {
      if (family == ChainFamily.bitcoin) {
        return _bitcoinAccount(
          mnemonic: mnemonic,
          passphrase: passphrase,
          key: key,
          network: network,
          account: account,
          path: path,
          exposePrivateKey: exposePrivateKey,
        );
      }
      if (family == ChainFamily.solana) {
        final pair = Uint8List(64)
          ..setRange(0, 32, key.privateKey)
          ..setRange(32, 64, key.publicKey);
        try {
          return WalletAccount(
            family: family,
            network: network,
            account: account,
            derivationPath: path,
            address: key.address,
            publicKey: Base58Encoder.encode(key.publicKey),
            privateKey: exposePrivateKey ? Base58Encoder.encode(pair) : null,
          );
        } finally {
          pair.fillRange(0, pair.length, 0);
        }
      }
      return WalletAccount(
        family: family,
        network: network,
        account: account,
        derivationPath: path,
        address: key.address,
        publicKey: _hex(key.publicKey),
        privateKey: exposePrivateKey ? _hex(key.privateKey) : null,
      );
    } finally {
      key.privateKey.fillRange(0, key.privateKey.length, 0);
    }
  }

  WalletAccount _bitcoinAccount({
    required String mnemonic,
    required String passphrase,
    required WalletCoreKeyInfo key,
    required String network,
    required int account,
    required String path,
    required bool exposePrivateKey,
  }) {
    final bitcoinNetwork = BitcoinNetwork.parse(network);
    final changePath = bitcoinNetwork.changePath(account);
    final changeKey = runtime.deriveKey(
      coinType: _coinType(ChainFamily.bitcoin),
      mnemonic: mnemonic,
      passphrase: passphrase,
      derivationPath: changePath,
      publicKeyMode: WalletCorePublicKeyMode.secp256k1Compressed,
    );
    try {
      final hrp = bitcoinNetwork.hrp;
      final encoder = P2WPKHAddrEncoder();
      return WalletAccount(
        family: ChainFamily.bitcoin,
        network: network,
        account: account,
        derivationPath: path,
        address: encoder.encodeKey(key.publicKey, hrp: hrp),
        publicKey: _hex(key.publicKey),
        privateKey: exposePrivateKey ? _hex(key.privateKey) : null,
        changeAddress: encoder.encodeKey(changeKey.publicKey, hrp: hrp),
        changePublicKey: _hex(changeKey.publicKey),
        changePrivateKey: exposePrivateKey ? _hex(changeKey.privateKey) : null,
      );
    } finally {
      changeKey.privateKey.fillRange(0, changeKey.privateKey.length, 0);
    }
  }

  WalletAccount _derivePolkadot({
    required String mnemonic,
    required String passphrase,
    required String network,
    required int account,
    required bool exposePrivateKey,
  }) {
    final seed = bip39.mnemonicToSeed(mnemonic, passphrase: passphrase);
    final path = '//44//354//0//0//$account';
    try {
      final substrate = Substrate.fromSeedAndPath(
        seed,
        path,
        SubstrateCoins.polkadotSr25519,
      );
      return WalletAccount(
        family: ChainFamily.polkadot,
        network: network,
        account: account,
        derivationPath: path,
        address: substrate.publicKey.toSS58Address(),
        publicKey: _hex(substrate.publicKey.compressed),
        privateKey: exposePrivateKey ? _hex(substrate.priveKey.raw) : null,
      );
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  static int _coinType(ChainFamily family) => switch (family) {
    ChainFamily.bitcoin => 0,
    ChainFamily.evm => 60,
    ChainFamily.solana => 501,
    ChainFamily.tron => 195,
    ChainFamily.sui => 784,
    ChainFamily.aptos => 637,
    ChainFamily.ton => 607,
    ChainFamily.xrp => 144,
    ChainFamily.cardano => 1815,
    ChainFamily.cosmos => 118,
    ChainFamily.near => 397,
    ChainFamily.polkadot ||
    ChainFamily.provenance => throw WalletAccountException(
      code: WalletAccountErrorCode.unsupportedChain,
      message: 'The requested chain family is not supported.',
      context: <String, Object?>{'family': family.name},
    ),
  };

  static WalletCorePublicKeyMode _publicKeyMode(ChainFamily family) {
    return switch (family) {
      ChainFamily.bitcoin ||
      ChainFamily.evm ||
      ChainFamily.tron ||
      ChainFamily.xrp ||
      ChainFamily.cosmos ||
      ChainFamily.provenance => WalletCorePublicKeyMode.secp256k1Compressed,
      ChainFamily.solana ||
      ChainFamily.sui ||
      ChainFamily.aptos ||
      ChainFamily.ton ||
      ChainFamily.cardano ||
      ChainFamily.near => WalletCorePublicKeyMode.ed25519,
      ChainFamily.polkadot => throw WalletAccountException(
        code: WalletAccountErrorCode.unsupportedChain,
        message: 'Native key inspection is unavailable for Polkadot.',
      ),
    };
  }

  static String _derivationPath(
    ChainFamily family,
    int account,
    String network,
  ) {
    return switch (family) {
      ChainFamily.bitcoin => BitcoinNetwork.parse(network).receivePath(account),
      ChainFamily.evm => "m/44'/60'/0'/0/$account",
      ChainFamily.solana => "m/44'/501'/$account'/0'",
      ChainFamily.tron => "m/44'/195'/0'/0/$account",
      ChainFamily.sui => "m/44'/784'/0'/0'/$account'",
      ChainFamily.aptos => "m/44'/637'/0'/0'/$account'",
      ChainFamily.ton => "m/44'/607'/0'/0'/$account'",
      ChainFamily.xrp => "m/44'/144'/0'/0/$account",
      ChainFamily.cardano => "m/1852'/1815'/0'/0/$account",
      ChainFamily.cosmos => "m/44'/118'/0'/0/$account",
      ChainFamily.near => "m/44'/397'/0'/0'/$account'",
      ChainFamily.polkadot ||
      ChainFamily.provenance => throw WalletAccountException(
        code: WalletAccountErrorCode.unsupportedChain,
        message: 'The requested chain family is not supported.',
        context: <String, Object?>{'family': family.name},
      ),
    };
  }

  static String _bitcoinHrp(String network) =>
      BitcoinNetwork.parse(network).hrp;

  static void _validateAccount(int account) {
    if (account < 0 || account > 0x7fffffff) {
      throw const WalletValidationException(
        message: 'Account must be between 0 and 2147483647.',
        field: 'account',
      );
    }
  }

  String _normalizeMnemonic(String mnemonic) {
    final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!validateMnemonic(normalized)) {
      throw const WalletAccountException(
        code: WalletAccountErrorCode.invalidMnemonic,
        message: 'Mnemonic must be a valid 12- or 24-word BIP-39 phrase.',
      );
    }
    return normalized;
  }

  static String _hex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List _decodeHex(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.startsWith('0x') || trimmed.startsWith('0X')
        ? trimmed.substring(2)
        : trimmed;
    return Uint8List.fromList(<int>[
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ]);
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

@Deprecated('Use WalletCoreAccountService.')
typedef TrustWalletAccountService = WalletCoreAccountService;
