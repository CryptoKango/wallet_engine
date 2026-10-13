import '../error/wallet_error.dart';

/// Stable machine-readable signing error codes.
enum WalletSigningErrorCode {
  invalidPrivateKey,
  invalidTransaction,
  nativeRuntimeUnavailable,
  nativeVersionMismatch,
  nativeSelfTestFailed,
  signingFailed,
  runtimeNotInitialized,
}

/// Sanitized signing failure. Private-key material is never included.
final class WalletSigningException implements WalletError {
  const WalletSigningException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final WalletSigningErrorCode code;

  @override
  final String message;

  @override
  WalletErrorCategory get category => WalletErrorCategory.signing;

  @override
  WalletErrorCode get publicCode => switch (code) {
    WalletSigningErrorCode.invalidPrivateKey =>
      WalletErrorCode.signingInvalidPrivateKey,
    WalletSigningErrorCode.invalidTransaction =>
      WalletErrorCode.signingInvalidTransaction,
    WalletSigningErrorCode.nativeRuntimeUnavailable =>
      WalletErrorCode.signingNativeRuntimeUnavailable,
    WalletSigningErrorCode.nativeVersionMismatch =>
      WalletErrorCode.signingNativeVersionMismatch,
    WalletSigningErrorCode.nativeSelfTestFailed =>
      WalletErrorCode.signingNativeSelfTestFailed,
    WalletSigningErrorCode.signingFailed => WalletErrorCode.signingFailed,
    WalletSigningErrorCode.runtimeNotInitialized =>
      WalletErrorCode.signingRuntimeNotInitialized,
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
  String toString() => 'WalletSigningException(${code.name}): $message';
}
