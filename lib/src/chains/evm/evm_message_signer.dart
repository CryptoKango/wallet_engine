import 'dart:typed_data';

import '../../native_bridge/wallet_core_native_bridge.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';

enum EvmMessageType { personal, typedData, immutableX }

/// EVM personal-message, EIP-712 V4, and Immutable X message signer.
final class WalletCoreEvmMessageSigner {
  const WalletCoreEvmMessageSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  Future<String> sign({
    required EvmMessageType type,
    required String message,
  }) async {
    if (message.isEmpty) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'EVM message must not be empty.',
      );
    }
    return privateKeyAccess.usePrivateKey((privateKey) {
      if (privateKey.length != 32) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidPrivateKey,
          message: 'EVM private key must contain exactly 32 bytes.',
        );
      }
      final keyBytes = Uint8List.fromList(privateKey);
      try {
        final signature = runtime.signEvmMessage(
          mode: switch (type) {
            EvmMessageType.personal => WalletCoreEvmMessageMode.personal,
            EvmMessageType.typedData => WalletCoreEvmMessageMode.typedData,
            EvmMessageType.immutableX => WalletCoreEvmMessageMode.immutableX,
          },
          message: message,
          privateKey: keyBytes,
        );
        if (signature.isEmpty) {
          throw const WalletSigningException(
            code: WalletSigningErrorCode.signingFailed,
            message: 'Wallet Core could not sign the EVM message.',
          );
        }
        return signature.startsWith('0x') ? signature.substring(2) : signature;
      } finally {
        keyBytes.fillRange(0, keyBytes.length, 0);
      }
    });
  }
}

@Deprecated('Use WalletCoreEvmMessageSigner.')
typedef TrustWalletEvmMessageSigner = WalletCoreEvmMessageSigner;
