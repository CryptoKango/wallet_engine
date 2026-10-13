import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:on_chain/on_chain.dart' show TransactionRaw;

import '../../amount/amount_codec.dart';
import '../../chain/chain_session.dart';
import '../../codec/wallet_codec.dart';
import '../../config/wallet_chain_config.dart';
import '../../error/wallet_error.dart';
import '../../rpc/rpc_client.dart';
import '../../rpc/rpc_request.dart';
import '../../rpc/rpc_response.dart';
import '../../transaction/transaction_confirmation.dart';
import 'tron_models.dart';
import 'tron_transaction.dart';

final class TronChainSession implements ChainSession {
  factory TronChainSession({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    return TronChainSession._(config, rpc);
  }

  const TronChainSession._(this.config, this._rpc);

  @override
  final WalletChainConfig config;
  final RpcClient _rpc;

  Future<Decimal> getBalance(String address) async {
    final result = await _post('wallet/getaccount', <String, Object?>{
      'address': address,
      'visible': true,
    });
    return AmountCodec.fromBaseUnits(
      _bigInt(result['balance'], fallback: BigInt.zero),
      decimals: config.nativeDecimals,
    );
  }

  Future<TronBlockHeader> getBlockHeader() async {
    final result = await _post('wallet/getnowblock', const <String, Object?>{});
    final header = _map(result['block_header']);
    final raw = _map(header['raw_data']);
    return TronBlockHeader(
      timestamp: _bigInt(raw['timestamp']),
      txTrieRoot: raw['txTrieRoot']?.toString() ?? '',
      parentHash: raw['parentHash']?.toString() ?? '',
      number: _bigInt(raw['number']),
      witnessAddress: raw['witness_address']?.toString() ?? '',
      version: _int(raw['version']),
    );
  }

  Future<TronUnsignedTransaction> buildTransfer({
    required String from,
    required String to,
    required Decimal amount,
  }) async {
    final baseUnits = AmountCodec.toBaseUnits(
      amount,
      decimals: config.nativeDecimals,
      allowZero: false,
    );
    final result = await _post('wallet/createtransaction', <String, Object?>{
      'owner_address': from,
      'to_address': to,
      'amount': baseUnits.toString(),
      'visible': true,
    });
    return _transactionFromResponse(result);
  }

  /// Builds a generic smart-contract transaction from ABI calldata.
  /// Project contract wrappers remain responsible for encoding [data].
  Future<TronTransactionBuildResult> buildContractCall({
    required String from,
    required String contract,
    required String data,
    Decimal? callValue,
    Decimal? feeLimit,
  }) async {
    final callValueBaseUnits = AmountCodec.toBaseUnits(
      callValue ?? Decimal.zero,
      decimals: config.nativeDecimals,
    );
    final feeLimitBaseUnits = feeLimit == null
        ? null
        : AmountCodec.toBaseUnits(feeLimit, decimals: config.nativeDecimals);
    final result = await _post(
      'wallet/triggersmartcontract',
      <String, Object?>{
        'owner_address': from,
        'contract_address': contract,
        'data': WalletCodec.stripHexPrefix(data),
        'call_value': callValueBaseUnits.toString(),
        'fee_limit': feeLimitBaseUnits?.toString(),
        'visible': true,
      }..removeWhere((_, value) => value == null),
    );
    _ensureTriggerSuccess(result);
    final transactionMap = _map(result['transaction']);
    var transaction = _transactionFromResponse(transactionMap);
    if (feeLimitBaseUnits != null) {
      final raw = TransactionRaw.deserialize(
        transaction.rawData,
      ).copyWith(feeLimit: feeLimitBaseUnits);
      transaction = _wrapRaw(raw);
    }
    return TronTransactionBuildResult(
      transaction: transaction,
      energyUsed: _bigIntOrNull(result['energy_used']),
    );
  }

  /// Executes a read-only contract call and returns raw result words as hex.
  Future<List<String>> callContract({
    required String owner,
    required String contract,
    required String data,
    Decimal? callValue,
  }) async {
    final result =
        await _post('wallet/triggerconstantcontract', <String, Object?>{
          'owner_address': owner,
          'contract_address': contract,
          'data': WalletCodec.stripHexPrefix(data),
          'call_value': AmountCodec.toBaseUnits(
            callValue ?? Decimal.zero,
            decimals: config.nativeDecimals,
          ).toString(),
          'visible': true,
        });
    _ensureTriggerSuccess(result);
    final values = result['constant_result'];
    if (values is! List<Object?>) return const <String>[];
    return values.map((value) => value.toString()).toList(growable: false);
  }

  Future<TronFeeSchedule> getFeeSchedule() async {
    final result = await _post(
      'wallet/getchainparameters',
      const <String, Object?>{},
    );
    final parameters = result['chainParameter'];
    if (parameters is! List<Object?>) {
      throw const TronRpcException('Invalid chain parameter response.');
    }
    final values = <String, BigInt>{};
    for (final item in parameters) {
      final parameter = _map(item);
      final key = parameter['key']?.toString();
      if (key != null) values[key] = _bigInt(parameter['value']);
    }
    return TronFeeSchedule(
      transactionFee: AmountCodec.fromBaseUnits(
        values['getTransactionFee'] ?? BigInt.from(1000),
        decimals: config.nativeDecimals,
      ),
      energyFee: AmountCodec.fromBaseUnits(
        values['getEnergyFee'] ?? BigInt.from(100),
        decimals: config.nativeDecimals,
      ),
      createAccountFee: AmountCodec.fromBaseUnits(
        values['getCreateAccountFee'] ?? BigInt.from(100000),
        decimals: config.nativeDecimals,
      ),
    );
  }

  Future<String> broadcast(TronSignedTransaction transaction) async {
    final result = await _post('wallet/broadcasthex', <String, Object?>{
      'transaction': transaction.encodedTransaction,
    });
    final accepted = result['result'];
    final txId = result['txid']?.toString();
    if (accepted == true || (accepted == null && txId?.isNotEmpty == true)) {
      return txId?.isNotEmpty == true ? txId! : transaction.txId;
    }
    throw TronRpcException(
      'TRON broadcast rejected: ${result['code'] ?? 'unknown'}.',
    );
  }

  Future<TronTransactionReceipt?> getTransactionReceipt(String txId) async {
    final result = await _post(
      'wallet/gettransactioninfobyid',
      <String, Object?>{'value': txId},
    );
    final blockNumber = _bigIntOrNull(result['blockNumber']);
    if (blockNumber == null) return null;
    final receipt = result['receipt'] is Map<Object?, Object?>
        ? _map(result['receipt'])
        : const <Object?, Object?>{};
    final receiptResult = receipt['result']?.toString();
    final transactionResult = result['result']?.toString();
    final success =
        (receiptResult == null || receiptResult == 'SUCCESS') &&
        (transactionResult == null || transactionResult == 'SUCCESS');
    return TronTransactionReceipt(
      txHash: txId,
      success: success,
      blockNumber: blockNumber,
      fee: AmountCodec.fromBaseUnits(
        _bigInt(
          result['fee'],
          fallback:
              _bigInt(receipt['energy_fee'], fallback: BigInt.zero) +
              _bigInt(receipt['net_fee'], fallback: BigInt.zero),
        ),
        decimals: config.nativeDecimals,
      ),
      energyUsage: _bigInt(
        receipt['energy_usage_total'] ?? receipt['energy_usage'],
        fallback: BigInt.zero,
      ),
      netUsage: _bigInt(receipt['net_usage'], fallback: BigInt.zero),
      result: receiptResult ?? transactionResult,
      error: result['resMessage']?.toString(),
    );
  }

  Future<TronTransactionReceipt> waitForTransactionReceipt(
    String txId, {
    TransactionConfirmationPolicy policy =
        const TransactionConfirmationPolicy(),
    WalletCancellationToken? cancellationToken,
  }) {
    return TransactionConfirmationWaiter.wait<TronTransactionReceipt>(
      lookup: () => getTransactionReceipt(txId),
      isConfirmed: (_) => true,
      transactionId: txId,
      chainKey: config.key,
      policy: policy,
      cancellationToken: cancellationToken,
    );
  }

  Future<String> signAndBroadcast(
    TronUnsignedTransaction transaction, {
    required TronTransactionSigner signer,
  }) async {
    return broadcast(await signer.sign(transaction));
  }

  @override
  Future<void> close() async {}

  Future<Map<Object?, Object?>> _post(String path, Map<String, Object?> body) {
    return _rpc.execute<Map<Object?, Object?>>(
      RpcRequest(
        operation: path,
        path: path,
        body: body,
        headers: const <String, String>{'Content-Type': 'application/json'},
      ),
      decode: _decodeObjectResponse,
    );
  }

  static Map<Object?, Object?> _decodeObjectResponse(RpcResponse response) {
    if (response.data is Map<Object?, Object?>) {
      return response.data! as Map<Object?, Object?>;
    }
    throw const TronRpcException('TRON endpoint returned a non-object body.');
  }

  static TronUnsignedTransaction _transactionFromResponse(
    Map<Object?, Object?> response,
  ) {
    final rawHex = response['raw_data_hex']?.toString();
    if (rawHex == null || rawHex.isEmpty) {
      throw const TronRpcException('TRON response has no raw_data_hex.');
    }
    return _wrapRaw(TransactionRaw.deserialize(WalletCodec.hexToBytes(rawHex)));
  }

  static TronUnsignedTransaction _wrapRaw(TransactionRaw raw) {
    return TronUnsignedTransaction(
      rawData: Uint8List.fromList(raw.toBuffer()),
      txId: raw.txID,
    );
  }

  static void _ensureTriggerSuccess(Map<Object?, Object?> response) {
    final result = response['result'];
    if (result is Map<Object?, Object?> && result['result'] == false) {
      throw TronRpcException(
        'TRON contract trigger rejected: ${result['message'] ?? 'unknown'}.',
      );
    }
  }

  static Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    throw const TronRpcException('Expected a TRON RPC object.');
  }

  static BigInt _bigInt(Object? value, {BigInt? fallback}) {
    final parsed = _bigIntOrNull(value);
    if (parsed != null) return parsed;
    if (fallback != null) return fallback;
    throw const TronRpcException('Expected a TRON RPC integer.');
  }

  static BigInt? _bigIntOrNull(Object? value) {
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    return BigInt.tryParse(value?.toString() ?? '');
  }

  static int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
}

final class TronRpcException implements WalletError {
  const TronRpcException(
    this.message, {
    this.retryable = false,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  @override
  final String message;

  @override
  final bool retryable;

  @override
  WalletErrorCategory get category => WalletErrorCategory.chain;

  @override
  WalletErrorCode get publicCode => WalletErrorCode.chainTronRpc;

  @override
  String get errorCode => publicCode.value;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'TronRpcException: $message';
}
