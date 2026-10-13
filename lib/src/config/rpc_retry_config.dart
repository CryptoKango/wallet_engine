/// Retry and endpoint cooldown policy shared by RPC pools.
final class RpcRetryConfig {
  const RpcRetryConfig({
    this.maxAttempts = 3,
    this.endpointCooldown = const Duration(seconds: 30),
    this.initialBackoff = const Duration(milliseconds: 200),
    this.maxBackoff = const Duration(seconds: 2),
  }) : assert(maxAttempts > 0, 'maxAttempts must be positive');

  final int maxAttempts;
  final Duration endpointCooldown;
  final Duration initialBackoff;
  final Duration maxBackoff;

  void validate() {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
    if (endpointCooldown.isNegative) {
      throw ArgumentError.value(
        endpointCooldown,
        'endpointCooldown',
        'must not be negative',
      );
    }
    if (initialBackoff.isNegative || maxBackoff.isNegative) {
      throw ArgumentError('RPC retry backoff durations must not be negative.');
    }
    if (maxBackoff < initialBackoff) {
      throw ArgumentError('RPC maxBackoff must not be below initialBackoff.');
    }
  }
}
