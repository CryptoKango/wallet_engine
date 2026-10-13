import 'dart:typed_data';

/// Metadata compiled into a native Wallet Core bridge artifact.
final class WalletCoreNativeBridgeInfo {
  const WalletCoreNativeBridgeInfo({
    required this.abiVersion,
    required this.upstreamVersion,
    required this.upstreamCommit,
  });

  final int abiVersion;
  final String upstreamVersion;
  final String upstreamCommit;
}

/// Narrow boundary between the public Dart API and the owned native artifact.
///
/// Chain-specific operations will be added to this interface only after their
/// deterministic compatibility vectors pass on every maintained platform.
abstract interface class WalletCoreNativeBridge {
  /// Loads the artifact and returns metadata embedded during compilation.
  Future<WalletCoreNativeBridgeInfo> load();

  /// Runs a harmless known-answer test inside the native artifact.
  Future<void> selfTest();

  /// Whether Wallet Core exposes its protobuf-JSON signer for [coinType].
  bool supportsJsonSigning(int coinType);

  /// Signs protobuf JSON synchronously while [privateKey] is in scope.
  ///
  /// The exact result format is chain-specific; for example, EVM returns
  /// hexadecimal text and Solana returns its encoded transaction text.
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  });
}

/// Optional low-level capability used by chains that sign a prepared digest.
abstract interface class WalletCoreSecp256k1Bridge {
  /// Produces a recoverable secp256k1 signature for a 32-byte digest.
  Uint8List signSecp256k1({
    required Uint8List privateKey,
    required Uint8List digest,
  });
}

/// Capability for Wallet Core protobuf binary input/output signing.
abstract interface class WalletCoreProtoBridge {
  Uint8List signProto({required int coinType, required Uint8List input});
}

/// Wallet Core Ethereum message signing mode.
enum WalletCoreEvmMessageMode { personal, typedData, immutableX }

/// Capability for EVM personal-message and EIP-712 signing.
abstract interface class WalletCoreEvmMessageBridge {
  String signEvmMessage({
    required WalletCoreEvmMessageMode mode,
    required String message,
    required Uint8List privateKey,
  });
}

enum WalletCorePublicKeyMode { coinDefault, secp256k1Compressed, ed25519 }

/// Derived material returned to the account service for immediate conversion.
/// [privateKey] must be erased by the caller as soon as possible.
final class WalletCoreKeyInfo {
  const WalletCoreKeyInfo({
    required this.privateKey,
    required this.publicKey,
    required this.address,
  });

  final Uint8List privateKey;
  final Uint8List publicKey;
  final String address;
}

abstract interface class WalletCoreKeyDerivationBridge {
  WalletCoreKeyInfo deriveKey({
    required int coinType,
    required String mnemonic,
    required String passphrase,
    required String derivationPath,
    required WalletCorePublicKeyMode publicKeyMode,
  });

  WalletCoreKeyInfo inspectKey({
    required int coinType,
    required Uint8List privateKey,
    required WalletCorePublicKeyMode publicKeyMode,
  });
}
