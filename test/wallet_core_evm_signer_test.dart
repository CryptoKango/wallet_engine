import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  const info = WalletCoreNativeBridgeInfo(
    abiVersion: 2,
    upstreamVersion: '4.8.4',
    upstreamCommit: 'd40d24a63d92619167903369308bf0e2f7eb3a59',
  );

  test(
    'maps the upstream EVM JSON golden vector without key leakage',
    () async {
      final bridge = _EvmVectorBridge(info);
      final runtime = WalletCoreNativeRuntime(bridge: bridge);
      await runtime.initialize();
      final signer = WalletCoreEvmSigner(
        privateKeyAccess: _TestKeyAccess(
          '17209af590a86462395d5881e60d11c7fa7d482cfb02b5a01b93c2eeef243543',
        ),
        runtime: runtime,
      );

      final signed = await signer.sign(
        EvmUnsignedTransaction.legacy(
          chainId: BigInt.one,
          nonce: BigInt.zero,
          gasLimit: BigInt.from(21000),
          to: '0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1',
          gasPrice: BigInt.from(3600000000),
          valueBaseUnits: BigInt.parse('0348bca5a16000', radix: 16),
        ),
      );

      expect(
        signed.rawTransaction,
        '0xf86a8084d693a400825208947d8bf18c7ce84b3e175b339c4ca93aed1dd166f1'
        '870348bca5a160008025a0fe5802b49e04c6b1705088310e133605ed8b549811a'
        '18968ad409ea02ad79f21a05bf845646fb1e1b9365f63a7fd5eb5e984094e3ed'
        '35c3bed7361aebbcbf41f10',
      );
      expect(bridge.lastJson, <String, Object?>{
        'chainId': 'AQ==',
        'nonce': 'AA==',
        'txMode': 'Legacy',
        'gasPrice': '1pOkAA==',
        'gasLimit': 'Ugg=',
        'toAddress': '0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1',
        'transaction': <String, Object?>{
          'contractGeneric': <String, Object?>{'amount': 'A0i8paFgAA=='},
        },
      });
    },
  );

  test('rejects a key with the wrong length before native signing', () async {
    final bridge = _EvmVectorBridge(info);
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreEvmSigner(
      privateKeyAccess: _BytesKeyAccess(Uint8List(31)),
      runtime: runtime,
    );

    await expectLater(
      signer.sign(
        EvmUnsignedTransaction.legacy(
          chainId: BigInt.one,
          nonce: BigInt.zero,
          gasLimit: BigInt.from(21000),
          to: '0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1',
          gasPrice: BigInt.one,
        ),
      ),
      throwsA(
        isA<WalletSigningException>().having(
          (error) => error.code,
          'code',
          WalletSigningErrorCode.invalidPrivateKey,
        ),
      ),
    );
    expect(bridge.signCount, 0);
  });
}

final class _EvmVectorBridge implements WalletCoreNativeBridge {
  _EvmVectorBridge(this.info);

  final WalletCoreNativeBridgeInfo info;
  Map<String, Object?>? lastJson;
  int signCount = 0;

  @override
  Future<WalletCoreNativeBridgeInfo> load() async => info;

  @override
  Future<void> selfTest() async {}

  @override
  bool supportsJsonSigning(int coinType) => coinType == 60;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    signCount += 1;
    expect(coinType, 60);
    expect(privateKey, hasLength(32));
    lastJson = (jsonDecode(json) as Map<Object?, Object?>)
        .cast<String, Object?>();
    return Uint8List.fromList(
      ascii.encode(
        'f86a8084d693a400825208947d8bf18c7ce84b3e175b339c4ca93aed1dd166f1'
        '870348bca5a160008025a0fe5802b49e04c6b1705088310e133605ed8b549811a'
        '18968ad409ea02ad79f21a05bf845646fb1e1b9365f63a7fd5eb5e984094e3ed'
        '35c3bed7361aebbcbf41f10',
      ),
    );
  }
}

final class _TestKeyAccess implements PrivateKeyAccess {
  _TestKeyAccess(String hex) : _bytes = _decodeHex(hex);

  final Uint8List _bytes;

  @override
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation) {
    final copy = Uint8List.fromList(_bytes);
    try {
      return operation(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  static Uint8List _decodeHex(String value) => Uint8List.fromList(<int>[
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
}

final class _BytesKeyAccess implements PrivateKeyAccess {
  _BytesKeyAccess(this._bytes);

  final Uint8List _bytes;

  @override
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation) =>
      operation(Uint8List.fromList(_bytes));
}
