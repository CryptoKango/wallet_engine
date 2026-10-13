import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart'
    show P2WPKHAddrEncoder, Secp256k1PrivateKey;
import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../codec/wallet_codec.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../native_bridge/wallet_core_proto_codec.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'bitcoin_network.dart';
import 'bitcoin_transaction.dart';

/// Bitcoin signer backed by the wallet_engine-owned Wallet Core artifact.
final class WalletCoreBitcoinSigner implements BitcoinTransactionSigner {
  const WalletCoreBitcoinSigner({
    required this.privateKeyAccess,
    required this.runtime,
    this.changePrivateKeyAccess,
  });

  static const int _bitcoinCoinType = 0;

  final PrivateKeyAccess privateKeyAccess;
  final PrivateKeyAccess? changePrivateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<BitcoinSignedTransaction> sign(
    BitcoinUnsignedTransaction transaction,
  ) async {
    return privateKeyAccess.usePrivateKey((primary) {
      final changeAccess = changePrivateKeyAccess;
      if (changeAccess == null) return _sign(transaction, primary, null);
      return changeAccess.usePrivateKey(
        (change) => _sign(transaction, primary, change),
      );
    });
  }

  Future<String> segwitAddress({String network = 'mainnet'}) async {
    runtime.ensureInitialized();
    final parameters = BitcoinNetwork.parse(network);
    return privateKeyAccess.usePrivateKey((bytes) {
      _validateKey(bytes);
      final publicKey = Secp256k1PrivateKey.fromBytes(
        bytes,
      ).publicKey.compressed;
      return P2WPKHAddrEncoder().encodeKey(publicKey, hrp: parameters.hrp);
    });
  }

  BitcoinSignedTransaction _sign(
    BitcoinUnsignedTransaction transaction,
    Uint8List primary,
    Uint8List? change,
  ) {
    if (transaction.utxos.isEmpty ||
        transaction.amount <= Decimal.zero ||
        transaction.feeRateSatPerVbyte <= Decimal.zero ||
        transaction.toAddress.trim().isEmpty ||
        transaction.changeAddress.trim().isEmpty) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Bitcoin transaction fields are invalid.',
      );
    }
    _validateKey(primary);
    if (change != null) _validateKey(change);

    final input = WalletCoreProtoWriter()
      ..uint32(1, 0x01)
      ..int64(
        2,
        _int64(
          AmountCodec.toBaseUnits(
            transaction.amount,
            decimals: 8,
            allowZero: false,
          ),
        ),
      )
      ..int64(
        3,
        _int64(AmountCodec.ceilToBigInt(transaction.feeRateSatPerVbyte)),
      )
      ..string(4, transaction.toAddress)
      ..string(5, transaction.changeAddress)
      ..bytes(6, primary);
    if (change != null) input.bytes(6, change);
    for (final utxo in transaction.utxos) {
      if (utxo.vout < 0 || utxo.vout > 0xffffffff) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidTransaction,
          message: 'Bitcoin UTXO index is outside the uint32 range.',
        );
      }
      final outPoint = WalletCoreProtoWriter()
        ..bytes(1, WalletCodec.hexToBytes(utxo.txHash).reversed.toList())
        ..uint32(2, utxo.vout);
      final unspent = WalletCoreProtoWriter()
        ..message(1, outPoint)
        ..bytes(2, WalletCodec.hexToBytes(utxo.script))
        ..int64(
          3,
          _int64(
            AmountCodec.toBaseUnits(utxo.amount, decimals: 8, allowZero: false),
          ),
        );
      input.message(8, unspent);
    }

    final encodedInput = input.takeBytes();
    try {
      final output = runtime.signProto(
        coinType: _bitcoinCoinType,
        input: encodedInput,
      );
      return _decodeOutput(output);
    } finally {
      encodedInput.fillRange(0, encodedInput.length, 0);
    }
  }

  static BitcoinSignedTransaction _decodeOutput(Uint8List output) {
    Uint8List? encoded;
    var error = BigInt.zero;
    var errorMessage = '';
    for (final field in WalletCoreProtoReader(output).readFields()) {
      switch (field.number) {
        case 2 when field.wireType == 2:
          encoded = Uint8List.fromList(field.bytes);
        case 4 when field.wireType == 0:
          error = field.varint;
        case 5 when field.wireType == 2:
          errorMessage = field.string;
      }
    }
    if (error != BigInt.zero || encoded == null || encoded.isEmpty) {
      throw WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: errorMessage.isEmpty
            ? 'Wallet Core could not sign the Bitcoin transaction.'
            : errorMessage,
        context: <String, Object?>{'walletCoreError': error.toString()},
      );
    }
    return BitcoinSignedTransaction(hex: WalletCodec.bytesToHex(encoded));
  }

  static void _validateKey(Uint8List bytes) {
    if (bytes.length != 32 || !Secp256k1PrivateKey.isValidBytes(bytes)) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidPrivateKey,
        message: 'Bitcoin private key must be a valid 32-byte secp256k1 key.',
      );
    }
  }

  static BigInt _int64(BigInt value) {
    if (value.isNegative || value > (BigInt.one << 63) - BigInt.one) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Bitcoin numeric field is outside the signed 64-bit range.',
      );
    }
    return value;
  }
}

@Deprecated('Use WalletCoreBitcoinSigner.')
typedef TrustWalletBitcoinSigner = WalletCoreBitcoinSigner;
