/// Controls structured RPC lifecycle logging.
///
/// Bodies are disabled by default because they may contain addresses,
/// calldata, signed transactions, or other application-sensitive data.
enum RpcLogBodyMode {
  /// Redacts known secrets and signed transaction payloads before logging.
  redacted,

  /// Emits the complete, length-limited body. Use only in controlled tooling.
  full,
}

final class RpcLoggingConfig {
  const RpcLoggingConfig({
    this.includeRequestBody = false,
    this.includeResponseBody = false,
    this.maxBodyCharacters = 8192,
    this.bodyMode = RpcLogBodyMode.redacted,
  }) : assert(maxBodyCharacters > 0, 'maxBodyCharacters must be positive');

  final bool includeRequestBody;
  final bool includeResponseBody;

  /// Maximum serialized characters retained for each request or response.
  final int maxBodyCharacters;

  /// Body redaction is enabled by default even after body logging is opted in.
  final RpcLogBodyMode bodyMode;

  void validate() {
    if (maxBodyCharacters <= 0) {
      throw ArgumentError.value(
        maxBodyCharacters,
        'maxBodyCharacters',
        'must be positive',
      );
    }
  }
}
