/// Broad error domains exposed by wallet_engine.
enum WalletErrorCategory {
  engine,
  configuration,
  validation,
  transport,
  rpc,
  signing,
  chain,
  transaction,
  internal,
}

/// Versioned, stable public error-code catalog.
///
/// Existing wire values must never be renamed or reused. New codes may be
/// appended without incrementing the major protocol version. Any semantic
/// change to an existing code requires a new protocol version.
enum WalletErrorCode {
  engineChainNotConfigured('engine.chainNotConfigured'),
  engineAdapterNotRegistered('engine.adapterNotRegistered'),
  engineDuplicateAdapter('engine.duplicateAdapter'),
  engineConfigurationRollback('engine.configurationRollback'),
  engineConfigurationUpdateInProgress('engine.configurationUpdateInProgress'),
  engineConfigurationUpdateFailed('engine.configurationUpdateFailed'),
  engineClosed('engine.engineClosed'),
  engineSessionTypeMismatch('engine.sessionTypeMismatch'),
  validationInvalidArgument('validation.invalidArgument'),
  rpcTransportTimeout('rpc.transport.timeout'),
  rpcTransportConnection('rpc.transport.connection'),
  rpcTransportInvalidResponse('rpc.transport.invalidResponse'),
  rpcTransportHttpStatus('rpc.transport.httpStatus'),
  rpcTransportCancelled('rpc.transport.cancelled'),
  rpcTransportUnknown('rpc.transport.unknown'),
  rpcJsonRpcInvalidResponse('rpc.jsonRpc.invalidResponse'),
  rpcJsonRpcServerError('rpc.jsonRpc.serverError'),
  signingInvalidPrivateKey('signing.invalidPrivateKey'),
  signingInvalidTransaction('signing.invalidTransaction'),
  signingNativeRuntimeUnavailable('signing.nativeRuntimeUnavailable'),
  signingFailed('signing.signingFailed'),
  chainBitcoinElectrum('chain.bitcoin.electrum'),
  chainTronRpc('chain.tron.rpc'),
  internalInvalidState('internal.invalidState'),
  internalUnknown('internal.unknown'),
  signingRuntimeNotInitialized('signing.runtimeNotInitialized'),
  configurationExpired('configuration.expired'),
  configurationSchemaUnsupported('configuration.schemaUnsupported'),
  configurationNetworkMismatch('configuration.networkMismatch'),
  configurationNetworkVerificationUnsupported(
    'configuration.networkVerificationUnsupported',
  ),
  transactionConfirmationTimeout('transaction.confirmationTimeout'),
  transactionConfirmationCancelled('transaction.confirmationCancelled'),
  chainSuiInsufficientGas('chain.sui.insufficientGas'),
  chainSuiInsufficientBalance('chain.sui.insufficientBalance'),
  chainSuiInvalidTransaction('chain.sui.invalidTransaction'),
  chainSuiObjectVersionConflict('chain.sui.objectVersionConflict'),
  chainSuiRpc('chain.sui.rpc'),
  accountInvalidMnemonic('account.invalidMnemonic'),
  accountInvalidAddress('account.invalidAddress'),
  accountInvalidPrivateKey('account.invalidPrivateKey'),
  accountUnsupportedChain('account.unsupportedChain'),
  accountGenerationFailed('account.generationFailed'),
  accountDerivationFailed('account.derivationFailed'),
  signingNativeVersionMismatch('signing.nativeVersionMismatch'),
  signingNativeSelfTestFailed('signing.nativeSelfTestFailed'),
  engineAccountServiceUnavailable('engine.accountServiceUnavailable');

  const WalletErrorCode(this.value);

  /// Stable serialized representation used across package boundaries.
  final String value;
}

/// Compatibility contract for serialized wallet errors.
abstract final class WalletErrorProtocol {
  /// Major version of the public error-code and diagnostic payload contract.
  static const int version = 1;

  static final Map<String, WalletErrorCode> _byValue =
      <String, WalletErrorCode>{
        for (final code in WalletErrorCode.values) code.value: code,
      };

  /// Parses a serialized code without throwing for codes introduced by a
  /// newer package version.
  static WalletErrorCode? tryParse(String value) => _byValue[value];
}

/// Common contract implemented by every public wallet_engine exception.
///
/// Callers can catch this type without depending on a chain or transport
/// implementation. [errorCode] is stable and intended for programmatic use;
/// [message] is sanitized and safe to show in logs.
abstract interface class WalletError implements Exception {
  WalletErrorCategory get category;

