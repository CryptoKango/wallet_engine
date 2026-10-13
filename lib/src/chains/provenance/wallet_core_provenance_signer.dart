import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'provenance_transaction.dart';

/// Provenance/Cosmos Amino signer backed by the owned native bridge.
final class WalletCoreProvenanceSigner implements ProvenanceTransactionSigner {
  const WalletCoreProvenanceSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  static const int _cosmosCoinType = 118;

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<ProvenanceSignedTransaction> sign(
    ProvenanceTransferTransaction transaction,
  ) async {
    runtime.ensureInitialized();
    _validate(transaction);
    return privateKeyAccess.usePrivateKey((privateKey) {
      if (privateKey.length != 32) {
        throw const WalletSigningException(
          code: WalletSigningErrorCode.invalidPrivateKey,
          message: 'Provenance private key must contain exactly 32 bytes.',
        );
      }
      final output = runtime.signJson(
        coinType: _cosmosCoinType,
        json: jsonEncode(_signingInput(transaction)),
        privateKey: privateKey,
      );
      return ProvenanceSignedTransaction(
        base64Signature: _extractSignature(output),
      );
    });
  }

  static Map<String, Object?> _signingInput(
    ProvenanceTransferTransaction transaction,
  ) {
    return <String, Object?>{
      'signingMode': 'JSON',
      'accountNumber': transaction.accountNumber.toString(),
      'chainId': transaction.chainId,
      'fee': <String, Object?>{
        'amounts': <Object?>[
          <String, Object?>{
            'denom': transaction.feeDenom,
            'amount': AmountCodec.toBaseUnits(
              transaction.feeAmount,
              decimals: transaction.feeDecimals,
            ).toString(),
          },
        ],
        'gas': transaction.gas.toString(),
      },
      'memo': transaction.memo,
      'sequence': transaction.sequence.toString(),
      'messages': <Object?>[
        <String, Object?>{
          'sendCoinsMessage': <String, Object?>{
            'fromAddress': transaction.fromAddress,
            'toAddress': transaction.toAddress,
            'amounts': <Object?>[
              <String, Object?>{
                'denom': transaction.denom,
                'amount': AmountCodec.toBaseUnits(
                  transaction.amount,
                  decimals: transaction.decimals,
                  allowZero: false,
                ).toString(),
              },
            ],
          },
        },
      ],
    };
  }

  static String _extractSignature(Uint8List output) {
    try {
      final decoded = jsonDecode(utf8.decode(output));
      final root = decoded as Map<String, Object?>;
      final tx = root['tx']! as Map<String, Object?>;
      final signatures = tx['signatures']! as List<Object?>;
      final signature =
          (signatures.single! as Map<String, Object?>)['signature']! as String;
      if (base64Decode(signature).length != 64) throw const FormatException();
      return signature;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core returned an invalid Provenance signature.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  static void _validate(ProvenanceTransferTransaction transaction) {
    if (transaction.chainId.isEmpty ||
        transaction.fromAddress.isEmpty ||
        transaction.toAddress.isEmpty ||
        transaction.denom.isEmpty ||
        transaction.feeDenom.isEmpty ||
        transaction.amount <= Decimal.zero ||
        transaction.feeAmount < Decimal.zero ||
        transaction.gas <= BigInt.zero ||
        transaction.accountNumber.isNegative ||
        transaction.sequence.isNegative ||
        transaction.accountNumber > BigInt.parse('18446744073709551615') ||
        transaction.sequence > BigInt.parse('18446744073709551615') ||
        transaction.gas > BigInt.parse('18446744073709551615')) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Provenance transfer fields are invalid.',
      );
    }
  }
}

@Deprecated('Use WalletCoreProvenanceSigner.')
typedef TrustWalletProvenanceSigner = WalletCoreProvenanceSigner;
