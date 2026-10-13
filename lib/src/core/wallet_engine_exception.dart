import '../error/wallet_error.dart';

/// Stable machine-readable wallet engine error codes.
enum WalletEngineErrorCode {
  chainNotConfigured,
  adapterNotRegistered,
  duplicateAdapter,
  configurationRollback,
  configurationUpdateInProgress,
  configurationUpdateFailed,
  engineClosed,
  sessionTypeMismatch,
  networkMismatch,
  networkVerificationUnsupported,
  accountServiceUnavailable,
}

/// Base exception exposed by the wallet engine core.
final class WalletEngineException implements WalletError {
  const WalletEngineException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final WalletEngineErrorCode code;

  @override
  final String message;

  @override
  WalletErrorCategory get category => switch (code) {
    WalletEngineErrorCode.engineClosed ||
    WalletEngineErrorCode.configurationUpdateInProgress =>
      WalletErrorCategory.engine,
    _ => WalletErrorCategory.configuration,
  };

  @override
  WalletErrorCode get publicCode => switch (code) {
    WalletEngineErrorCode.chainNotConfigured =>
      WalletErrorCode.engineChainNotConfigured,
    WalletEngineErrorCode.adapterNotRegistered =>
      WalletErrorCode.engineAdapterNotRegistered,
    WalletEngineErrorCode.duplicateAdapter =>
      WalletErrorCode.engineDuplicateAdapter,
    WalletEngineErrorCode.configurationRollback =>
      WalletErrorCode.engineConfigurationRollback,
    WalletEngineErrorCode.configurationUpdateInProgress =>
      WalletErrorCode.engineConfigurationUpdateInProgress,
    WalletEngineErrorCode.configurationUpdateFailed =>
      WalletErrorCode.engineConfigurationUpdateFailed,
    WalletEngineErrorCode.engineClosed => WalletErrorCode.engineClosed,
    WalletEngineErrorCode.sessionTypeMismatch =>
      WalletErrorCode.engineSessionTypeMismatch,
    WalletEngineErrorCode.networkMismatch =>
      WalletErrorCode.configurationNetworkMismatch,
    WalletEngineErrorCode.networkVerificationUnsupported =>
      WalletErrorCode.configurationNetworkVerificationUnsupported,
    WalletEngineErrorCode.accountServiceUnavailable =>
      WalletErrorCode.engineAccountServiceUnavailable,
  };

  @override
  String get errorCode => publicCode.value;

  @override
  bool get retryable => false;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'WalletEngineException(${code.name}): $message';
}
