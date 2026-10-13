import '../error/wallet_error.dart';

enum WalletAccountErrorCode {
  invalidMnemonic,
  invalidAddress,
  invalidPrivateKey,
  unsupportedChain,
  generationFailed,
  derivationFailed,
}

/// Stable public failure raised by wallet creation and account derivation.
final class WalletAccountException implements WalletError {
  const WalletAccountException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final WalletAccountErrorCode code;

  @override
  final String message;

  @override
  WalletErrorCategory get category => switch (code) {
    WalletAccountErrorCode.invalidMnemonic ||
    WalletAccountErrorCode.invalidAddress ||
    WalletAccountErrorCode.invalidPrivateKey => WalletErrorCategory.validation,
    WalletAccountErrorCode.unsupportedChain => WalletErrorCategory.chain,
    WalletAccountErrorCode.generationFailed ||
    WalletAccountErrorCode.derivationFailed => WalletErrorCategory.internal,
  };

  @override
  WalletErrorCode get publicCode => switch (code) {
    WalletAccountErrorCode.invalidMnemonic =>
      WalletErrorCode.accountInvalidMnemonic,
    WalletAccountErrorCode.invalidAddress =>
      WalletErrorCode.accountInvalidAddress,
    WalletAccountErrorCode.invalidPrivateKey =>
      WalletErrorCode.accountInvalidPrivateKey,
    WalletAccountErrorCode.unsupportedChain =>
      WalletErrorCode.accountUnsupportedChain,
    WalletAccountErrorCode.generationFailed =>
      WalletErrorCode.accountGenerationFailed,
    WalletAccountErrorCode.derivationFailed =>
      WalletErrorCode.accountDerivationFailed,
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
  String toString() => 'WalletAccountException($errorCode): $message';
}
