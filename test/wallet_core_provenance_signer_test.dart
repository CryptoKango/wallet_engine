import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  test('maps and parses the upstream Cosmos JSON golden vector', () async {
    final bridge = _CosmosVectorBridge();
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreProvenanceSigner(
      privateKeyAccess: _KeyAccess(
        'c9b0a273831931aa4a5f8d1a570d5021dda91d3319bd3819becdaabfb7b44e3b',
      ),
      runtime: runtime,
    );

    final signed = await signer.sign(
      ProvenanceTransferTransaction(
        chainId: 'cosmoshub-2',
        accountNumber: BigInt.from(8733),
        sequence: BigInt.zero,
        fromAddress: 'cosmos1ufwv9ymhqaal6xz47n0jhzm2wf4empfqvjy575',
        toAddress: 'cosmos135qla4294zxarqhhgxsx0sw56yssa3z0f78pm0',
        denom: 'uatom',
        amount: Decimal.fromInt(995000),
        decimals: 0,
        feeDenom: 'uatom',
        feeAmount: Decimal.fromInt(5000),
        feeDecimals: 0,
        gas: BigInt.from(200000),
        memo: 'Testing',
      ),
    );

    expect(
      signed.base64Signature,
      'ULEpUqNzoAnYEx2x22F3ANAiPXquAU9+mqLWoAA/ZOUGTMsdb6vryzsW6AKX2Kqj'
      '1pGNdrTcQ58Z09JPyjpgEA==',
    );
    expect(bridge.lastInput?['accountNumber'], '8733');
    expect(bridge.lastInput?['signingMode'], 'JSON');
    expect(bridge.lastInput?['sequence'], '0');
  });
}

final class _CosmosVectorBridge implements WalletCoreNativeBridge {
  Map<String, Object?>? lastInput;

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
  bool supportsJsonSigning(int coinType) => coinType == 118;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) {
    expect(coinType, 118);
    expect(privateKey, hasLength(32));
    lastInput = (jsonDecode(json) as Map<Object?, Object?>)
        .cast<String, Object?>();
    return Uint8List.fromList(
      utf8.encode(
        '{"mode":"block","tx":{"signatures":[{"signature":'
        '"ULEpUqNzoAnYEx2x22F3ANAiPXquAU9+mqLWoAA/ZOUGTMsdb6vryzsW6AKX2Kqj'
        '1pGNdrTcQ58Z09JPyjpgEA=="}]}}',
      ),
    );
  }
}

final class _KeyAccess implements PrivateKeyAccess {
  _KeyAccess(String hex)
    : _key = Uint8List.fromList(<int>[
        for (var index = 0; index < hex.length; index += 2)
          int.parse(hex.substring(index, index + 2), radix: 16),
      ]);

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
