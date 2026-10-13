import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/rpc_endpoint.dart';
import '../../error/wallet_error.dart';
import '../../rpc/rpc_transport_exception.dart';

abstract interface class ElectrumTransport {
  Future<Object?> request({
    required RpcEndpoint endpoint,
    required String method,
    required List<Object?> params,
    required Duration timeout,
  });

  Future<void> close();
}

/// One-request-per-connection Electrum transport.
///
/// It favors isolation and deterministic cleanup. Endpoint pooling and
/// failover are still handled by [RpcClient] above this layer.
final class SocketElectrumTransport implements ElectrumTransport {
  const SocketElectrumTransport();

  @override
  Future<Object?> request({
    required RpcEndpoint endpoint,
    required String method,
    required List<Object?> params,
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      final uri = endpoint.uri;
      final secure = switch (uri.scheme.toLowerCase()) {
        'ssl' || 'tls' || 'electrums' => true,
        'tcp' || 'electrum' => false,
        _ => throw const WalletValidationException(
          field: 'uri',
          message:
              'Electrum endpoint must use tls, ssl, electrums, tcp, or electrum.',
        ),
      };
      final port = uri.hasPort ? uri.port : (secure ? 50002 : 50001);
      socket = secure
          ? await SecureSocket.connect(uri.host, port, timeout: timeout)
          : await Socket.connect(uri.host, port, timeout: timeout);
      final iterator = StreamIterator<String>(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      socket.write(
        '${jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'server.version',
          'params': <Object?>[
            'wallet_engine',
            <String>['1.4', '1.4.2'],
          ],
        })}\n',
      );
      socket.write(
        '${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': method, 'params': params})}\n',
      );
      await socket.flush();

      while (await iterator.moveNext().timeout(timeout)) {
        final decoded = jsonDecode(iterator.current);
        if (decoded is! Map<Object?, Object?> || decoded['id'] != 2) continue;
        final error = decoded['error'];
        if (error != null) {
          throw ElectrumException.fromServer(_safeError(error));
        }
        return decoded['result'];
      }
      throw const RpcTransportException(
        failure: RpcTransportFailure.invalidResponse,
        message: 'Electrum endpoint closed without a response.',
        retryable: true,
      );
    } on ElectrumException {
      rethrow;
    } on RpcTransportException {
      rethrow;
    } on TimeoutException {
      throw const RpcTransportException(
        failure: RpcTransportFailure.timeout,
        message: 'Electrum request timed out.',
        retryable: true,
      );
    } on SocketException {
      throw const RpcTransportException(
        failure: RpcTransportFailure.connection,
        message: 'Electrum connection failed.',
        retryable: true,
      );
    } catch (_) {
      throw const RpcTransportException(
        failure: RpcTransportFailure.invalidResponse,
        message: 'Electrum endpoint returned an invalid response.',
        retryable: true,
      );
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<void> close() async {}

  static String _safeError(Object error) {
    if (error is Map<Object?, Object?>) {
      return error['message']?.toString() ?? 'Electrum request failed.';
    }
    return 'Electrum request failed.';
  }
}

final class ElectrumException implements WalletError {
  const ElectrumException(
    this.message, {
    this.retryable = false,
    this.transactionNotFound = false,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  factory ElectrumException.fromServer(String serverMessage) {
    final normalized = serverMessage.toLowerCase();
    return ElectrumException(
      'Electrum server returned an error.',
      transactionNotFound:
          normalized.contains('not found') ||
          normalized.contains('no such mempool or blockchain transaction'),
      cause: serverMessage,
    );
  }

  @override
  final String message;

  @override
  final bool retryable;
  final bool transactionNotFound;

  @override
  WalletErrorCategory get category => WalletErrorCategory.chain;

  @override
  WalletErrorCode get publicCode => WalletErrorCode.chainBitcoinElectrum;

  @override
  String get errorCode => publicCode.value;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'ElectrumException: $message';
}
