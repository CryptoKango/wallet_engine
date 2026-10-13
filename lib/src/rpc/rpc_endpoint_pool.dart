import 'dart:convert';

import '../config/rpc_endpoint.dart';
import '../config/rpc_logging_config.dart';
import '../config/rpc_pool_config.dart';
import '../config/rpc_retry_config.dart';
import '../error/wallet_error.dart';
import 'rpc_log_event.dart';
import 'rpc_transport_exception.dart';

typedef RpcAttempt<T> = Future<T> Function(RpcEndpoint endpoint);
typedef RpcRetryPredicate = bool Function(Object error);
typedef RpcResponseBody<T> = Object? Function(T result);
typedef RpcFailureResponseBody = Object? Function();

/// Per-chain, in-memory endpoint health and failover coordinator.
final class RpcEndpointPool {
  factory RpcEndpointPool({
    required String chainKey,
    required RpcPoolConfig config,
    required RpcRetryConfig retry,
    RpcLoggingConfig logging = const RpcLoggingConfig(),
    RpcLogSink? logSink,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  }) {
    retry.validate();
    logging.validate();
    return RpcEndpointPool._(
      chainKey,
      config,
      retry,
      logging,
      logSink,
      clock ?? DateTime.now,
      delay ?? Future<void>.delayed,
    );
  }

  RpcEndpointPool._(
    this.chainKey,
    this._config,
    this._retry,
    this._logging,
    this._logSink,
    this._clock,
    this._delay,
  );

  final String chainKey;
  final RpcPoolConfig _config;
  final RpcRetryConfig _retry;
  final RpcLoggingConfig _logging;
  final RpcLogSink? _logSink;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;
  final Map<Uri, DateTime> _cooldownUntil = <Uri, DateTime>{};
  int _cursor = 0;

  int get endpointCount => _config.endpoints.length;

  Future<T> execute<T>({
    required String operation,
    required RpcAttempt<T> attempt,
    required RpcRetryPredicate shouldRetry,
    Object? requestBody,
    RpcResponseBody<T>? responseBody,
    RpcFailureResponseBody? failureResponseBody,
  }) async {
    final ordered = _orderedEndpoints(_clock());
    final attemptCount = _retry.maxAttempts;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var index = 0; index < attemptCount; index++) {
      final candidate = ordered[index % ordered.length];
      final startedAt = _clock();
      _emit(
        RpcLogEvent(
          type: RpcLogEventType.attempt,
          chainKey: chainKey,
          operation: operation,
          endpointHost: candidate.endpoint.uri.host,
          attempt: index + 1,
          endpointCount: ordered.length,
          requestBody: _serializeBody(
            requestBody,
            enabled: _logging.includeRequestBody,
            operation: operation,
            isRequest: true,
          ),
        ),
      );
      try {
        final result = await attempt(candidate.endpoint);
        _cooldownUntil.remove(candidate.endpoint.uri);
        _cursor = (candidate.originalIndex + 1) % _config.endpoints.length;
        _emit(
          RpcLogEvent(
            type: RpcLogEventType.success,
            chainKey: chainKey,
            operation: operation,
            endpointHost: candidate.endpoint.uri.host,
            attempt: index + 1,
            endpointCount: ordered.length,
            duration: _clock().difference(startedAt),
            responseBody: responseBody == null
                ? null
                : _serializeBody(
                    responseBody(result),
                    enabled: _logging.includeResponseBody,
                    operation: operation,
                    isRequest: false,
                  ),
          ),
        );
        return result;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final retryable = shouldRetry(error);
        _emit(
          RpcLogEvent(
            type: RpcLogEventType.failure,
            chainKey: chainKey,
            operation: operation,
            endpointHost: candidate.endpoint.uri.host,
            attempt: index + 1,
            endpointCount: ordered.length,
            duration: _clock().difference(startedAt),
            errorType: error.runtimeType.toString(),
            errorCode: error is WalletError ? error.errorCode : null,
            retryable: retryable,
            responseBody: failureResponseBody == null
                ? null
                : _serializeBody(
                    failureResponseBody(),
                    enabled: _logging.includeResponseBody,
                    operation: operation,
                    isRequest: false,
                  ),
          ),
        );
        if (!retryable) {
          Error.throwWithStackTrace(
            WalletErrorNormalizer.normalize(
              error,
              stackTrace: stackTrace,
              operation: operation,
              chainKey: chainKey,
            ),
            stackTrace,
          );
        }
        _cooldownUntil[candidate.endpoint.uri] = _clock().add(
          _retry.endpointCooldown,
        );
        if (index + 1 < attemptCount && index + 1 >= ordered.length) {
          final backoff = _retryDelay(index, error);
          if (backoff > Duration.zero) await _delay(backoff);
        }
      }
    }

