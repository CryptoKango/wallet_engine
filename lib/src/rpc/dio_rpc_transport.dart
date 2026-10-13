import 'package:dio/dio.dart';

import '../config/rpc_endpoint.dart';
import '../config/rpc_transport_config.dart';
import 'rpc_credential_provider.dart';
import 'rpc_request.dart';
import 'rpc_response.dart';
import 'rpc_transport.dart';
import 'rpc_transport_exception.dart';

/// Dio-backed transport with runtime credential injection and sanitized
/// failures. It performs no logging and owns no endpoint selection state.
final class DioRpcTransport implements RpcTransport, ClosableRpcTransport {
  factory DioRpcTransport({
    Dio? dio,
    RpcCredentialProvider? credentialProvider,
  }) {
    return DioRpcTransport._(dio ?? Dio(), credentialProvider);
  }

  DioRpcTransport._(this._dio, this._credentialProvider);

  final Dio _dio;
  final RpcCredentialProvider? _credentialProvider;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _dio.close(force: true);
  }

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    if (_closed) {
      throw const RpcTransportException(
        failure: RpcTransportFailure.cancelled,
        message: 'RPC transport is closed.',
        retryable: false,
      );
    }
    final credentialHeaders =
        await _credentialProvider?.headersFor(endpoint) ??
        const <String, String>{};
    final resolved = _resolve(endpoint.uri, request.path);
    final uri = resolved.replace(
      queryParameters: <String, String>{
        ...endpoint.uri.queryParameters,
        ...resolved.queryParameters,
        ...request.queryParameters,
      },
    );

    try {
      final response = await _dio.request<Object?>(
        uri.toString(),
        data: request.body,
        options: Options(
          method: request.method == RpcHttpMethod.get ? 'GET' : 'POST',
          headers: <String, String>{
            ...endpoint.headers,
            ...credentialHeaders,
            ...request.headers,
          },
          connectTimeout: config.connectTimeout,
          sendTimeout: request.timeout ?? config.sendTimeout,
          receiveTimeout: request.timeout ?? config.receiveTimeout,
          validateStatus: (_) => true,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        final retryAfter = _parseRetryAfter(
          response.headers.value('retry-after'),
        );
        throw RpcTransportException(
          failure: RpcTransportFailure.httpStatus,
          message: 'RPC endpoint returned HTTP $statusCode.',
          retryable:
              statusCode == 408 || statusCode == 429 || statusCode >= 500,
          statusCode: statusCode,
          retryAfter: retryAfter,
          context: <String, Object?>{
            'statusCode': statusCode,
            if (retryAfter != null) 'retryAfterMs': retryAfter.inMilliseconds,
          },
        );
      }
      return RpcResponse(
        statusCode: statusCode,
        data: response.data,
        headers: response.headers.map,
      );
    } on RpcTransportException {
      rethrow;
    } on DioException catch (error) {
      throw _sanitizeDioException(error);
    } on FormatException {
      throw RpcTransportException(
        failure: RpcTransportFailure.invalidResponse,
        message: 'RPC endpoint returned an invalid response.',
        retryable: true,
      );
    } catch (_) {
      throw RpcTransportException(
        failure: RpcTransportFailure.unknown,
        message: 'RPC transport failed.',
        retryable: false,
      );
    }
  }

  static Uri _resolve(Uri base, String path) {
    if (path.isEmpty) return base;
    final normalizedBase = base.path.endsWith('/')
        ? base
        : base.replace(path: '${base.path}/');
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return normalizedBase.resolve(normalizedPath);
  }

  static RpcTransportException _sanitizeDioException(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => RpcTransportException(
        failure: RpcTransportFailure.timeout,
        message: 'RPC request timed out.',
        retryable: true,
      ),
      DioExceptionType.connectionError => RpcTransportException(
        failure: RpcTransportFailure.connection,
        message: 'RPC connection failed.',
        retryable: true,
      ),
      DioExceptionType.cancel => RpcTransportException(
        failure: RpcTransportFailure.cancelled,
        message: 'RPC request was cancelled.',
        retryable: false,
      ),
      DioExceptionType.badResponse => _badResponse(error),
      DioExceptionType.badCertificate ||
      DioExceptionType.unknown => RpcTransportException(
        failure: RpcTransportFailure.connection,
        message: 'RPC connection failed.',
        retryable: true,
      ),
    };
  }

  static RpcTransportException _badResponse(DioException error) {
    final statusCode = error.response?.statusCode;
    final retryAfter = _parseRetryAfter(
      error.response?.headers.value('retry-after'),
    );
    return RpcTransportException(
      failure: RpcTransportFailure.httpStatus,
      message: 'RPC endpoint returned an HTTP error.',
      retryable:
          statusCode == 408 || statusCode == 429 || (statusCode ?? 0) >= 500,
      statusCode: statusCode,
      retryAfter: retryAfter,
      context: <String, Object?>{
        'statusCode': ?statusCode,
        if (retryAfter != null) 'retryAfterMs': retryAfter.inMilliseconds,
      },
    );
  }

  static Duration? _parseRetryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    final date = DateTime.tryParse(value)?.toUtc();
    if (date == null) return null;
    final duration = date.difference(DateTime.now().toUtc());
    return duration.isNegative ? Duration.zero : duration;
  }
}
