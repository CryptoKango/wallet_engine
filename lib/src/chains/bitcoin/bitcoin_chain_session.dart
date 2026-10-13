import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart'
    show QuickCrypto, SegwitBech32Decoder;
import 'package:decimal/decimal.dart';

import '../../amount/amount_codec.dart';
import '../../chain/chain_network_identity.dart';
import '../../chain/chain_session.dart';
import '../../codec/wallet_codec.dart';
import '../../config/wallet_chain_config.dart';
import '../../core/wallet_engine_exception.dart';
import '../../error/wallet_error.dart';
import '../../rpc/rpc_client.dart';
import '../../rpc/rpc_transport_exception.dart';
import '../../transaction/transaction_confirmation.dart';
import 'bitcoin_network.dart';
import 'bitcoin_transaction.dart';
import 'bitcoin_transaction_receipt.dart';
import 'electrum_transport.dart';

final class BitcoinChainSession
    implements ChainSession, ChainNetworkIdentityVerifier {
  factory BitcoinChainSession({
    required WalletChainConfig config,
    required RpcClient rpc,
    required ElectrumTransport transport,
  }) {
    return BitcoinChainSession._(config, rpc, transport);
  }

  const BitcoinChainSession._(this.config, this._rpc, this._transport);

  @override
  final WalletChainConfig config;
  final RpcClient _rpc;
  final ElectrumTransport _transport;

  Future<List<BitcoinUtxo>> listUnspent(String address) async {
    final script = scriptFromSegwitAddress(address);
    final result = await _request(
      'blockchain.scripthash.listunspent',
      <Object?>[scripthashFromAddress(address)],
    );
    if (result is! List<Object?>) {
      throw const ElectrumException('Invalid listunspent response.');
    }
    return result
        .map((item) {
          final map = _map(item);
          return BitcoinUtxo(
            txHash: _string(map['tx_hash']),
            vout: _int(map['tx_pos']),
            amount: AmountCodec.fromBaseUnits(
              _bigInt(map['value']),
              decimals: config.nativeDecimals,
            ),
            script: script,
          );
        })
        .toList(growable: false);
  }

  Future<Decimal> getBalance(String address) async {
    final result = _map(
      await _request('blockchain.scripthash.get_balance', <Object?>[
        scripthashFromAddress(address),
      ]),
    );
    return AmountCodec.fromBaseUnits(
      _bigInt(result['confirmed']) + _bigInt(result['unconfirmed']),
      decimals: config.nativeDecimals,
    );
  }

  Future<Decimal> estimateFeeRate({int blocks = 6}) async {
    Object? result;
    try {
      result = await _request('blockchain.estimatefee', <Object?>[blocks]);
    } on ElectrumException {
      result = null;
    }
    final btcPerKb = _decimalOrNull(result);
    if (btcPerKb != null && btcPerKb > Decimal.zero) {
      final value = btcPerKb * Decimal.fromInt(100000);
      return value < Decimal.one ? Decimal.one : value;
    }
    try {
      final relay = await _request('blockchain.relayfee', const <Object?>[]);
      final relayFee = _decimalOrNull(relay);
      if (relayFee != null && relayFee > Decimal.zero) {
        final value = relayFee * Decimal.fromInt(100000);
        return value < Decimal.one ? Decimal.one : value;
      }
    } on ElectrumException {
      // Static fallback below.
    }
    return Decimal.fromInt(2);
  }

  Future<String> getGenesisHash() async {
    final features = _map(await _request('server.features', const <Object?>[]));
    return _string(features['genesis_hash']);
  }

  @override
  Future<ChainNetworkIdentity> verifyNetworkIdentity() async {
    final configured = config.chainId?.toLowerCase();
    if (configured == null) {
      throw const WalletValidationException(
        field: 'chainId',
        message: 'Bitcoin network verification requires a genesis hash.',
      );
    }
    final observed = (await getGenesisHash()).toLowerCase();
    if (configured != observed) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.networkMismatch,
        message: 'Configured Bitcoin genesis hash does not match the server.',
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

  Future<String> broadcast(BitcoinSignedTransaction transaction) async {
    final result = await _request('blockchain.transaction.broadcast', <Object?>[
      transaction.hex,
    ]);
    return _string(result);
  }

  Future<BitcoinTransactionReceipt?> getTransactionReceipt(
    String txHash, {
    int maxDepth = 12,
  }) async {
    try {
      await _request('blockchain.transaction.get', <Object?>[txHash]);
    } on ElectrumException catch (error) {
      if (error.transactionNotFound || _isNotFound(error.message)) return null;
      rethrow;
    }
    final header = _map(
      await _request('blockchain.headers.subscribe', const <Object?>[]),
    );
    final tip = _int(header['height']);
    for (var height = tip; height >= 0 && height > tip - maxDepth; height--) {
      try {
        final merkle = _map(
          await _request('blockchain.transaction.get_merkle', <Object?>[
            txHash,
            height,
          ]),
        );
        if (merkle['block_height'] != null) {
          return BitcoinTransactionReceipt(
            txHash: txHash,
            confirmations: tip - height + 1,
            blockHeight: height,
          );
        }
      } on ElectrumException {
        // Continue scanning recent blocks.
      }
    }
    return BitcoinTransactionReceipt(txHash: txHash, confirmations: 0);
  }

  Future<BitcoinTransactionReceipt> waitForTransactionReceipt(
    String txHash, {
    int confirmations = 1,
    int maxSearchDepth = 144,
    TransactionConfirmationPolicy policy = const TransactionConfirmationPolicy(
      timeout: Duration(minutes: 30),
    ),
    WalletCancellationToken? cancellationToken,
  }) {
    if (confirmations <= 0) {
      throw const WalletValidationException(
        field: 'confirmations',
        message: 'Bitcoin confirmation count must be positive.',
      );
    }
    if (maxSearchDepth < confirmations) {
      throw const WalletValidationException(
        field: 'maxSearchDepth',
        message: 'Bitcoin search depth must cover the confirmation target.',
      );
    }
    return TransactionConfirmationWaiter.wait<BitcoinTransactionReceipt>(
      lookup: () => getTransactionReceipt(txHash, maxDepth: maxSearchDepth),
      isConfirmed: (receipt) => receipt.confirmations >= confirmations,
      transactionId: txHash,
      chainKey: config.key,
      policy: policy,
      cancellationToken: cancellationToken,
    );
  }

  Future<String> signAndBroadcast(
    BitcoinUnsignedTransaction transaction, {
    required BitcoinTransactionSigner signer,
  }) async {
    return broadcast(await signer.sign(transaction));
  }

  String scriptFromSegwitAddress(String address) {
    try {
      final hrp = BitcoinNetwork.parse(config.network).hrp;
      final (witnessVersion, witnessProgram) = SegwitBech32Decoder.decode(
        hrp,
        address,
      );
      if (witnessVersion != 0 || witnessProgram.length != 20) {
        throw const ElectrumException(
          'Only P2WPKH segwit addresses are supported.',
        );
      }
      return '0014${WalletCodec.bytesToHex(witnessProgram)}';
    } on ElectrumException {
      rethrow;
    } catch (_) {
      throw const ElectrumException('Invalid Bitcoin segwit address.');
    }
  }

  String scripthashFromAddress(String address) {
    final script = WalletCodec.hexToBytes(scriptFromSegwitAddress(address));
    final digest = QuickCrypto.sha256Hash(script);
    return WalletCodec.bytesToHex(Uint8List.fromList(digest.reversed.toList()));
  }

  Future<Object?> _request(String method, List<Object?> params) {
    return _rpc.executeOnEndpoint<Object?>(
      operation: method,
      attempt: (endpoint) => _transport.request(
        endpoint: endpoint,
        method: method,
        params: params,
        timeout: const Duration(seconds: 20),
      ),
      shouldRetry: (error) => error is RpcTransportException && error.retryable,
      requestBody: <String, Object?>{'method': method, 'params': params},
    );
  }

  @override
  Future<void> close() => _transport.close();

  static Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    throw const ElectrumException('Expected an Electrum object.');
  }

  static String _string(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    throw const ElectrumException('Expected an Electrum string.');
  }

  static int _int(Object? value) {
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    throw const ElectrumException('Expected an Electrum integer.');
  }

  static BigInt _bigInt(Object? value) {
    final parsed = BigInt.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    throw const ElectrumException('Expected an Electrum integer.');
  }

  static Decimal? _decimalOrNull(Object? value) {
    return Decimal.tryParse(value?.toString() ?? '');
  }

  static bool _isNotFound(String value) {
    final message = value.toLowerCase();
    return message.contains('missing transaction') ||
        message.contains('no such transaction') ||
        message.contains('transaction not found');
  }
}
