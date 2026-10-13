import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../chain/chain_network_identity.dart';
import '../../chain/chain_session.dart';
import '../../config/wallet_chain_config.dart';
import '../../core/wallet_engine_exception.dart';
import '../../error/wallet_error.dart';
import '../../rpc/json_rpc_client.dart';
import '../../rpc/json_rpc_exception.dart';
import '../../transaction/transaction_confirmation.dart';
import 'evm_call.dart';
import 'evm_fee_quote.dart';
import 'evm_transaction.dart';
import 'evm_transaction_receipt.dart';

/// Generic EVM RPC capabilities. Project contracts build calldata elsewhere
/// and use [call], [estimateGas], and [broadcast] through this session.
final class EvmChainSession
    implements ChainSession, ChainNetworkIdentityVerifier {
  factory EvmChainSession({
    required WalletChainConfig config,
    required JsonRpcClient rpc,
  }) {
    return EvmChainSession._(config, rpc);
  }

  const EvmChainSession._(this.config, this._rpc);

  @override
  final WalletChainConfig config;

  final JsonRpcClient _rpc;

  Future<BigInt> getChainId() {
    return _quantityCall('eth_chainId');
  }

  @override
  Future<ChainNetworkIdentity> verifyNetworkIdentity() async {
    final configuredValue = config.chainId;
    if (configuredValue == null) {
      throw const WalletValidationException(
        field: 'chainId',
        message: 'EVM network verification requires a configured chain ID.',
      );
    }
    final configured = _parseConfiguredChainId(configuredValue);
    final observed = await getChainId();
    if (configured != observed) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.networkMismatch,
        message: 'Configured EVM chain ID does not match the RPC node.',
        context: <String, Object?>{
          'chainKey': config.key,
          'configuredChainId': configured.toString(),
          'observedChainId': observed.toString(),
        },
      );
    }
    return ChainNetworkIdentity(
      family: config.family,
      configured: configured.toString(),
      observed: observed.toString(),
    );
  }

  Future<Decimal> getBalance(String address, {String block = 'latest'}) async {
    final baseUnits = await _quantityCall('eth_getBalance', <Object?>[
      address,
      block,
    ]);
    return AmountCodec.fromBaseUnits(
      baseUnits,
      decimals: config.nativeDecimals,
    );
  }

  Future<BigInt> getTransactionCount(
    String address, {
    String block = 'pending',
  }) {
    return _quantityCall('eth_getTransactionCount', <Object?>[address, block]);
  }

  Future<BigInt> getGasPrice() {
    return _quantityCall('eth_gasPrice');
  }

  Future<BigInt> getBlockNumber() {
    return _quantityCall('eth_blockNumber');
  }

  Future<BigInt> getMaxPriorityFeePerGas() {
    return _quantityCall('eth_maxPriorityFeePerGas');
  }

  Future<BigInt> estimateGas(EvmCall call) {
    return _quantityCall('eth_estimateGas', <Object?>[call.toJson()]);
  }

  Future<String> call(EvmCall call, {String block = 'latest'}) {
    return _rpc.call<String>(
      method: 'eth_call',
      params: <Object?>[call.toJson(), block],
      decode: _decodeString,
    );
  }

  Future<String> broadcast(String signedTransaction) {
    return _rpc.call<String>(
      method: 'eth_sendRawTransaction',
      params: <Object?>[signedTransaction],
      decode: _decodeString,
    );
  }

  /// Resolves chain ID, nonce, gas, and fee fields without touching key
  /// material. Project contract wrappers are responsible for calldata.
  Future<EvmUnsignedTransaction> prepareTransaction(
    EvmTransactionRequest request, {
    EvmFeePolicy feePolicy = const EvmFeePolicy(),
  }) async {
    final call = EvmCall(
      from: request.from,
      to: request.to,
      valueBaseUnits: AmountCodec.toBaseUnits(
        request.value,
        decimals: config.nativeDecimals,
      ),
      data: request.data,
    );
    final chainId = config.chainId == null
        ? await getChainId()
        : _parseConfiguredChainId(config.chainId!);
    final nonce = request.nonce ?? await getTransactionCount(request.from);
    var feeQuote =
        request.feeQuote ?? await estimateFee(call, policy: feePolicy);
    if (request.gasLimit != null) {
      feeQuote = feeQuote.withGasLimit(request.gasLimit!);
    }
    if (feeQuote.isEip1559) {
      return EvmUnsignedTransaction.eip1559(
        chainId: chainId,
        nonce: nonce,
        gasLimit: feeQuote.gasLimit,
        to: request.to,
        valueBaseUnits: call.valueBaseUnits,
        data: request.data,
        maxPriorityFeePerGas: feeQuote.maxPriorityFeePerGas!,
        maxFeePerGas: feeQuote.maxFeePerGas!,
      );
    }
    return EvmUnsignedTransaction.legacy(
      chainId: chainId,
      nonce: nonce,
      gasLimit: feeQuote.gasLimit,
      to: request.to,
      valueBaseUnits: call.valueBaseUnits,
      data: request.data,
      gasPrice: feeQuote.gasPrice!,
    );
  }

  /// Signs through an injected signer and broadcasts only the resulting bytes.
  Future<EvmBroadcastResult> signAndBroadcast(
    EvmUnsignedTransaction transaction, {
    required EvmTransactionSigner signer,
  }) async {
    final signed = await signer.sign(transaction);
    final transactionHash = await broadcast(signed.rawTransaction);
    return EvmBroadcastResult(
      transactionHash: transactionHash,
      signedTransaction: signed,
    );
  }

  Future<EvmTransactionReceipt?> getTransactionReceipt(String txHash) {
    return _rpc.call<EvmTransactionReceipt?>(
      method: 'eth_getTransactionReceipt',
      params: <Object?>[txHash],
      decode: _decodeReceipt,
    );
  }

  Future<EvmTransactionReceipt> waitForTransactionReceipt(
    String txHash, {
    int confirmations = 1,
    TransactionConfirmationPolicy policy =
        const TransactionConfirmationPolicy(),
    WalletCancellationToken? cancellationToken,
  }) async {
    if (confirmations <= 0) {
      throw const WalletValidationException(
        field: 'confirmations',
        message: 'EVM confirmation count must be positive.',
      );
    }
    final snapshot =
        await TransactionConfirmationWaiter.wait<_EvmConfirmationSnapshot>(
          lookup: () async {
            final receipt = await getTransactionReceipt(txHash);
            final blockNumber = receipt?.blockNumber;
            if (receipt == null || blockNumber == null) return null;
            final latest = confirmations == 1
                ? blockNumber
                : await getBlockNumber();
            final count = latest >= blockNumber
                ? (latest - blockNumber + BigInt.one).toInt()
                : 0;
            return _EvmConfirmationSnapshot(receipt, count);
          },
          isConfirmed: (value) => value.confirmations >= confirmations,
          transactionId: txHash,
          chainKey: config.key,
          policy: policy,
          cancellationToken: cancellationToken,
        );
    return snapshot.receipt;
  }

  Future<EvmFeeQuote> estimateFee(
    EvmCall call, {
    EvmFeePolicy policy = const EvmFeePolicy(),
  }) async {
    final gasLimit = await estimateGas(call);
    if (policy.preferEip1559) {
      final baseFee = await _latestBaseFee();
      if (baseFee != null) {
        try {
          final priorityFee = await getMaxPriorityFeePerGas();
          final adjustedBaseFee =
              (baseFee * BigInt.from(policy.baseFeeMultiplierNumerator)) ~/
              BigInt.from(policy.baseFeeMultiplierDenominator);
          return EvmFeeQuote.eip1559(
            gasLimit: gasLimit,
            maxPriorityFeePerGas: priorityFee,
            maxFeePerGas: adjustedBaseFee + priorityFee,
          );
        } on JsonRpcException {
          // Older EVM nodes may not implement eth_maxPriorityFeePerGas.
        }
      }
    }
    return EvmFeeQuote.legacy(
      gasLimit: gasLimit,
      gasPrice: await getGasPrice(),
    );
  }

  @override
  Future<void> close() async {}

  Future<BigInt> _quantityCall(
    String method, [
    List<Object?> params = const <Object?>[],
  ]) {
    return _rpc.call<BigInt>(
      method: method,
      params: params,
      decode: _decodeQuantity,
    );
  }

  Future<BigInt?> _latestBaseFee() {
    return _rpc.call<BigInt?>(
      method: 'eth_getBlockByNumber',
      params: const <Object?>['latest', false],
      decode: (result) {
        if (result is! Map<Object?, Object?>) {
          throw const JsonRpcException(
            message: 'Latest EVM block is not an object.',
            retryable: true,
          );
        }
        final value = result['baseFeePerGas'];
        if (value == null) return null;
        return _decodeQuantity(value);
      },
    );
  }

  static String _decodeString(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const JsonRpcException(
        message: 'Expected a non-empty string result.',
        retryable: true,
      );
    }
    return value;
  }

  static BigInt _decodeQuantity(Object? value) {
    if (value is! String || !value.startsWith('0x') || value.length < 3) {
      throw const JsonRpcException(
        message: 'Expected an EVM hex quantity.',
        retryable: true,
      );
    }
    try {
      return BigInt.parse(value.substring(2), radix: 16);
    } on FormatException {
      throw const JsonRpcException(
        message: 'Expected an EVM hex quantity.',
        retryable: true,
      );
    }
  }

  static BigInt _parseConfiguredChainId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const JsonRpcException(
        message: 'Configured EVM chain ID is empty.',
        retryable: false,
      );
    }
    try {
      final parsed = normalized.startsWith('0x') || normalized.startsWith('0X')
          ? BigInt.parse(normalized.substring(2), radix: 16)
          : BigInt.parse(normalized);
      if (parsed.isNegative) throw const FormatException();
      return parsed;
    } on FormatException {
      throw const JsonRpcException(
        message: 'Configured EVM chain ID is invalid.',
        retryable: false,
      );
    }
  }

  static EvmTransactionReceipt? _decodeReceipt(Object? value) {
    if (value == null) return null;
    if (value is! Map<Object?, Object?>) {
      throw const JsonRpcException(
        message: 'Expected an EVM transaction receipt object.',
        retryable: true,
      );
    }
    final hash = value['transactionHash'];
    if (hash is! String || hash.isEmpty) {
      throw const JsonRpcException(
        message: 'EVM receipt has no transaction hash.',
        retryable: true,
      );
    }
    final statusValue = value['status'];
    final status = statusValue == null
        ? null
        : _decodeQuantity(statusValue) == BigInt.one;
    final blockValue = value['blockNumber'];
    final gasUsedValue = value['gasUsed'];
    return EvmTransactionReceipt(
      transactionHash: hash,
      blockNumber: blockValue == null ? null : _decodeQuantity(blockValue),
      success: status,
      gasUsed: gasUsedValue == null ? null : _decodeQuantity(gasUsedValue),
    );
  }
}

final class _EvmConfirmationSnapshot {
  const _EvmConfirmationSnapshot(this.receipt, this.confirmations);

  final EvmTransactionReceipt receipt;
  final int confirmations;
}
