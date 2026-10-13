import '../error/wallet_error.dart';
import 'json_rpc_exception.dart';
import 'rpc_client.dart';
import 'rpc_request.dart';
import 'rpc_response.dart';

typedef JsonRpcResultDecoder<T> = T Function(Object? result);
typedef JsonRpcErrorRetryPolicy = bool Function(int? code, String message);
typedef JsonRpcErrorDecoder =
    WalletError Function(
      int? code,
      String message,
      bool retryable,
      Map<String, Object?> context,
    );

/// JSON-RPC 2.0 protocol client built on the endpoint-aware [RpcClient].
final class JsonRpcClient {
  factory JsonRpcClient({
    required RpcClient rpc,
    JsonRpcErrorRetryPolicy? errorRetryPolicy,
    JsonRpcErrorDecoder? errorDecoder,
  }) {
    return JsonRpcClient._(
      rpc,
      errorRetryPolicy ?? _defaultErrorRetryPolicy,
      errorDecoder,
    );
  }

  JsonRpcClient._(this._rpc, this._errorRetryPolicy, this._errorDecoder);

  final RpcClient _rpc;
  final JsonRpcErrorRetryPolicy _errorRetryPolicy;
  final JsonRpcErrorDecoder? _errorDecoder;
  int _nextId = 0;

  Future<T> call<T>({
    required String method,
    List<Object?> params = const <Object?>[],
    required JsonRpcResultDecoder<T> decode,
    Duration? timeout,
  }) {
    if (method.trim().isEmpty) {
      throw const WalletValidationException(
        field: 'method',
        message: 'JSON-RPC method must not be empty.',
      );
    }
    final id = ++_nextId;
    return _rpc.execute<T>(
      RpcRequest(
        operation: method,
        body: <String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        },
        headers: const <String, String>{'Content-Type': 'application/json'},
        timeout: timeout,
      ),
      decode: (response) =>
          _decodeResponse(response, expectedId: id, decode: decode),
      shouldRetry: _shouldRetry,
    );
  }

  T _decodeResponse<T>(
    RpcResponse response, {
    required int expectedId,
    required JsonRpcResultDecoder<T> decode,
  }) {
    final data = response.data;
    if (data is! Map<Object?, Object?>) {
      throw const JsonRpcException(
        message: 'RPC endpoint returned a non-object JSON-RPC response.',
        retryable: true,
      );
    }

    final responseId = data['id'];
    if (responseId != expectedId) {
      throw const JsonRpcException(
        message: 'RPC endpoint returned a mismatched response ID.',
        retryable: true,
      );
    }

    final error = data['error'];
    if (error != null) {
      if (error is! Map<Object?, Object?>) {
        throw const JsonRpcException(
          message: 'RPC endpoint returned an invalid error object.',
          retryable: true,
        );
      }
      final codeValue = error['code'];
      final code = codeValue is int ? codeValue : null;
      final messageValue = error['message'];
      final message = messageValue is String
          ? messageValue
          : 'RPC endpoint returned an unspecified error.';
      final retryable = _errorRetryPolicy(code, message);
      final context = <String, Object?>{'rpcCode': ?code};
      throw _errorDecoder?.call(code, message, retryable, context) ??
          JsonRpcException(
            code: code,
            message: 'JSON-RPC server returned an error.',
            retryable: retryable,
            cause: message,
            context: context,
          );
    }

    if (!data.containsKey('result')) {
      throw const JsonRpcException(
        message: 'RPC endpoint response has no result.',
        retryable: true,
      );
    }
    try {
      return decode(data['result']);
    } on JsonRpcException {
      rethrow;
    } catch (_) {
      throw const JsonRpcException(
        message: 'RPC endpoint returned an invalid result.',
        retryable: true,
      );
    }
  }

  static bool _shouldRetry(Object error) {
    return error is WalletError && error.retryable;
  }

  static bool _defaultErrorRetryPolicy(int? code, String message) {
    final normalized = message.toLowerCase();
    if (code == -32005 ||
        normalized.contains('rate limit') ||
        normalized.contains('too many requests') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('server overloaded') ||
        normalized.contains('timeout')) {
      return true;
    }
    return false;
  }
}