    throw RpcTransportException(
      failure: RpcTransportFailure.connection,
      message: 'All eligible RPC endpoints failed for $chainKey.',
      retryable: true,
      cause: lastError,
      stackTrace: lastStackTrace,
      context: <String, Object?>{
        'operation': operation,
        'chainKey': chainKey,
        'attempts': attemptCount,
      },
    );
  }

  Duration _retryDelay(int failedAttemptIndex, Object error) {
    final serverDelay = error is RpcTransportException
        ? error.retryAfter
        : null;
    if (serverDelay != null) {
      return serverDelay > _retry.maxBackoff ? _retry.maxBackoff : serverDelay;
    }
    if (_retry.initialBackoff == Duration.zero) return Duration.zero;
    final cycle = failedAttemptIndex ~/ _config.endpoints.length;
    final exponent = cycle > 20 ? 20 : cycle;
    final micros = _retry.initialBackoff.inMicroseconds * (1 << exponent);
    final calculated = Duration(microseconds: micros);
    return calculated > _retry.maxBackoff ? _retry.maxBackoff : calculated;
  }

  List<_EndpointCandidate> _orderedEndpoints(DateTime now) {
    final candidates = <_EndpointCandidate>[];
    for (var offset = 0; offset < _config.endpoints.length; offset++) {
      final index = (_cursor + offset) % _config.endpoints.length;
      candidates.add(
        _EndpointCandidate(
          endpoint: _config.endpoints[index],
          originalIndex: index,
          cooling:
              _cooldownUntil[_config.endpoints[index].uri]?.isAfter(now) ??
              false,
          relativeOrder: offset,
        ),
      );
    }

    candidates.sort((left, right) {
      if (left.cooling != right.cooling) return left.cooling ? 1 : -1;
      if (_config.strategy == RpcSelectionStrategy.priorityFailover &&
          left.endpoint.priority != right.endpoint.priority) {
        return right.endpoint.priority.compareTo(left.endpoint.priority);
      }
      return left.relativeOrder.compareTo(right.relativeOrder);
    });
    return candidates;
  }

  String? _serializeBody(
    Object? value, {
    required bool enabled,
    required String operation,
    required bool isRequest,
  }) {
    if (!enabled) return null;
    final safeValue = _logging.bodyMode == RpcLogBodyMode.full
        ? value
        : _redactBody(value, operation: operation, isRequest: isRequest);
    String serialized;
    try {
      serialized = jsonEncode(safeValue);
    } catch (_) {
      serialized = safeValue.toString();
    }
    if (serialized.length <= _logging.maxBodyCharacters) return serialized;
    return '${serialized.substring(0, _logging.maxBodyCharacters)}…';
  }

  static const Set<String> _sensitiveOperations = <String>{
    'eth_sendRawTransaction',
    'sendTransaction',
    'sui_executeTransactionBlock',
    'wallet/broadcasthex',
    'blockchain.transaction.broadcast',
  };

  static const Set<String> _sensitiveKeys = <String>{
    'authorization',
    'x-api-key',
    'apikey',
    'api_key',
    'privatekey',
    'private_key',
    'secret',
    'signature',
    'signatures',
    'signedtransaction',
    'rawtransaction',
    'encodedtransaction',
    'txbytes',
  };

  static Object? _redactBody(
    Object? value, {
    required String operation,
    required bool isRequest,
  }) {
    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.toLowerCase();
        final redactParams =
            isRequest &&
            key == 'params' &&
            _sensitiveOperations.contains(operation);
        final redactTransaction =
            isRequest &&
            normalized == 'transaction' &&
            _sensitiveOperations.contains(operation);
        result[key] =
            _sensitiveKeys.contains(normalized) ||
                redactParams ||
                redactTransaction
            ? '<redacted>'
            : _redactBody(
                entry.value,
                operation: operation,
                isRequest: isRequest,
              );
      }
      return result;
    }
    if (value is List<Object?>) {
      return value
          .map(
            (item) =>
                _redactBody(item, operation: operation, isRequest: isRequest),
          )
          .toList(growable: false);
    }
    return value;
  }

  void _emit(RpcLogEvent event) {
    try {
      _logSink?.call(event);
    } catch (_) {
      // Diagnostic hooks must never alter RPC execution.
    }
  }
}

final class _EndpointCandidate {
  const _EndpointCandidate({
    required this.endpoint,
    required this.originalIndex,
    required this.cooling,
    required this.relativeOrder,
  });

  final RpcEndpoint endpoint;
  final int originalIndex;
  final bool cooling;
  final int relativeOrder;
}
