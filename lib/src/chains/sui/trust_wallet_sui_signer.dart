import 'dart:typed_data';

import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../native_bridge/wallet_core_proto_codec.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'sui_transaction.dart';

/// Sui signer backed by the wallet_engine-owned Wallet Core artifact.
final class WalletCoreSuiSigner implements SuiTransactionSigner {
  const WalletCoreSuiSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  static const int _suiCoinType = 784;

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<SuiSignedTransaction> sign(SuiUnsignedTransaction transaction) async {
    return privateKeyAccess.usePrivateKey((privateKey) {
      if (privateKey.length != 32) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidPrivateKey,
          message: 'Sui private key must contain exactly 32 bytes.',
        );
      }
      final input = _encodeInput(transaction, privateKey);
      try {
        final output = runtime.signProto(coinType: _suiCoinType, input: input);
        return _decodeOutput(output);
      } finally {
        input.fillRange(0, input.length, 0);
      }
    });
  }

  static Uint8List _encodeInput(
    SuiUnsignedTransaction transaction,
    Uint8List privateKey,
  ) {
    final input = WalletCoreProtoWriter()..bytes(1, privateKey);
    switch (transaction) {
      case SuiRawJsonTransaction():
        if (transaction.rawJson.trim().isEmpty) {
          throw const WalletSigningException(
            code: WalletSigningErrorCode.invalidTransaction,
            message: 'Sui raw JSON must not be empty.',
          );
        }
        input.string(10, transaction.rawJson);
      case SuiPaySuiTransaction():
        _validatePayment(
          transaction.inputCoins,
          transaction.recipients,
          transaction.amounts,
          transaction.gasBudget,
          transaction.referenceGasPrice,
        );
        final pay = WalletCoreProtoWriter();
        for (final coin in transaction.inputCoins) {
          pay.message(1, _objectRef(coin));
        }
        for (final recipient in transaction.recipients) {
          pay.string(2, recipient);
        }
        pay.packedUint64(
          3,
          transaction.amounts.map(
            (amount) => _uint64(
              AmountCodec.toBaseUnits(
                amount,
                decimals: transaction.decimals,
                allowZero: false,
              ),
            ),
          ),
        );
        input
          ..message(5, pay)
          ..uint64(12, _uint64(transaction.gasBudget))
          ..uint64(13, _uint64(transaction.referenceGasPrice));
      case SuiPayTransaction():
        _validatePayment(
          transaction.inputCoins,
          transaction.recipients,
          transaction.amounts,
          transaction.gasBudget,
          transaction.referenceGasPrice,
        );
        final pay = WalletCoreProtoWriter();
        for (final coin in transaction.inputCoins) {
          pay.message(1, _objectRef(coin));
        }
        for (final recipient in transaction.recipients) {
          pay.string(2, recipient);
        }
        pay.packedUint64(
          3,
          transaction.amounts.map(
            (amount) => _uint64(
              AmountCodec.toBaseUnits(
                amount,
                decimals: transaction.decimals,
                allowZero: false,
              ),
            ),
          ),
        );
        pay.message(4, _objectRef(transaction.gas));
        input
          ..message(4, pay)
          ..uint64(12, _uint64(transaction.gasBudget))
          ..uint64(13, _uint64(transaction.referenceGasPrice));
    }
    return input.takeBytes();
  }

  static WalletCoreProtoWriter _objectRef(SuiObjectRef ref) {
    if (ref.objectId.trim().isEmpty || ref.digest.trim().isEmpty) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Sui object reference is incomplete.',
      );
    }
    return WalletCoreProtoWriter()
      ..string(1, ref.objectId)
      ..uint64(2, _uint64(ref.version))
      ..string(3, ref.digest);
  }

  static SuiSignedTransaction _decodeOutput(Uint8List output) {
    var unsignedTx = '';
    var signature = '';
    var error = BigInt.zero;
    var errorMessage = '';
    for (final field in WalletCoreProtoReader(output).readFields()) {
      switch (field.number) {
        case 1 when field.wireType == 2:
          unsignedTx = field.string;
        case 2 when field.wireType == 2:
          signature = field.string;
        case 3 when field.wireType == 0:
          error = field.varint;
        case 4 when field.wireType == 2:
          errorMessage = field.string;
      }
    }
    if (error != BigInt.zero || unsignedTx.isEmpty || signature.isEmpty) {
      throw WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: errorMessage.isEmpty
            ? 'Wallet Core could not sign the Sui transaction.'
            : errorMessage,
        context: <String, Object?>{'walletCoreError': error.toString()},
      );
    }
    return SuiSignedTransaction(txBytes: unsignedTx, signature: signature);
  }

  static void _validatePayment(
    List<SuiObjectRef> coins,
    List<String> recipients,
    List<Decimal> amounts,
    BigInt gasBudget,
    BigInt referenceGasPrice,
  ) {
    if (coins.isEmpty ||
        recipients.isEmpty ||
        recipients.length != amounts.length ||
        recipients.any((recipient) => recipient.trim().isEmpty) ||
        amounts.any((amount) => amount <= Decimal.zero) ||
        gasBudget <= BigInt.zero ||
        referenceGasPrice <= BigInt.zero) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Sui payment fields are invalid.',
      );
    }
  }

  static BigInt _uint64(BigInt value) {
    if (value.isNegative || value > (BigInt.one << 64) - BigInt.one) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Sui numeric field is outside the unsigned 64-bit range.',
      );
    }
    return value;
  }
}

@Deprecated('Use WalletCoreSuiSigner.')
typedef TrustWalletSuiSigner = WalletCoreSuiSigner;
