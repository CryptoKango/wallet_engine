import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  test('maps SOL transfer to protobuf JSON with uint64 strings', () async {
    final bridge = _SolanaBridge();
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreSolanaSigner(
      privateKeyAccess: _KeyAccess(Uint8List(64)),
      runtime: runtime,
    );

    final signed = await signer.sign(
      SolanaTransferTransaction(
        recentBlockhash: '11111111111111111111111111111111',
        recipient: 'So11111111111111111111111111111111111111112',
        amount: Decimal.parse('1.25'),
        priorityFeeLimit: 200000,
        priorityFeePrice: BigInt.from(1000),
      ),
    );

    expect(signed.base64Transaction, 'AQID');
    expect(bridge.lastInput, <String, Object?>{
      'recentBlockhash': '11111111111111111111111111111111',
      'txEncoding': 'Base64',
      'priorityFeeLimit': <String, Object?>{'limit': 200000},
      'priorityFeePrice': <String, Object?>{'price': '1000'},
      'transferTransaction': <String, Object?>{
        'recipient': 'So11111111111111111111111111111111111111112',
        'value': '1250000000',
      },
    });
    expect(bridge.lastPrivateKey, everyElement(0));
  });
}

final class _SolanaBridge implements WalletCoreNativeBridge {
  Map<String, Object?>? lastInput;
  Uint8List? lastPrivateKey;

  @override
  Future<WalletCoreNativeBridgeInfo> load() async =>
      const WalletCoreNativeBridgeInfo(
        abiVersion: 2,
        upstreamVersion: '4.8.4',
        upstreamCommit: 'd40d24a63d92619167903369308bf0e2f7eb3a59',
      );

  @override
  Future<void> selfTest() async {}

  @override
  bool supportsJsonSigning(int coinType) => coinType == 501;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    expect(coinType, 501);
    lastInput = (jsonDecode(json) as Map<Object?, Object?>)
        .cast<String, Object?>();
    lastPrivateKey = privateKey;
    return Uint8List.fromList(utf8.encode('AQID'));
  }
}

final class _KeyAccess implements PrivateKeyAccess {
  _KeyAccess(this._key);

  final Uint8List _key;

  @override
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation) {
    final copy = Uint8List.fromList(_key);
    try {
      return operation(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }
}
