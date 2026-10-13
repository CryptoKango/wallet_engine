import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:on_chain/on_chain.dart' show SuiHelper;

import '../../amount/amount_codec.dart';
import '../../chain/chain_network_identity.dart';
import '../../chain/chain_session.dart';
import '../../config/wallet_chain_config.dart';
import '../../core/wallet_engine_exception.dart';
import '../../error/wallet_error.dart';
import '../../transaction/transaction_confirmation.dart';
import 'sui_gateway.dart';
import 'sui_transaction.dart';
import 'sui_transaction_receipt.dart';

/// Conservative fallback used when Sui dry-run is temporarily unavailable.
final BigInt suiDefaultTransferGasBudget = BigInt.from(50000000);

final class SuiChainSession
    implements ChainSession, ChainNetworkIdentityVerifier {
  factory SuiChainSession.withGateway({
    required WalletChainConfig config,
    required SuiGateway gateway,
  }) {
    return SuiChainSession._(config, gateway);
  }

  const SuiChainSession._(this.config, this._gateway);

  @override
  final WalletChainConfig config;
  final SuiGateway _gateway;

  Future<Decimal> getBalance(
    String address, {
    String? coinType,
    int? decimals,
  }) async {
    final balance = await _gateway.getBalanceBaseUnits(
      address: address,
      coinType: coinType,
    );
    return AmountCodec.fromBaseUnits(
      balance,
      decimals: decimals ?? config.nativeDecimals,
    );
  }

  Future<List<SuiCoinRef>> getAllCoins(
    String address, {
    String? coinType,
    int limit = 50,
    int? decimals,
  }) async {
    final coins = <SuiCoinRef>[];
    String? cursor;
    do {
      final page = await _gateway.getCoins(
        address: address,
        coinType: coinType,
        cursor: cursor,
        limit: limit,
      );
      coins.addAll(
        page.coins.map(
          (coin) => SuiCoinRef(
            objectId: coin.objectId,
            version: coin.version,
            digest: coin.digest,
            coinType: coin.coinType,
            balance: AmountCodec.fromBaseUnits(
              coin.balanceBaseUnits,
              decimals: decimals ?? config.nativeDecimals,
            ),
          ),
        ),
      );
      cursor = page.hasNextPage ? page.nextCursor : null;
    } while (cursor != null);
    return coins;
  }

  Future<BigInt> getReferenceGasPrice() => _gateway.getReferenceGasPrice();

  Future<String> getChainIdentifier() => _gateway.getChainIdentifier();

  @override
  Future<ChainNetworkIdentity> verifyNetworkIdentity() async {
    final configured = config.chainId;
    if (configured == null) {
      throw const WalletValidationException(
        field: 'chainId',
        message: 'Sui network verification requires a chain identifier.',
      );
    }
    final observed = await getChainIdentifier();
    if (configured != observed) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.networkMismatch,
        message: 'Configured Sui chain identifier does not match the RPC node.',
        context: <String, Object?>{
          'chainKey': config.key,
          'configuredChainId': configured,
          'observedChainId': observed,
        },
      );
    }
    return ChainNetworkIdentity(
      family: config.family,
      configured: configured,
      observed: observed,
    );
  }

  Future<SuiGasCostSummary> dryRun(String txBytes) => _gateway.dryRun(txBytes);

  Future<BigInt> estimateGasBudget(
    String txBytes, {
    int bufferNumerator = 12,
    int bufferDenominator = 10,
  }) async {
    final summary = await dryRun(txBytes);
    return (summary.netCost * BigInt.from(bufferNumerator) +
            BigInt.from(bufferDenominator - 1)) ~/
        BigInt.from(bufferDenominator);
  }

  /// Estimates a budget and falls back to a host-overridable safe ceiling.
  Future<BigInt> estimateGasBudgetOrDefault(
    String txBytes, {
    BigInt? fallback,
    bool fallbackOnDeterministicError = false,
    int bufferNumerator = 12,
    int bufferDenominator = 10,
  }) async {
    try {
      return await estimateGasBudget(
        txBytes,
        bufferNumerator: bufferNumerator,
        bufferDenominator: bufferDenominator,
      );
    } on WalletError catch (error) {
      if (!fallbackOnDeterministicError && !error.retryable) rethrow;
      return fallback ?? suiDefaultTransferGasBudget;
    }
  }

  Future<String> getLatestCheckpointSequenceNumber() =>
      _gateway.getLatestCheckpointSequenceNumber();

  Future<String> broadcast(SuiSignedTransaction transaction) =>
      _gateway.executeTransaction(transaction);

  Future<SuiTransactionReceipt?> getTransactionReceipt(String digest) =>
      _gateway.getTransactionReceipt(digest);

  Future<SuiTransactionReceipt> waitForTransactionReceipt(
    String digest, {
    TransactionConfirmationPolicy policy =
        const TransactionConfirmationPolicy(),
    WalletCancellationToken? cancellationToken,
  }) {
    return TransactionConfirmationWaiter.wait<SuiTransactionReceipt>(
      lookup: () => getTransactionReceipt(digest),
      isConfirmed: (_) => true,
      transactionId: digest,
      chainKey: config.key,
      policy: policy,
      cancellationToken: cancellationToken,
    );
  }

  /// Computes the canonical Sui transaction digest from BCS transaction data.
  static String digestFromTxBytes(String txBytes) {
    try {
      return SuiHelper.generateTransactionDigest(base64.decode(txBytes));
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletValidationException(
          field: 'txBytes',
          message: 'Sui transaction bytes are not valid base64 BCS data.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  Future<String> signAndBroadcast(
    SuiUnsignedTransaction transaction, {
    required SuiTransactionSigner signer,
  }) async {
    return broadcast(await signer.sign(transaction));
  }

  @override
  Future<void> close() => _gateway.close();
}
