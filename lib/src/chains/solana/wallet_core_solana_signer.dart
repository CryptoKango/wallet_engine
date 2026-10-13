import 'dart:convert';
import 'dart:typed_data';

import 'package:on_chain/on_chain.dart'
    show AssociatedTokenAccountProgramUtils, SolAddress;

import '../../amount/amount_codec.dart';
import '../../native_bridge/wallet_core_native_runtime.dart';
import '../../signing/private_key_access.dart';
import '../../signing/wallet_signing_exception.dart';
import 'solana_token_account.dart';
import 'solana_transaction.dart';

/// Solana signer backed by the owned Wallet Core native bridge.
final class WalletCoreSolanaSigner implements SolanaTransactionSigner {
  const WalletCoreSolanaSigner({
    required this.privateKeyAccess,
    required this.runtime,
  });

  static const int _solanaCoinType = 501;
  static final BigInt _uint64Max = BigInt.parse('18446744073709551615');

  final PrivateKeyAccess privateKeyAccess;
  final WalletCoreNativeRuntime runtime;

  @override
  Future<SolanaSignedTransaction> sign(
    SolanaUnsignedTransaction transaction,
  ) async {
    runtime.ensureInitialized();
    return privateKeyAccess.usePrivateKey((privateKey) {
      final seed = _seed(privateKey);
      try {
        final output = runtime.signJson(
          coinType: _solanaCoinType,
          json: jsonEncode(_signingInput(transaction)),
          privateKey: seed,
        );
        final encoded = utf8.decode(output);
        if (encoded.isEmpty || base64Decode(encoded).isEmpty) {
          throw const FormatException();
        }
        return SolanaSignedTransaction(base64Transaction: encoded);
      } on WalletSigningException {
        rethrow;
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          WalletSigningException(
            code: WalletSigningErrorCode.invalidTransaction,
            message: 'Solana transaction fields or signing output are invalid.',
            cause: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      } finally {
        seed.fillRange(0, seed.length, 0);
      }
    });
  }

  static Map<String, Object?> _signingInput(
    SolanaUnsignedTransaction transaction,
  ) {
    final input = <String, Object?>{
      'recentBlockhash': transaction.recentBlockhash,
      'txEncoding': 'Base64',
      if (transaction.priorityFeeLimit case final limit?)
        'priorityFeeLimit': <String, Object?>{'limit': _uint32(limit)},
      if (transaction.priorityFeePrice case final price?)
        'priorityFeePrice': <String, Object?>{
          'price': _uint64(price).toString(),
        },
    };
    switch (transaction) {
      case SolanaTransferTransaction():
        input['transferTransaction'] = <String, Object?>{
          'recipient': transaction.recipient,
          'value': _uint64(
            AmountCodec.toBaseUnits(
              transaction.amount,
              decimals: 9,
              allowZero: false,
            ),
          ).toString(),
        };
      case SolanaTokenTransferTransaction():
        _setTokenTransfer(input, transaction);
    }
    return input;
  }

  static void _setTokenTransfer(
    Map<String, Object?> input,
    SolanaTokenTransferTransaction transaction,
  ) {
    final program = transaction.token2022 ? 'Token2022Program' : 'TokenProgram';
    final amount = _uint64(
      AmountCodec.toBaseUnits(
        transaction.amount,
        decimals: transaction.decimals,
        allowZero: false,
      ),
    ).toString();
    final recipientToken = transaction.recipientTokenAddress;
    if (recipientToken != null && recipientToken.isNotEmpty) {
      input['tokenTransferTransaction'] = <String, Object?>{
        'tokenMintAddress': transaction.tokenMintAddress,
        'senderTokenAddress': transaction.senderTokenAddress,
        'recipientTokenAddress': recipientToken,
        'amount': amount,
        'decimals': transaction.decimals,
        'tokenProgramId': program,
      };
      return;
    }
    final tokenProgram = transaction.token2022
        ? SolanaTokenProgram.token2022
        : SolanaTokenProgram.token;
    final recipientAta =
        AssociatedTokenAccountProgramUtils.associatedTokenAccount(
          owner: SolAddress(transaction.recipientMainAddress),
          mint: SolAddress(transaction.tokenMintAddress),
          tokenProgramId: SolAddress(tokenProgram.programId),
        ).address.address;
    input['createAndTransferTokenTransaction'] = <String, Object?>{
      'recipientMainAddress': transaction.recipientMainAddress,
      'tokenMintAddress': transaction.tokenMintAddress,
      'recipientTokenAddress': recipientAta,
      'senderTokenAddress': transaction.senderTokenAddress,
      'amount': amount,
      'decimals': transaction.decimals,
      'tokenProgramId': program,
    };
  }

  static Uint8List _seed(Uint8List bytes) {
    if (bytes.length != 32 && bytes.length != 64) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidPrivateKey,
        message: 'Solana private key must contain 32 or 64 bytes.',
      );
    }
    return Uint8List.fromList(bytes.sublist(0, 32));
  }

  static BigInt _uint64(BigInt value) {
    if (value <= BigInt.zero || value > _uint64Max) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Solana amount is outside the unsigned 64-bit range.',
      );
    }
    return value;
  }

  static int _uint32(int value) {
    if (value <= 0 || value > 0xffffffff) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.invalidTransaction,
        message: 'Solana priority fee limit is outside the uint32 range.',
      );
    }
    return value;
  }
}

@Deprecated('Use WalletCoreSolanaSigner.')
typedef TrustWalletSolanaSigner = WalletCoreSolanaSigner;
