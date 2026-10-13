import '../error/wallet_error.dart';
import 'rpc_logging_config.dart';
import 'rpc_retry_config.dart';
import 'rpc_transport_config.dart';
import 'wallet_chain_config.dart';

/// Immutable, validated configuration snapshot consumed by [WalletEngine].
final class WalletEngineConfig {
  WalletEngineConfig({
    required this.revision,
    required this.version,
    required List<WalletChainConfig> chains,
    this.transport = const RpcTransportConfig(),
    this.retry = const RpcRetryConfig(),
    this.rpcLogging = const RpcLoggingConfig(),
    this.issuedAt,
    this.expiresAt,
  }) : chains = Map<String, WalletChainConfig>.unmodifiable(
         _indexChains(chains),
       ) {
    if (revision < 0) {
      throw const WalletValidationException(
        field: 'revision',
        message: 'Configuration revision must not be negative.',
      );
    }
    if (version.trim().isEmpty) {
      throw const WalletValidationException(
        field: 'version',
        message: 'Configuration version must not be empty.',
      );
    }
    if (expiresAt != null &&
        issuedAt != null &&
        !expiresAt!.isAfter(issuedAt!)) {
      throw const WalletValidationException(
        field: 'expiresAt',
        message: 'Configuration expiry must be after its issue time.',
      );
    }
    _validateRuntimeConfiguration();
  }

  /// Monotonic revision used to reject accidental configuration rollback.
  final int revision;

  /// Human-readable source version for diagnostics.
  final String version;

  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final Map<String, WalletChainConfig> chains;
  final RpcTransportConfig transport;
  final RpcRetryConfig retry;
  final RpcLoggingConfig rpcLogging;

  bool isExpiredAt(DateTime instant) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(instant);
  }

  /// Enforces the snapshot validity window at an application-controlled time.
  void ensureUsableAt(DateTime instant) {
    if (isExpiredAt(instant)) {
      throw const NormalizedWalletException(
        category: WalletErrorCategory.configuration,
        publicCode: WalletErrorCode.configurationExpired,
        message: 'Wallet engine configuration has expired.',
        retryable: false,
      );
    }
  }

  void _validateRuntimeConfiguration() {
    try {
      transport.validate();
      retry.validate();
      rpcLogging.validate();
    } on ArgumentError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletValidationException(
          message: 'Wallet engine runtime configuration is invalid.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
    for (final chain in chains.values) {
      if (chain.key.trim().isEmpty ||
          chain.network.trim().isEmpty ||
          chain.nativeSymbol.trim().isEmpty ||
          chain.nativeDecimals < 0 ||
          (chain.chainId != null && chain.chainId!.trim().isEmpty)) {
        throw const WalletValidationException(
          field: 'chains',
          message: 'Wallet chain configuration contains invalid metadata.',
        );
      }
    }
  }

  static Map<String, WalletChainConfig> _indexChains(
    List<WalletChainConfig> chains,
  ) {
    if (chains.isEmpty) {
      throw const WalletValidationException(
        field: 'chains',
        message: 'Configuration must contain at least one chain.',
      );
    }

    final indexed = <String, WalletChainConfig>{};
    for (final chain in chains) {
      if (indexed.containsKey(chain.key)) {
        throw const WalletValidationException(
          field: 'chains',
          message: 'Configuration contains a duplicate chain key.',
        );
      }
      indexed[chain.key] = chain;
    }
    return indexed;
  }
}