  WalletErrorCode get publicCode;

  String get errorCode;

  String get message;

  bool get retryable;

  /// Original error retained for diagnostics. It is deliberately omitted from
  /// [toString] and [WalletErrorDiagnostics.toDiagnosticMap] because it may
  /// contain sensitive data.
  Object? get cause;

  StackTrace? get stackTrace;

  /// Sanitized metadata such as an operation name, chain key, or status code.
  Map<String, Object?> get context;
}

/// A normalized error used when a dependency throws an exception that does
/// not implement [WalletError].
final class NormalizedWalletException implements WalletError {
  const NormalizedWalletException({
    required this.category,
    required this.publicCode,
    required this.message,
    required this.retryable,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  @override
  final WalletErrorCategory category;

  @override
  final WalletErrorCode publicCode;

  @override
  String get errorCode => publicCode.value;

  @override
  final String message;

  @override
  final bool retryable;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'NormalizedWalletException($errorCode): $message';
}

/// Invalid public input. Raw values are never retained or printed.
final class WalletValidationException implements WalletError {
  const WalletValidationException({
    required this.message,
    this.field,
    this.cause,
    this.stackTrace,
  });

  final String? field;

  @override
  WalletErrorCategory get category => WalletErrorCategory.validation;

  @override
  WalletErrorCode get publicCode => WalletErrorCode.validationInvalidArgument;

  @override
  String get errorCode => publicCode.value;

  @override
  final String message;

  @override
  bool get retryable => false;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  Map<String, Object?> get context => <String, Object?>{
    if (field != null) 'field': field,
  };

  @override
  String toString() => 'WalletValidationException($errorCode): $message';
}

/// Invalid internal state detected before execution can continue.
final class WalletStateException implements WalletError {
  const WalletStateException({
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  @override
  WalletErrorCategory get category => WalletErrorCategory.internal;

  @override
  WalletErrorCode get publicCode => WalletErrorCode.internalInvalidState;

  @override
  String get errorCode => publicCode.value;

  @override
  final String message;

  @override
  bool get retryable => false;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  final Map<String, Object?> context;

  @override
  String toString() => 'WalletStateException($errorCode): $message';
}

/// Converts arbitrary dependency and Dart errors to the public error contract.
abstract final class WalletErrorNormalizer {
  static WalletError normalize(
    Object error, {
    StackTrace? stackTrace,
    String? operation,
    String? chainKey,
  }) {
    if (error is WalletError) return error;

    final context = <String, Object?>{
      if (operation != null && operation.isNotEmpty) 'operation': operation,
      if (chainKey != null && chainKey.isNotEmpty) 'chainKey': chainKey,
    };

    if (error is ArgumentError || error is FormatException) {
      return NormalizedWalletException(
        category: WalletErrorCategory.validation,
        publicCode: WalletErrorCode.validationInvalidArgument,
        message: 'Invalid wallet engine input.',
        retryable: false,
        cause: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (error is StateError) {
      return NormalizedWalletException(
        category: WalletErrorCategory.internal,
        publicCode: WalletErrorCode.internalInvalidState,
        message: 'Wallet engine reached an invalid state.',
        retryable: false,
        cause: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    return NormalizedWalletException(
      category: WalletErrorCategory.internal,
      publicCode: WalletErrorCode.internalUnknown,
      message: 'Wallet engine operation failed.',
      retryable: false,
      cause: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Runs an asynchronous boundary and guarantees a [WalletError] on failure.
  static Future<T> guard<T>(
    Future<T> Function() action, {
    String? operation,
    String? chainKey,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        normalize(
          error,
          stackTrace: stackTrace,
          operation: operation,
          chainKey: chainKey,
        ),
        stackTrace,
      );
    }
  }

  /// Runs a synchronous boundary and guarantees a [WalletError] on failure.
  static T guardSync<T>(
    T Function() action, {
    String? operation,
    String? chainKey,
  }) {
    try {
      return action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        normalize(
          error,
          stackTrace: stackTrace,
          operation: operation,
          chainKey: chainKey,
        ),
        stackTrace,
      );
    }
  }
}

/// Safe, serializable diagnostics. The original [WalletError.cause] and stack
/// trace are intentionally excluded.
extension WalletErrorDiagnostics on WalletError {
  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'codeVersion': WalletErrorProtocol.version,
    'category': category.name,
    'code': errorCode,
    'message': message,
    'retryable': retryable,
    if (context.isNotEmpty) 'context': context,
  };
}
