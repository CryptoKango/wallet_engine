import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart' show QuickCrypto;
import 'package:on_chain/on_chain.dart' show Transaction, TransactionRaw;

import '../../codec/wallet_codec.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'tron_transaction.dart';

/// TRON signer backed by the owned native secp256k1 bridge.
final class WalletCoreTronSigner implements TronTransactionSigner {
  const WalletCoreTronSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<TronSignedTransaction> sign(
    TronUnsignedTransaction transaction,
  ) async {
    runtime.ensureInitialized();
    return privateKeyAccess.usePrivateKey((privateKey) {
      if (privateKey.length != 32) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidPrivateKey,
          message: 'TRON private key must contain exactly 32 bytes.',
        );
      }
      try {
        final raw = TransactionRaw.deserialize(transaction.rawData);
        final digest = Uint8List.fromList(
          QuickCrypto.sha256Hash(raw.toBuffer()),
        );
        final signature = runtime.signSecp256k1(
          privateKey: privateKey,
          digest: digest,
        );
        if (signature.length != 65) throw const FormatException();
        final encoded = Transaction(
          rawData: raw,
          signature: <List<int>>[signature],
        ).toHex;
        return TronSignedTransaction(
          encodedTransaction: WalletCodec.stripHexPrefix(encoded),
          txId: transaction.txId,
        );
      } on WalletSigningException {
        rethrow;
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          WalletSigningException(
            code: WalletSigningErrorCode.invalidTransaction,
            message: 'TRON raw transaction is invalid.',
            cause: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
    });
  }
}

@Deprecated('Use WalletCoreTronSigner.')
typedef TrustWalletTronSigner = WalletCoreTronSigner;
