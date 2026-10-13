/// Timeouts applied by the default RPC transport implementation.
final class RpcTransportConfig {
  const RpcTransportConfig({
    this.connectTimeout = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;

  void validate() {
    if (connectTimeout <= Duration.zero ||
        sendTimeout <= Duration.zero ||
        receiveTimeout <= Duration.zero) {
      throw ArgumentError(
        'RPC connect, send, and receive timeouts must be positive.',
      );
    }
  }
}
