import 'dart:typed_data';

import 'wallet_core_native_bridge.dart';

/// Unsupported-platform placeholder for the native FFI implementation.
final class FfiWalletCoreNativeBridge implements WalletCoreNativeBridge {
  FfiWalletCoreNativeBridge.open({String? libraryPath});

  @override
  Future<WalletCoreNativeBridgeInfo> load() {
    throw UnsupportedError(
      'The Wallet Core native bridge is unavailable on this platform.',
    );
  }

  @override
  Future<void> selfTest() => Future<void>.error(
    UnsupportedError(
      'The Wallet Core native bridge is unavailable on this platform.',
    ),
  );

  @override
  bool supportsJsonSigning(int coinType) => false;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    throw UnsupportedError(
      'The Wallet Core native bridge is unavailable on this platform.',
    );
  }
}
