import '../../config/wallet_chain_config.dart';
import '../../error/wallet_error.dart';
import '../../rpc/json_rpc_client.dart';
import '../../rpc/json_rpc_exception.dart';
import '../../rpc/rpc_client.dart';
import 'sui_rpc_exception.dart';
import 'sui_transaction.dart';
import 'sui_transaction_receipt.dart';

/// One raw Sui coin returned by a [SuiGateway].
///
/// Balances stay in integer base units at this protocol boundary. The session
/// converts them to Decimal-based public values using chain metadata.
final class SuiCoinData {
  const SuiCoinData({
    required this.objectId,
    required this.version,
    required this.digest,
    required this.coinType,
    required this.balanceBaseUnits,
  });

  final String objectId;
  final BigInt version;
  final String digest;
  final String coinType;
  final BigInt balanceBaseUnits;
}

/// Cursor page returned by [SuiGateway.getCoins].
final class SuiCoinPage {
  const SuiCoinPage({
    required this.coins,
    required this.hasNextPage,
    required this.nextCursor,
  });

  final List<SuiCoinData> coins;
  final bool hasNextPage;
  final String? nextCursor;
}

/// Protocol-neutral transport boundary for Sui state and execution services.
///
/// Production applications should inject an implementation backed by current
/// Sui gRPC v2 services. Implementations own their channel and must translate
/// provider failures into [WalletError]. A missing transaction must return
/// `null` instead of parsing human-readable error text.
abstract interface class SuiGateway {
  Future<BigInt> getBalanceBaseUnits({
    required String address,
    String? coinType,
  });

  Future<SuiCoinPage> getCoins({
    required String address,
    String? coinType,
    String? cursor,
    required int limit,
  });

  Future<BigInt> getReferenceGasPrice();

  Future<String> getChainIdentifier();

  Future<SuiGasCostSummary> dryRun(String txBytes);

  Future<String> getLatestCheckpointSequenceNumber();

  Future<String> executeTransaction(SuiSignedTransaction transaction);

  Future<SuiTransactionReceipt?> getTransactionReceipt(String digest);

  Future<void> close();
}

typedef SuiGatewayFactory =
    SuiGateway Function(WalletChainConfig config, RpcClient rpc);

/// Compatibility gateway for providers that still expose legacy JSON-RPC.
final class LegacySuiJsonRpcGateway implements SuiGateway {
  LegacySuiJsonRpcGateway(RpcClient rpc)
    : _rpc = JsonRpcClient(rpc: rpc, errorDecoder: SuiRpcException.fromNode);

  final JsonRpcClient _rpc;

  @override
  Future<BigInt> getBalanceBaseUnits({
    required String address,
    String? coinType,
  }) {
    return _rpc.call<BigInt>(
      method: 'suix_getBalance',
      params: <Object?>[address, coinType],
      decode: (result) => _bigInt(_map(result)['totalBalance']),
    );
  }

  @override
  Future<SuiCoinPage> getCoins({
    required String address,
    String? coinType,
    String? cursor,
    required int limit,
  }) {
    return _rpc.call<SuiCoinPage>(
      method: coinType == null ? 'suix_getAllCoins' : 'suix_getCoins',
      params: coinType == null
          ? <Object?>[address, cursor, limit]
          : <Object?>[address, coinType, cursor, limit],
      decode: (result) {
        final map = _map(result);
        final coins = _list(map['data'])
            .map((item) {
              final coin = _map(item);
              return SuiCoinData(
                objectId: _string(coin['coinObjectId']),
                version: _bigInt(coin['version']),
                digest: _string(coin['digest']),
                coinType: _string(coin['coinType']),
                balanceBaseUnits: _bigInt(coin['balance']),
              );
            })
            .toList(growable: false);
        return SuiCoinPage(
          coins: coins,
          hasNextPage: map['hasNextPage'] == true,
          nextCursor: map['nextCursor'] as String?,
        );
      },
    );
  }

  @override
  Future<BigInt> getReferenceGasPrice() {
    return _rpc.call<BigInt>(
      method: 'suix_getReferenceGasPrice',
      decode: _bigInt,
    );
  }

  @override
  Future<String> getChainIdentifier() {
    return _rpc.call<String>(method: 'sui_getChainIdentifier', decode: _string);
  }

  @override
  Future<SuiGasCostSummary> dryRun(String txBytes) {
    return _rpc.call<SuiGasCostSummary>(
      method: 'sui_dryRunTransactionBlock',
      params: <Object?>[txBytes],
      decode: (result) {
        final effects = _map(_map(result)['effects']);
        final gas = _map(effects['gasUsed']);
        return SuiGasCostSummary(
          computationCost: _bigInt(gas['computationCost']),
          storageCost: _bigInt(gas['storageCost']),
          storageRebate: _bigInt(gas['storageRebate']),
        );
      },
    );
  }

  @override
  Future<String> getLatestCheckpointSequenceNumber() {
    return _rpc.call<String>(
      method: 'sui_getLatestCheckpointSequenceNumber',
      decode: _string,
    );
  }

  @override
  Future<String> executeTransaction(SuiSignedTransaction transaction) {
    return _rpc.call<String>(
      method: 'sui_executeTransactionBlock',
      params: <Object?>[
        transaction.txBytes,
        <String>[transaction.signature],
        const <String, Object?>{'showEffects': true},
        'WaitForLocalExecution',
      ],
      decode: (result) => _string(_map(result)['digest']),
    );
  }

  @override
  Future<SuiTransactionReceipt?> getTransactionReceipt(String digest) async {
    try {
      return await _rpc.call<SuiTransactionReceipt>(
        method: 'sui_getTransactionBlock',
        params: <Object?>[
          digest,
          const <String, Object?>{'showEffects': true},
        ],
        decode: (result) {
          final map = _map(result);
          final status = _map(_map(map['effects'])['status']);
          return SuiTransactionReceipt(
            digest: _string(map['digest']),
            status: _string(status['status']),
            error: status['error'] as String?,
            checkpoint: map['checkpoint']?.toString(),
            timestampMs: map['timestampMs']?.toString(),
          );
        },
      );
    } on SuiRpcException catch (error) {
      if (error.transactionNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {}

  static Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    throw const JsonRpcException(
      message: 'Expected a Sui RPC object.',
      retryable: true,
    );
  }

  static List<Object?> _list(Object? value) {
    if (value is List<Object?>) return value;
    throw const JsonRpcException(
      message: 'Expected a Sui RPC list.',
      retryable: true,
    );
  }

  static String _string(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    throw const JsonRpcException(
      message: 'Expected a Sui RPC string.',
      retryable: true,
    );
  }

  static BigInt _bigInt(Object? value) {
    final parsed = BigInt.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    throw const JsonRpcException(
      message: 'Expected a Sui RPC integer.',
      retryable: true,
    );
  }
}
