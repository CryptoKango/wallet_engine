/// Transport-neutral RPC response.
final class RpcResponse {
  RpcResponse({
    required this.statusCode,
    required this.data,
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) : headers = Map<String, List<String>>.unmodifiable(headers);

  final int statusCode;
  final Object? data;
  final Map<String, List<String>> headers;
}
