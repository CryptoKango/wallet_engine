import 'dart:typed_data';

import '../logging/wallet_logger.dart';
import '../signing/wallet_signing_exception.dart';
import 'wallet_core_bridge_manifest.dart';
import 'wallet_core_native_bridge.dart';

/// Process lifetime state of an owned Wallet Core native artifact.
enum WalletCoreNativeRuntimeState { uninitialized, initializing, ready, failed }

/// Initializes and validates a first-party Wallet Core bridge exactly once.
///
/// A failure is sticky for this runtime instance. Loading a different native
/// artifact after signing has started is intentionally unsupported.
final class WalletCoreNativeRuntime {
  WalletCoreNativeRuntime({
    required WalletCoreNativeBridge bridge,
    WalletCoreBridgeManifest manifest = walletCoreProductionManifest,
    WalletLogger? logger,
  }) : this._(bridge, manifest, logger ?? WalletLogger.disabled());

  WalletCoreNativeRuntime._(this._bridge, this.manifest, this._logger);

  final WalletCoreNativeBridge _bridge;
  final WalletCoreBridgeManifest manifest;
  final WalletLogger _logger;

  WalletCoreNativeRuntimeState _state =
      WalletCoreNativeRuntimeState.uninitialized;
  Future<WalletCoreNativeBridgeInfo>? _initialization;
  WalletCoreNativeBridgeInfo? _info;
  WalletSigningException? _failure;

  WalletCoreNativeRuntimeState get state => _state;
  bool get isInitialized => _state == WalletCoreNativeRuntimeState.ready;
  WalletCoreNativeBridgeInfo? get info => _info;
  WalletSigningException? get failure => _failure;

  /// Loads, verifies, and self-tests the native artifact once.
  Future<WalletCoreNativeBridgeInfo> initialize() {
    final existing = _initialization;
    if (existing != null) {
      _logger.log(
        level: WalletLogLevel.debug,
        category: WalletLogCategory.lifecycle,
        operation: 'native.initialize',
        message: 'Reusing Wallet Core initialization result.',
        context: <String, Object?>{'state': _state.name},
      );
      return existing;
    }

    _state = WalletCoreNativeRuntimeState.initializing;
    _logger.log(
      level: WalletLogLevel.info,
      category: WalletLogCategory.lifecycle,
      operation: 'native.initialize',
      message: 'Initializing Wallet Core native runtime.',
      context: <String, Object?>{
        'expectedAbi': manifest.abiVersion,
        'expectedVersion': manifest.upstreamVersion,
      },
    );
    final pending = _initialize();
    _initialization = pending;
    return pending;
  }

  Future<WalletCoreNativeBridgeInfo> _initialize() async {
    final stopwatch = Stopwatch()..start();
    try {
      final loaded = await _bridge.load();
      _verifyMetadata(loaded);
      try {
        await _bridge.selfTest();
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          WalletSigningException(
            code: WalletSigningErrorCode.nativeSelfTestFailed,
            message: 'Wallet Core native self-test failed.',
            cause: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      _info = loaded;
      _state = WalletCoreNativeRuntimeState.ready;
      _logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.lifecycle,
        operation: 'native.initialize',
        message: 'Wallet Core native runtime initialized.',
        duration: stopwatch.elapsed,
        context: <String, Object?>{
          'abiVersion': loaded.abiVersion,
          'upstreamVersion': loaded.upstreamVersion,
          'selfTest': 'passed',
        },
      );
      return loaded;
    } on WalletSigningException catch (error, stackTrace) {
      _failure = error;
      _state = WalletCoreNativeRuntimeState.failed;
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.lifecycle,
        operation: 'native.initialize',
        message: 'Wallet Core native runtime initialization failed.',
        duration: stopwatch.elapsed,
        error: error,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      final normalized = WalletSigningException(
        code: WalletSigningErrorCode.nativeRuntimeUnavailable,
        message: 'Wallet Core native runtime could not be initialized.',
        cause: error,
        stackTrace: stackTrace,
      );
      _failure = normalized;
      _state = WalletCoreNativeRuntimeState.failed;
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.lifecycle,
        operation: 'native.initialize',
        message: 'Wallet Core native runtime initialization failed.',
        duration: stopwatch.elapsed,
        error: normalized,
      );
      Error.throwWithStackTrace(normalized, stackTrace);
    }
  }

  void _verifyMetadata(WalletCoreNativeBridgeInfo loaded) {
    if (loaded.abiVersion != manifest.abiVersion ||
        loaded.upstreamVersion != manifest.upstreamVersion ||
        loaded.upstreamCommit != manifest.upstreamCommit) {
      throw WalletSigningException(
        code: WalletSigningErrorCode.nativeVersionMismatch,
        message: 'Wallet Core native artifact does not match the approved pin.',
        context: <String, Object?>{
          'expectedAbi': manifest.abiVersion,
          'actualAbi': loaded.abiVersion,
          'expectedUpstreamVersion': manifest.upstreamVersion,
          'actualUpstreamVersion': loaded.upstreamVersion,
          'expectedUpstreamCommit': manifest.upstreamCommit,
          'actualUpstreamCommit': loaded.upstreamCommit,
        },
      );
    }
  }

  /// Throws unless application startup completed native validation.
  void ensureInitialized() {
    if (isInitialized) return;
    final previousFailure = _failure;
    if (previousFailure != null) throw previousFailure;
    throw const WalletSigningException(
      code: WalletSigningErrorCode.runtimeNotInitialized,
      message: 'Wallet Core must be initialized during application startup.',
    );
  }

