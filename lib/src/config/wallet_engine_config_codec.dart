import '../error/wallet_error.dart';
import 'chain_family.dart';
import 'rpc_endpoint.dart';
import 'rpc_logging_config.dart';
import 'rpc_pool_config.dart';
import 'rpc_retry_config.dart';
import 'rpc_transport_config.dart';
import 'wallet_chain_config.dart';
import 'wallet_engine_config.dart';

/// Stable JSON-compatible representation of [WalletEngineConfig].
///
/// Credentials are intentionally excluded. Runtime credentials must continue
/// to come from `RpcCredentialProvider`.
abstract final class WalletEngineConfigCodec {
  static const int schemaVersion = 1;

  static Map<String, Object?> encode(WalletEngineConfig config) {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'revision': config.revision,
      'version': config.version,
      if (config.issuedAt != null)
        'issuedAt': config.issuedAt!.toUtc().toIso8601String(),
      if (config.expiresAt != null)
        'expiresAt': config.expiresAt!.toUtc().toIso8601String(),
      'transport': <String, Object?>{
        'connectTimeoutMs': config.transport.connectTimeout.inMilliseconds,
        'sendTimeoutMs': config.transport.sendTimeout.inMilliseconds,
        'receiveTimeoutMs': config.transport.receiveTimeout.inMilliseconds,
      },
      'retry': <String, Object?>{
        'maxAttempts': config.retry.maxAttempts,
        'endpointCooldownMs': config.retry.endpointCooldown.inMilliseconds,
        'initialBackoffMs': config.retry.initialBackoff.inMilliseconds,
        'maxBackoffMs': config.retry.maxBackoff.inMilliseconds,
      },
      'rpcLogging': <String, Object?>{
        'includeRequestBody': config.rpcLogging.includeRequestBody,
        'includeResponseBody': config.rpcLogging.includeResponseBody,
        'maxBodyCharacters': config.rpcLogging.maxBodyCharacters,
        'bodyMode': config.rpcLogging.bodyMode.name,
      },
      'chains': config.chains.values.map(_encodeChain).toList(growable: false),
    };
  }

  static WalletEngineConfig decode(Map<String, Object?> json) {
    try {
      final version = _int(json, 'schemaVersion');
      if (version != schemaVersion) {
        throw NormalizedWalletException(
          category: WalletErrorCategory.configuration,
          publicCode: WalletErrorCode.configurationSchemaUnsupported,
          message: 'Wallet engine configuration schema is not supported.',
          retryable: false,
          context: <String, Object?>{'schemaVersion': version},
        );
      }
      final transport = _objectOrEmpty(json['transport'], 'transport');
      final retry = _objectOrEmpty(json['retry'], 'retry');
      final logging = _objectOrEmpty(json['rpcLogging'], 'rpcLogging');
      final chainsValue = json['chains'];
      if (chainsValue is! List<Object?>) {
        throw const FormatException('chains must be a list');
      }
      return WalletEngineConfig(
        revision: _int(json, 'revision'),
        version: _string(json, 'version'),
        issuedAt: _dateTimeOrNull(json['issuedAt'], 'issuedAt'),
        expiresAt: _dateTimeOrNull(json['expiresAt'], 'expiresAt'),
        transport: RpcTransportConfig(
          connectTimeout: Duration(
            milliseconds: _intOr(
              transport,
              'connectTimeoutMs',
              const Duration(seconds: 15).inMilliseconds,
            ),
          ),
          sendTimeout: Duration(
            milliseconds: _intOr(
              transport,
              'sendTimeoutMs',
              const Duration(seconds: 30).inMilliseconds,
            ),
          ),
          receiveTimeout: Duration(
            milliseconds: _intOr(
              transport,
              'receiveTimeoutMs',
              const Duration(seconds: 30).inMilliseconds,
            ),
          ),
        ),
        retry: RpcRetryConfig(
          maxAttempts: _intOr(retry, 'maxAttempts', 3),
          endpointCooldown: Duration(
            milliseconds: _intOr(retry, 'endpointCooldownMs', 30000),
          ),
          initialBackoff: Duration(
            milliseconds: _intOr(retry, 'initialBackoffMs', 200),
          ),
          maxBackoff: Duration(
            milliseconds: _intOr(retry, 'maxBackoffMs', 2000),
          ),
        ),
        rpcLogging: RpcLoggingConfig(
          includeRequestBody: _boolOr(logging, 'includeRequestBody', false),
          includeResponseBody: _boolOr(logging, 'includeResponseBody', false),
          maxBodyCharacters: _intOr(logging, 'maxBodyCharacters', 8192),
          bodyMode: _enumByName(
            RpcLogBodyMode.values,
            _stringOr(logging, 'bodyMode', RpcLogBodyMode.redacted.name),
            'rpcLogging.bodyMode',
          ),
        ),
        chains: chainsValue
            .map((value) => _decodeChain(_object(value, 'chains[]')))
            .toList(growable: false),
      );
    } on WalletError {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletValidationException(
          field: 'config',
          message: 'Wallet engine configuration JSON is invalid.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _encodeChain(WalletChainConfig chain) {
    return <String, Object?>{
      'key': chain.key,
      'family': chain.family.name,
      'network': chain.network,
      if (chain.chainId != null) 'chainId': chain.chainId,
      'nativeSymbol': chain.nativeSymbol,
      'nativeDecimals': chain.nativeDecimals,
      'rpcPool': <String, Object?>{
        'strategy': chain.rpcPool.strategy.name,
        'endpoints': chain.rpcPool.endpoints
            .map(
              (endpoint) => <String, Object?>{
                'url': endpoint.uri.toString(),
                'priority': endpoint.priority,
                if (endpoint.allowInsecureTransport)
                  'allowInsecureTransport': true,
                if (endpoint.headers.isNotEmpty) 'headers': endpoint.headers,
              },
            )
            .toList(growable: false),
      },
    };
  }

  static WalletChainConfig _decodeChain(Map<String, Object?> json) {
    final pool = _object(json['rpcPool'], 'rpcPool');
    final endpointsValue = pool['endpoints'];
    if (endpointsValue is! List<Object?>) {
      throw const FormatException('rpcPool.endpoints must be a list');
    }
    return WalletChainConfig(
      key: _string(json, 'key'),
      family: _enumByName(
        ChainFamily.values,
        _string(json, 'family'),
        'family',
      ),
      network: _string(json, 'network'),
      chainId: _nullableString(json['chainId'], 'chainId'),
      nativeSymbol: _string(json, 'nativeSymbol'),
      nativeDecimals: _int(json, 'nativeDecimals'),
      rpcPool: RpcPoolConfig(
        strategy: _enumByName(
          RpcSelectionStrategy.values,
          _stringOr(
            pool,
            'strategy',
            RpcSelectionStrategy.priorityFailover.name,
          ),
          'rpcPool.strategy',
        ),
        endpoints: endpointsValue
            .map((value) {
              final endpoint = _object(value, 'endpoint');
              return RpcEndpoint.parse(
                _string(endpoint, 'url'),
                priority: _intOr(endpoint, 'priority', 0),
                allowInsecureTransport: _boolOr(
                  endpoint,
                  'allowInsecureTransport',
                  false,
                ),
                headers: _stringMapOrEmpty(endpoint['headers']),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  static Map<String, Object?> _object(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map<Object?, Object?>) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw FormatException('$field must be an object');
  }

  static Map<String, Object?> _objectOrEmpty(Object? value, String field) {
    return value == null ? <String, Object?>{} : _object(value, field);
  }

  static String _string(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('$field must be a non-empty string');
  }

  static String _stringOr(
    Map<String, Object?> json,
    String field,
    String fallback,
  ) {
    return json[field] == null ? fallback : _string(json, field);
  }

  static String? _nullableString(Object? value, String field) {
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('$field must be a non-empty string');
  }

  static int _int(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is int) return value;
    throw FormatException('$field must be an integer');
  }

  static int _intOr(Map<String, Object?> json, String field, int fallback) {
    return json[field] == null ? fallback : _int(json, field);
  }

  static bool _boolOr(Map<String, Object?> json, String field, bool fallback) {
    final value = json[field];
    if (value == null) return fallback;
    if (value is bool) return value;
    throw FormatException('$field must be a boolean');
  }

  static DateTime? _dateTimeOrNull(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$field must be a string');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$field must be ISO-8601');
    return parsed.toUtc();
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    String field,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('$field contains an unsupported value');
  }

  static Map<String, String> _stringMapOrEmpty(Object? value) {
    if (value == null) return const <String, String>{};
    final map = _object(value, 'headers');
    return map.map((key, item) {
      if (item is! String) {
        throw const FormatException('header values must be strings');
      }
      return MapEntry(key, item);
    });
  }
}
