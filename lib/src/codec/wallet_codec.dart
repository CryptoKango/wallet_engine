import 'dart:typed_data';

import '../signing/wallet_signing_exception.dart';

final class WalletCodec {
  WalletCodec._();

  static Uint8List hexToBytes(String value) {
    final normalized = stripHexPrefix(value.trim());
    if (normalized.isEmpty || normalized.length.isOdd) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Expected non-empty, even-length hexadecimal data.',
      );
    }
    final bytes = Uint8List(normalized.length ~/ 2);
    for (var index = 0; index < normalized.length; index += 2) {
      final byte = int.tryParse(
        normalized.substring(index, index + 2),
        radix: 16,
      );
      if (byte == null) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidTransaction,
          message: 'Expected hexadecimal data.',
        );
      }
      bytes[index ~/ 2] = byte;
    }
    return bytes;
  }

  static String bytesToHex(Iterable<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List unsignedBigIntBytes(BigInt value) {
    if (value.isNegative) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Numeric transaction fields must not be negative.',
      );
    }
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return hexToBytes(hex);
  }

  static String stripHexPrefix(String value) {
    return value.startsWith('0x') || value.startsWith('0X')
        ? value.substring(2)
        : value;
  }
}
