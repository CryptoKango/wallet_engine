import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'wallet_core_native_bridge.dart';

typedef _Uint32Native = Uint32 Function();
typedef _Uint32Dart = int Function();
typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _BytesNative = Pointer<Uint8> Function();
typedef _BytesDart = Pointer<Uint8> Function();
typedef _SupportsJsonNative = Uint8 Function(Uint32 coinType);
typedef _SupportsJsonDart = int Function(int coinType);
typedef _SignJsonNative =
    Int32 Function(
      Uint32 coinType,
      Pointer<Uint8> json,
      Uint32 jsonLength,
      Pointer<Uint8> privateKey,
      Uint32 privateKeyLength,
      Pointer<Uint8> output,
      Uint32 outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignJsonDart =
    int Function(
      int coinType,
      Pointer<Uint8> json,
      int jsonLength,
      Pointer<Uint8> privateKey,
      int privateKeyLength,
      Pointer<Uint8> output,
      int outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignSecp256k1Native =
    Int32 Function(
      Pointer<Uint8> privateKey,
      Uint32 privateKeyLength,
      Pointer<Uint8> digest,
      Uint32 digestLength,
      Pointer<Uint8> output,
      Uint32 outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignSecp256k1Dart =
    int Function(
      Pointer<Uint8> privateKey,
      int privateKeyLength,
      Pointer<Uint8> digest,
      int digestLength,
      Pointer<Uint8> output,
      int outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignProtoNative =
    Int32 Function(
      Uint32 coinType,
      Pointer<Uint8> input,
      Uint32 inputLength,
      Pointer<Uint8> output,
      Uint32 outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignProtoDart =
    int Function(
      int coinType,
      Pointer<Uint8> input,
      int inputLength,
      Pointer<Uint8> output,
      int outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignEvmMessageNative =
    Int32 Function(
      Uint32 mode,
      Pointer<Uint8> message,
      Uint32 messageLength,
      Pointer<Uint8> privateKey,
      Uint32 privateKeyLength,
      Pointer<Uint8> output,
      Uint32 outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _SignEvmMessageDart =
    int Function(
      int mode,
      Pointer<Uint8> message,
      int messageLength,
      Pointer<Uint8> privateKey,
      int privateKeyLength,
      Pointer<Uint8> output,
      int outputCapacity,
      Pointer<Uint32> outputLength,
    );
typedef _DeriveKeyNative =
    Int32 Function(
      Uint32 coinType,
      Pointer<Uint8> mnemonic,
      Uint32 mnemonicLength,
      Pointer<Uint8> passphrase,
      Uint32 passphraseLength,
      Pointer<Uint8> path,
      Uint32 pathLength,
      Uint32 publicKeyMode,
      Pointer<Uint8> privateKeyOutput,
      Uint32 privateKeyCapacity,
      Pointer<Uint32> privateKeyLength,
      Pointer<Uint8> publicKeyOutput,
      Uint32 publicKeyCapacity,
      Pointer<Uint32> publicKeyLength,
      Pointer<Uint8> addressOutput,
      Uint32 addressCapacity,
      Pointer<Uint32> addressLength,
    );
typedef _DeriveKeyDart =
    int Function(
      int coinType,
      Pointer<Uint8> mnemonic,
      int mnemonicLength,
      Pointer<Uint8> passphrase,
      int passphraseLength,
      Pointer<Uint8> path,
      int pathLength,
      int publicKeyMode,
      Pointer<Uint8> privateKeyOutput,
      int privateKeyCapacity,
      Pointer<Uint32> privateKeyLength,
      Pointer<Uint8> publicKeyOutput,
      int publicKeyCapacity,
      Pointer<Uint32> publicKeyLength,
      Pointer<Uint8> addressOutput,
      int addressCapacity,
      Pointer<Uint32> addressLength,
    );
typedef _InspectKeyNative =
    Int32 Function(
      Uint32 coinType,
      Pointer<Uint8> privateKey,
      Uint32 privateKeyLength,
      Uint32 publicKeyMode,
      Pointer<Uint8> publicKeyOutput,
      Uint32 publicKeyCapacity,
      Pointer<Uint32> publicKeyLength,
      Pointer<Uint8> addressOutput,
      Uint32 addressCapacity,
      Pointer<Uint32> addressLength,
    );
typedef _InspectKeyDart =
    int Function(
      int coinType,
      Pointer<Uint8> privateKey,
      int privateKeyLength,
      int publicKeyMode,
      Pointer<Uint8> publicKeyOutput,
      int publicKeyCapacity,
      Pointer<Uint32> publicKeyLength,
      Pointer<Uint8> addressOutput,
      int addressCapacity,
      Pointer<Uint32> addressLength,
    );

/// FFI loader for the C ABI owned and built by `wallet_engine`.
final class FfiWalletCoreNativeBridge
    implements
        WalletCoreNativeBridge,
        WalletCoreSecp256k1Bridge,
        WalletCoreProtoBridge,
        WalletCoreEvmMessageBridge,
        WalletCoreKeyDerivationBridge {
  FfiWalletCoreNativeBridge._(this._library);

  /// Opens an explicit test/development artifact, or the platform artifact.
  factory FfiWalletCoreNativeBridge.open({String? libraryPath}) {
    if (libraryPath != null && libraryPath.trim().isNotEmpty) {
      return FfiWalletCoreNativeBridge._(DynamicLibrary.open(libraryPath));
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return FfiWalletCoreNativeBridge._(DynamicLibrary.process());
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return FfiWalletCoreNativeBridge._(
        DynamicLibrary.open('libwallet_engine_core.so'),
      );
    }
    throw UnsupportedError(
      'No Wallet Core native artifact is configured for this platform.',
    );
  }

  final DynamicLibrary _library;
  WalletCoreNativeBridgeInfo? _info;

  late final _Uint32Dart _abiVersion = _library
      .lookupFunction<_Uint32Native, _Uint32Dart>(
        'wallet_engine_wallet_core_abi_version',
      );
  late final _BytesDart _upstreamVersion = _library
      .lookupFunction<_BytesNative, _BytesDart>(
        'wallet_engine_wallet_core_upstream_version',
      );
  late final _Uint32Dart _upstreamVersionLength = _library
      .lookupFunction<_Uint32Native, _Uint32Dart>(
        'wallet_engine_wallet_core_upstream_version_length',
      );
  late final _BytesDart _upstreamCommit = _library
      .lookupFunction<_BytesNative, _BytesDart>(
        'wallet_engine_wallet_core_upstream_commit',
      );
  late final _Uint32Dart _upstreamCommitLength = _library
      .lookupFunction<_Uint32Native, _Uint32Dart>(
        'wallet_engine_wallet_core_upstream_commit_length',
      );
  late final _Int32Dart _selfTest = _library
      .lookupFunction<_Int32Native, _Int32Dart>(
        'wallet_engine_wallet_core_self_test',
      );
  late final _SupportsJsonDart _supportsJson = _library
      .lookupFunction<_SupportsJsonNative, _SupportsJsonDart>(
        'wallet_engine_wallet_core_supports_json',
      );
  late final _SignJsonDart _signJson = _library
      .lookupFunction<_SignJsonNative, _SignJsonDart>(
        'wallet_engine_wallet_core_sign_json',
      );
  late final _SignSecp256k1Dart _signSecp256k1 = _library
      .lookupFunction<_SignSecp256k1Native, _SignSecp256k1Dart>(
        'wallet_engine_wallet_core_sign_secp256k1',
      );
  late final _SignProtoDart _signProto = _library
      .lookupFunction<_SignProtoNative, _SignProtoDart>(
        'wallet_engine_wallet_core_sign_proto',
      );
  late final _SignEvmMessageDart _signEvmMessage = _library
      .lookupFunction<_SignEvmMessageNative, _SignEvmMessageDart>(
        'wallet_engine_wallet_core_sign_evm_message',
      );
  late final _DeriveKeyDart _deriveKey = _library
      .lookupFunction<_DeriveKeyNative, _DeriveKeyDart>(
        'wallet_engine_wallet_core_derive_key',
      );
  late final _InspectKeyDart _inspectKey = _library
      .lookupFunction<_InspectKeyNative, _InspectKeyDart>(
        'wallet_engine_wallet_core_inspect_key',
      );

  @override
  Future<WalletCoreNativeBridgeInfo> load() async {
    _validateRequiredSymbols();
    return _info ??= WalletCoreNativeBridgeInfo(
      abiVersion: _abiVersion(),
      upstreamVersion: _readString(
        _upstreamVersion(),
        _upstreamVersionLength(),
      ),
      upstreamCommit: _readString(_upstreamCommit(), _upstreamCommitLength()),
    );
  }

  void _validateRequiredSymbols() {
    // Evaluating every late lookup makes an incomplete or older artifact fail
    // during application startup instead of on the first affected operation.
    <Object>[
      _supportsJson,
      _signJson,
      _signSecp256k1,
      _signProto,
      _signEvmMessage,
      _deriveKey,
      _inspectKey,
    ];
  }

  @override
  Future<void> selfTest() async {
    final result = _selfTest();
    if (result != 0) {
      throw StateError('Native self-test returned status $result.');
    }
  }

  @override
  bool supportsJsonSigning(int coinType) => _supportsJson(coinType) == 1;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    if (privateKey.length != 32) {
      throw ArgumentError.value(privateKey.length, 'privateKey.length');
    }
    final jsonBytes = utf8.encode(json);
    final jsonPointer = calloc<Uint8>(jsonBytes.length);
    final keyPointer = calloc<Uint8>(privateKey.length);
    final outputLength = calloc<Uint32>();
    try {
      jsonPointer.asTypedList(jsonBytes.length).setAll(0, jsonBytes);
      keyPointer.asTypedList(privateKey.length).setAll(0, privateKey);

      final probeStatus = _signJson(
        coinType,
        jsonPointer,
        jsonBytes.length,
        keyPointer,
        privateKey.length,
        nullptr,
        0,
        outputLength,
      );
      if (probeStatus != 3 || outputLength.value == 0) {
        throw StateError('Native JSON signer failed with status $probeStatus.');
      }

      final output = calloc<Uint8>(outputLength.value);
      try {
        final status = _signJson(
          coinType,
          jsonPointer,
          jsonBytes.length,
          keyPointer,
          privateKey.length,
          output,
          outputLength.value,
          outputLength,
        );
        if (status != 0) {
          throw StateError('Native JSON signer failed with status $status.');
        }
        return Uint8List.fromList(output.asTypedList(outputLength.value));
      } finally {
        calloc.free(output);
      }
    } finally {
      keyPointer
          .asTypedList(privateKey.length)
          .fillRange(0, privateKey.length, 0);
      calloc.free(outputLength);
      calloc.free(keyPointer);
      calloc.free(jsonPointer);
    }
  }

  @override
  Uint8List signSecp256k1({
    required Uint8List privateKey,
    required Uint8List digest,
  }) {
    if (privateKey.length != 32 || digest.length != 32) {
      throw ArgumentError('Private key and digest must contain 32 bytes.');
    }
    final keyPointer = calloc<Uint8>(32);
    final digestPointer = calloc<Uint8>(32);
    final output = calloc<Uint8>(65);
    final outputLength = calloc<Uint32>();
    try {
      keyPointer.asTypedList(32).setAll(0, privateKey);
      digestPointer.asTypedList(32).setAll(0, digest);
      final status = _signSecp256k1(
        keyPointer,
        32,
        digestPointer,
        32,
        output,
        65,
        outputLength,
      );
      if (status != 0 || outputLength.value != 65) {
        throw StateError('Native secp256k1 signer failed with status $status.');
      }
      return Uint8List.fromList(output.asTypedList(outputLength.value));
    } finally {
      keyPointer.asTypedList(32).fillRange(0, 32, 0);
      output.asTypedList(65).fillRange(0, 65, 0);
      calloc.free(outputLength);
      calloc.free(output);
      calloc.free(digestPointer);
      calloc.free(keyPointer);
    }
  }

  @override
  Uint8List signProto({required int coinType, required Uint8List input}) {
    if (input.isEmpty) throw ArgumentError.value(input.length, 'input.length');
    final inputPointer = calloc<Uint8>(input.length);
    final outputLength = calloc<Uint32>();
    try {
      inputPointer.asTypedList(input.length).setAll(0, input);
      final probe = _signProto(
        coinType,
        inputPointer,
        input.length,
        nullptr,
        0,
        outputLength,
      );
      if (probe != 3 || outputLength.value == 0) {
        throw StateError('Native protobuf signer failed with status $probe.');
      }
      final output = calloc<Uint8>(outputLength.value);
      try {
        final status = _signProto(
          coinType,
          inputPointer,
          input.length,
          output,
          outputLength.value,
          outputLength,
        );
        if (status != 0) {
          throw StateError(
            'Native protobuf signer failed with status $status.',
          );
        }
        return Uint8List.fromList(output.asTypedList(outputLength.value));
      } finally {
        output
            .asTypedList(outputLength.value)
            .fillRange(0, outputLength.value, 0);
        calloc.free(output);
      }
    } finally {
      inputPointer.asTypedList(input.length).fillRange(0, input.length, 0);
      calloc.free(outputLength);
      calloc.free(inputPointer);
    }
  }

  @override
  String signEvmMessage({
    required WalletCoreEvmMessageMode mode,
    required String message,
    required Uint8List privateKey,
  }) {
    if (message.isEmpty || privateKey.length != 32) {
      throw ArgumentError(
        'Message must be non-empty and key must be 32 bytes.',
      );
    }
    final messageBytes = utf8.encode(message);
    final messagePointer = calloc<Uint8>(messageBytes.length);
    final keyPointer = calloc<Uint8>(32);
    final output = calloc<Uint8>(256);
    final outputLength = calloc<Uint32>();
    try {
      messagePointer.asTypedList(messageBytes.length).setAll(0, messageBytes);
      keyPointer.asTypedList(32).setAll(0, privateKey);
      final status = _signEvmMessage(
        mode.index,
        messagePointer,
        messageBytes.length,
        keyPointer,
        32,
        output,
        256,
        outputLength,
      );
      if (status != 0 || outputLength.value == 0 || outputLength.value > 256) {
        throw StateError(
          'Native EVM message signer failed with status $status.',
        );
      }
      return utf8.decode(output.asTypedList(outputLength.value));
    } finally {
      keyPointer.asTypedList(32).fillRange(0, 32, 0);
      output.asTypedList(256).fillRange(0, 256, 0);
      calloc.free(outputLength);
      calloc.free(output);
      calloc.free(keyPointer);
      calloc.free(messagePointer);
    }
  }

  @override
  WalletCoreKeyInfo deriveKey({
    required int coinType,
    required String mnemonic,
    required String passphrase,
    required String derivationPath,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    final mnemonicBytes = utf8.encode(mnemonic);
    final passphraseBytes = utf8.encode(passphrase);
    final pathBytes = utf8.encode(derivationPath);
    final mnemonicPointer = _copyBytes(mnemonicBytes);
    final passphrasePointer = _copyBytes(passphraseBytes);
    final pathPointer = _copyBytes(pathBytes);
    final privateOutput = calloc<Uint8>(128);
    final publicOutput = calloc<Uint8>(128);
    final addressOutput = calloc<Uint8>(512);
    final privateLength = calloc<Uint32>();
    final publicLength = calloc<Uint32>();
    final addressLength = calloc<Uint32>();
    try {
      final status = _deriveKey(
        coinType,
        mnemonicPointer,
        mnemonicBytes.length,
        passphrasePointer,
        passphraseBytes.length,
        pathPointer,
        pathBytes.length,
        publicKeyMode.index,
        privateOutput,
        128,
        privateLength,
        publicOutput,
        128,
        publicLength,
        addressOutput,
        512,
        addressLength,
      );
      _validateKeyInfoStatus(
        status,
        privateLength.value,
        publicLength.value,
        addressLength.value,
      );
      return WalletCoreKeyInfo(
        privateKey: Uint8List.fromList(
          privateOutput.asTypedList(privateLength.value),
        ),
        publicKey: Uint8List.fromList(
          publicOutput.asTypedList(publicLength.value),
        ),
        address: utf8.decode(addressOutput.asTypedList(addressLength.value)),
      );
    } finally {
      mnemonicPointer
          .asTypedList(mnemonicBytes.isEmpty ? 1 : mnemonicBytes.length)
          .fillRange(0, mnemonicBytes.isEmpty ? 1 : mnemonicBytes.length, 0);
      passphrasePointer
          .asTypedList(passphraseBytes.isEmpty ? 1 : passphraseBytes.length)
          .fillRange(
            0,
            passphraseBytes.isEmpty ? 1 : passphraseBytes.length,
            0,
          );
      privateOutput.asTypedList(128).fillRange(0, 128, 0);
      publicOutput.asTypedList(128).fillRange(0, 128, 0);
      calloc.free(addressLength);
      calloc.free(publicLength);
      calloc.free(privateLength);
      calloc.free(addressOutput);
      calloc.free(publicOutput);
      calloc.free(privateOutput);
      calloc.free(pathPointer);
      calloc.free(passphrasePointer);
      calloc.free(mnemonicPointer);
    }
  }

  @override
  WalletCoreKeyInfo inspectKey({
    required int coinType,
    required Uint8List privateKey,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    final keyPointer = _copyBytes(privateKey);
    final publicOutput = calloc<Uint8>(128);
    final addressOutput = calloc<Uint8>(512);
    final publicLength = calloc<Uint32>();
    final addressLength = calloc<Uint32>();
    try {
      final status = _inspectKey(
        coinType,
        keyPointer,
        privateKey.length,
        publicKeyMode.index,
        publicOutput,
        128,
        publicLength,
        addressOutput,
        512,
        addressLength,
      );
      _validateKeyInfoStatus(
        status,
        privateKey.length,
        publicLength.value,
        addressLength.value,
      );
      return WalletCoreKeyInfo(
        privateKey: Uint8List.fromList(privateKey),
        publicKey: Uint8List.fromList(
          publicOutput.asTypedList(publicLength.value),
        ),
        address: utf8.decode(addressOutput.asTypedList(addressLength.value)),
      );
    } finally {
      keyPointer
          .asTypedList(privateKey.isEmpty ? 1 : privateKey.length)
          .fillRange(0, privateKey.isEmpty ? 1 : privateKey.length, 0);
      publicOutput.asTypedList(128).fillRange(0, 128, 0);
      calloc.free(addressLength);
      calloc.free(publicLength);
      calloc.free(addressOutput);
      calloc.free(publicOutput);
      calloc.free(keyPointer);
    }
  }

  static Pointer<Uint8> _copyBytes(List<int> bytes) {
    final pointer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static void _validateKeyInfoStatus(
    int status,
    int privateLength,
    int publicLength,
    int addressLength,
  ) {
    if (status != 0 ||
        privateLength <= 0 ||
        privateLength > 128 ||
        publicLength <= 0 ||
        publicLength > 128 ||
        addressLength <= 0 ||
        addressLength > 512) {
      throw StateError('Native key derivation failed with status $status.');
    }
  }

  static String _readString(Pointer<Uint8> pointer, int length) {
    if (pointer == nullptr || length <= 0 || length > 256) {
      throw StateError('Native bridge returned invalid metadata.');
    }
    return utf8.decode(pointer.asTypedList(length), allowMalformed: false);
  }
}
