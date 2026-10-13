import '../error/wallet_error.dart';
import '../rpc/rpc_log_event.dart';

/// Severity of a structured wallet engine diagnostic event.
enum WalletLogLevel { debug, info, warning, error }

/// Stable diagnostic domains emitted by wallet_engine.
enum WalletLogCategory {
  lifecycle,
  configuration,
  session,
  rpc,
  signing,
  account,
}

/// A sanitized, structured SDK diagnostic event.
///
/// Events never contain private keys, mnemonics, passphrases, credentials, or
/// stack traces. RPC bodies are present only when separately enabled by
/// `RpcLoggingConfig` and are redacted there before reaching this event.
final class WalletLogEvent {
  WalletLogEvent({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.operation,
    required String message,
    this.chainKey,
    this.duration,
    this.errorCode,
    Map<String, Object?> context = const <String, Object?>{},
  }) : message = _bounded(message, 1024),
       context = Map<String, Object?>.unmodifiable(_sanitizeMap(context));

  final DateTime timestamp;
  final WalletLogLevel level;
  final WalletLogCategory category;
  final String operation;
  final String message;
  final String? chainKey;
  final Duration? duration;
  final String? errorCode;
  final Map<String, Object?> context;

  /// JSON-compatible representation suitable for a host logger or telemetry.
  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'category': category.name,
    'operation': operation,
    'message': message,
    if (chainKey != null) 'chainKey': chainKey,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (errorCode != null) 'errorCode': errorCode,
    if (context.isNotEmpty) 'context': context,
  };

  @override
  String toString() => toDiagnosticMap().toString();

  static const Set<String> _sensitiveKeys = <String>{
    'authorization',
    'password',
    'passphrase',
    'mnemonic',
    'privatekey',
    'private_key',
    'secret',
    'token',
    'apikey',
    'api_key',
    'signature',
    'signedtransaction',
    'rawtransaction',
    'encodedtransaction',
    'txbytes',
  };

  static Map<String, Object?> _sanitizeMap(Map<String, Object?> source) {
    return <String, Object?>{
      for (final entry in source.entries)
        entry.key: _sensitiveKeys.contains(entry.key.toLowerCase())
            ? '<redacted>'
            : _sanitizeValue(entry.value, 0),
    };
  }

  static Object? _sanitizeValue(Object? value, int depth) {
    if (value == null || value is num || value is bool) return value;
    if (depth >= 4) return '<truncated>';
    if (value is String) return _bounded(value, 2048);
    if (value is Enum) return value.name;
    if (value is Duration) return value.inMilliseconds;
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        result[key] = _sensitiveKeys.contains(key.toLowerCase())
            ? '<redacted>'
            : _sanitizeValue(entry.value, depth + 1);
      }
      return result;
    }
    if (value is Iterable) {
      return value
          .take(100)
          .map((item) => _sanitizeValue(item, depth + 1))
          .toList(growable: false);
    }
    return value.runtimeType.toString();
  }

  static String _bounded(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}…';
  }
}

typedef WalletLogSink = void Function(WalletLogEvent event);

/// Process-wide, failure-isolated diagnostic logger.
///
/// Omitting a logger disables general SDK logs. Exceptions thrown by [sink]
/// are swallowed so diagnostics can never alter wallet execution.
final class WalletLogger {
  factory WalletLogger({
    required WalletLogSink sink,
    WalletLogLevel minimumLevel = WalletLogLevel.info,
    DateTime Function()? clock,
  }) {
    return WalletLogger._(sink, minimumLevel, clock ?? DateTime.now);
  }

  WalletLogger.disabled() : this._(null, WalletLogLevel.error, DateTime.now);

  WalletLogger._(this._sink, this.minimumLevel, this._clock);

  final WalletLogLevel minimumLevel;
  final WalletLogSink? _sink;
  final DateTime Function() _clock;

  bool get enabled => _sink != null;

  void log({
    required WalletLogLevel level,
    required WalletLogCategory category,
    required String operation,
    required String message,
    String? chainKey,
    Duration? duration,
    Object? error,
    String? errorCode,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final sink = _sink;
    if (sink == null || level.index < minimumLevel.index) return;
    final walletError = error is WalletError ? error : null;
    try {
      sink(
        WalletLogEvent(
          timestamp: _clock().toUtc(),
          level: level,
          category: category,
          operation: operation,
          message: message,
          chainKey: chainKey,
          duration: duration,
          errorCode: errorCode ?? walletError?.errorCode,
          context: <String, Object?>{
            ...context,
            if (walletError != null) ...walletError.context,
            if (error != null) 'errorType': error.runtimeType.toString(),
            if (walletError != null) 'retryable': walletError.retryable,
          },
        ),
      );
    } catch (_) {
      // Diagnostic hooks must never alter SDK execution.
    }
  }

  /// Converts the existing RPC event stream into the common SDK log stream.
  void recordRpc(RpcLogEvent event) {
    final level = switch (event.type) {
      RpcLogEventType.attempt => WalletLogLevel.debug,
      RpcLogEventType.success => WalletLogLevel.info,
      RpcLogEventType.failure => WalletLogLevel.warning,
    };
    log(
      level: level,
      category: WalletLogCategory.rpc,
      operation: 'rpc.${event.type.name}',
      message: switch (event.type) {
        RpcLogEventType.attempt => 'RPC request started.',
        RpcLogEventType.success => 'RPC request completed.',
        RpcLogEventType.failure => 'RPC request failed.',
      },
      chainKey: event.chainKey,
      duration: event.duration,
      errorCode: event.errorCode,
      context: <String, Object?>{
        'rpcOperation': event.operation,
        'endpointHost': event.endpointHost,
        'attempt': event.attempt,
        'endpointCount': event.endpointCount,
        if (event.errorType != null) 'errorType': event.errorType,
        if (event.retryable != null) 'retryable': event.retryable,
        if (event.requestBody != null) 'requestBody': event.requestBody,
        if (event.responseBody != null) 'responseBody': event.responseBody,
      },
    );
  }
}
