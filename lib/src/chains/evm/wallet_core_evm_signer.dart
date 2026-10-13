import 'dart:convert';
import 'dart:typed_data';

import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'evm_transaction.dart';

/// EVM signer backed by the first-party Wallet Core native bridge.
///
/// Instantiate one process-wide [WalletCoreNativeRuntime], initialize it at
/// application startup, and inject it into every signer.
final class WalletCoreEvmSigner implements EvmTransactionSigner {
  const WalletCoreEvmSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  static const int _ethereumCoinType = 60;

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<EvmSignedTransaction> sign(EvmUnsignedTransaction transaction) async {
    runtime.ensureInitialized();
    return privateKeyAccess.usePrivateKey(
      (privateKey) => _sign(transaction, privateKey),
    );
  }

  EvmSignedTransaction _sign(
    EvmUnsignedTransaction transaction,
    Uint8List privateKey,
  ) {
    if (privateKey.length != 32) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidPrivateKey,
        message: 'EVM private key must contain exactly 32 bytes.',
      );
    }
    try {
      final output = runtime.signJson(
        coinType: _ethereumCoinType,
        json: jsonEncode(_signingInput(transaction)),
        privateKey: privateKey,
      );
      final encoded = ascii.decode(output, allowInvalid: false);
      if (encoded.isEmpty ||
          encoded.length.isOdd ||
          !RegExp(r'^[0-9a-fA-F]+$').hasMatch(encoded)) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core returned an invalid EVM transaction.',
        );
      }
      return EvmSignedTransaction(encoded);
    } on WalletSigningException {
      rethrow;
    } on FormatException {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'EVM transaction contains invalid hexadecimal calldata.',
      );
    }
  }

  static Map<String, Object?> _signingInput(
    EvmUnsignedTransaction transaction,
  ) {
    return <String, Object?>{
      'chainId': _base64Unsigned(transaction.chainId),
      'nonce': _base64Unsigned(transaction.nonce),
      'txMode': transaction.isEip1559 ? 'Enveloped' : 'Legacy',
      if (transaction.gasPrice case final gasPrice?)
        'gasPrice': _base64Unsigned(gasPrice),
      'gasLimit': _base64Unsigned(transaction.gasLimit),
      if (transaction.maxPriorityFeePerGas case final priorityFee?)
        'maxInclusionFeePerGas': _base64Unsigned(priorityFee),
      if (transaction.maxFeePerGas case final maxFee?)
        'maxFeePerGas': _base64Unsigned(maxFee),
      'toAddress': transaction.to,
      'transaction': <String, Object?>{
        'contractGeneric': <String, Object?>{
          'amount': _base64Unsigned(transaction.valueBaseUnits),
          if (_optionalHexBytes(transaction.data) case final data?)
            'data': base64Encode(data),
        },
      },
    };
  }

  static String _base64Unsigned(BigInt value) {
    if (value.isNegative) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'EVM transaction numeric fields must not be negative.',
      );
    }
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return base64Encode(_hexBytes(hex));
  }

  static Uint8List? _optionalHexBytes(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    final normalized = trimmed.startsWith('0x') || trimmed.startsWith('0X')
        ? trimmed.substring(2)
        : trimmed;
    if (normalized.isEmpty) return null;
    return _hexBytes(normalized);
  }

  static Uint8List _hexBytes(String value) {
    if (value.length.isOdd) throw const FormatException();
    final bytes = Uint8List(value.length ~/ 2);
    for (var index = 0; index < value.length; index += 2) {
      final byte = int.tryParse(value.substring(index, index + 2), radix: 16);
      if (byte == null) throw const FormatException();
      bytes[index ~/ 2] = byte;
    }
    return bytes;
  }
}

@Deprecated('Use WalletCoreEvmSigner.')
typedef TrustWalletEvmSigner = WalletCoreEvmSigner;