  /// Executes the narrow native JSON signing operation after startup checks.
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    ensureInitialized();
    if (!_bridge.supportsJsonSigning(coinType)) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not support JSON signing for coin.',
      );
    }
    try {
      return _runNative<Uint8List>(
        category: WalletLogCategory.signing,
        operation: 'native.sign.json',
        context: <String, Object?>{
          'coinType': coinType,
          'inputLength': json.length,
        },
        action: () => _bridge.signJson(
          coinType: coinType,
          json: json,
          privateKey: privateKey,
        ),
      );
    } on WalletSigningException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native signing failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  /// Signs a prepared 32-byte digest through the owned native artifact.
  Uint8List signSecp256k1({
    required Uint8List privateKey,
    required Uint8List digest,
  }) {
    ensureInitialized();
    final bridge = _bridge;
    if (bridge is! WalletCoreSecp256k1Bridge) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not expose secp256k1 signing.',
      );
    }
    final signer = bridge as WalletCoreSecp256k1Bridge;
    try {
      return _runNative<Uint8List>(
        category: WalletLogCategory.signing,
        operation: 'native.sign.secp256k1',
        context: <String, Object?>{'digestLength': digest.length},
        action: () =>
            signer.signSecp256k1(privateKey: privateKey, digest: digest),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native secp256k1 signing failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  Uint8List signProto({required int coinType, required Uint8List input}) {
    ensureInitialized();
    final bridge = _bridge;
    if (bridge is! WalletCoreProtoBridge) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not expose protobuf signing.',
      );
    }
    final signer = bridge as WalletCoreProtoBridge;
    try {
      return _runNative<Uint8List>(
        category: WalletLogCategory.signing,
        operation: 'native.sign.protobuf',
        context: <String, Object?>{
          'coinType': coinType,
          'inputLength': input.length,
        },
        action: () => signer.signProto(coinType: coinType, input: input),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native protobuf signing failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  String signEvmMessage({
    required WalletCoreEvmMessageMode mode,
    required String message,
    required Uint8List privateKey,
  }) {
    ensureInitialized();
    final bridge = _bridge;
    if (bridge is! WalletCoreEvmMessageBridge) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not expose EVM message signing.',
      );
    }
    final signer = bridge as WalletCoreEvmMessageBridge;
    try {
      return _runNative<String>(
        category: WalletLogCategory.signing,
        operation: 'native.sign.evmMessage',
        context: <String, Object?>{
          'mode': mode.name,
          'messageLength': message.length,
        },
        action: () => signer.signEvmMessage(
          mode: mode,
          message: message,
          privateKey: privateKey,
        ),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native EVM message signing failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  WalletCoreKeyInfo deriveKey({
    required int coinType,
    required String mnemonic,
    required String passphrase,
    required String derivationPath,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    ensureInitialized();
    final bridge = _bridge;
    if (bridge is! WalletCoreKeyDerivationBridge) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not expose HD key derivation.',
      );
    }
    final derivation = bridge as WalletCoreKeyDerivationBridge;
    try {
      return _runNative<WalletCoreKeyInfo>(
        category: WalletLogCategory.account,
        operation: 'native.account.derive',
        context: <String, Object?>{
          'coinType': coinType,
          'publicKeyMode': publicKeyMode.name,
        },
        action: () => derivation.deriveKey(
          coinType: coinType,
          mnemonic: mnemonic,
          passphrase: passphrase,
          derivationPath: derivationPath,
          publicKeyMode: publicKeyMode,
        ),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native key derivation failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  WalletCoreKeyInfo inspectKey({
    required int coinType,
    required Uint8List privateKey,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    ensureInitialized();
    final bridge = _bridge;
    if (bridge is! WalletCoreKeyDerivationBridge) {
      throw const WalletSigningException(
        code: WalletSigningErrorCode.signingFailed,
        message: 'Native Wallet Core does not expose key inspection.',
      );
    }
    final derivation = bridge as WalletCoreKeyDerivationBridge;
    try {
      return _runNative<WalletCoreKeyInfo>(
        category: WalletLogCategory.account,
        operation: 'native.account.inspect',
        context: <String, Object?>{
          'coinType': coinType,
          'publicKeyMode': publicKeyMode.name,
        },
        action: () => derivation.inspectKey(
          coinType: coinType,
          privateKey: privateKey,
          publicKeyMode: publicKeyMode,
        ),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'Wallet Core native key inspection failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  T _runNative<T>({
    required WalletLogCategory category,
    required String operation,
    required T Function() action,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final stopwatch = Stopwatch()..start();
    _logger.log(
      level: WalletLogLevel.debug,
      category: category,
      operation: operation,
      message: 'Native wallet operation started.',
      context: context,
    );
    try {
      final result = action();
      _logger.log(
        level: WalletLogLevel.info,
        category: category,
        operation: operation,
        message: 'Native wallet operation completed.',
        duration: stopwatch.elapsed,
        context: context,
      );
      return result;
    } catch (error) {
      final diagnosticError = error is WalletSigningException
          ? error
          : WalletSigningException(
              code: WalletSigningErrorCode.signingFailed,
              message: 'Native wallet operation failed.',
              cause: error,
            );
      _logger.log(
        level: WalletLogLevel.error,
        category: category,
        operation: operation,
        message: 'Native wallet operation failed.',
        duration: stopwatch.elapsed,
        error: diagnosticError,
        context: context,
      );
      rethrow;
    }
  }
}
