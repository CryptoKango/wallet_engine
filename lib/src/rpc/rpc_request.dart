import '../error/wallet_error.dart';

/// HTTP methods required by supported RPC protocols.
enum RpcHttpMethod { get, post }

/// Transport-neutral RPC request.
final class RpcRequest {
  RpcRequest({
    required this.operation,
    this.method = RpcHttpMethod.post,
    this.path = '',
    this.body,
    Map<String, String> headers = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    this.timeout,
  }) : headers = Map<String, String>.unmodifiable(headers),
       queryParameters = Map<String, String>.unmodifiable(queryParameters) {
    if (operation.trim().isEmpty) {
      throw const WalletValidationException(
        field: 'operation',
        message: 'RPC operation must not be empty.',
      );
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      throw const WalletValidationException(
        field: 'path',
        message: 'RPC request path must be relative.',
      );
    }
  }

  /// Safe diagnostic name such as `eth_call`; never include request data.
  final String operation;
  final RpcHttpMethod method;
  final String path;
  final Object? body;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;
  final Duration? timeout;
}
