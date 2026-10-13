import '../error/wallet_error.dart';

/// A single RPC endpoint supplied by the host application.
final class RpcEndpoint {
  RpcEndpoint({
    required this.uri,
    this.priority = 0,
    this.allowInsecureTransport = false,
    Map<String, String> headers = const <String, String>{},
  }) : headers = Map<String, String>.unmodifiable(headers) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const WalletValidationException(
        field: 'uri',
        message: 'RPC endpoint must be an absolute URI.',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if (!_supportedSchemes.contains(scheme)) {
      throw const WalletValidationException(
        field: 'uri',
        message: 'RPC endpoint uses an unsupported transport scheme.',
      );
    }
    if (_insecureSchemes.contains(scheme) && !allowInsecureTransport) {
      throw const WalletValidationException(
        field: 'uri',
        message: 'Insecure RPC transports require explicit opt-in.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const WalletValidationException(
        field: 'uri',
        message: 'RPC credentials must not be embedded in endpoint URLs.',
      );
    }
    if (uri.queryParameters.keys.any(_isSensitiveName)) {
      throw const WalletValidationException(
        field: 'uri',
        message: 'RPC credentials must not be embedded in endpoint queries.',
      );
    }
    if (headers.keys.any(_isSensitiveName)) {
      throw const WalletValidationException(
        field: 'headers',
        message: 'RPC credentials must use RpcCredentialProvider.',
      );
    }
  }

  factory RpcEndpoint.parse(
    String url, {
    int priority = 0,
    bool allowInsecureTransport = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    try {
      return RpcEndpoint(
        uri: Uri.parse(url),
        priority: priority,
        allowInsecureTransport: allowInsecureTransport,
        headers: headers,
      );
    } on WalletError {
      rethrow;
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletValidationException(
          field: 'uri',
          message: 'RPC endpoint URL is invalid.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  /// Absolute endpoint URI.
  final Uri uri;

  /// Higher values are preferred when an adapter uses priority failover.
  final int priority;

  /// Allows clear-text HTTP or Electrum TCP for explicitly trusted local or
  /// development environments. Production endpoints should leave this false.
  final bool allowInsecureTransport;

  /// Non-sensitive, static headers for this endpoint.
  ///
  /// Runtime credentials must be supplied by the transport credential port;
  /// they must not be persisted in configuration snapshots.
  final Map<String, String> headers;

  static const Set<String> _supportedSchemes = <String>{
    'https',
    'http',
    'tls',
    'ssl',
    'electrums',
    'tcp',
    'electrum',
  };

  static const Set<String> _insecureSchemes = <String>{
    'http',
    'tcp',
    'electrum',
  };

  static const Set<String> _sensitiveNames = <String>{
    'authorization',
    'proxy-authorization',
    'x-api-key',
    'apikey',
    'api_key',
    'api-key',
    'access_token',
    'accesstoken',
    'token',
    'secret',
    'password',
  };

  static bool _isSensitiveName(String value) {
    return _sensitiveNames.contains(value.trim().toLowerCase());
  }
}
