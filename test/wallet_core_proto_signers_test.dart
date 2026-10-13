import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/src/native_bridge/wallet_core_proto_codec.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('owned protobuf signing bridge', () {
    test('encodes and decodes unsigned 64-bit boundary values', () {
      final writer = WalletCoreProtoWriter()
        ..uint64(1, (BigInt.one << 64) - BigInt.one);
      final bytes = writer.takeBytes();
      final fields = WalletCoreProtoReader(bytes).readFields().toList();

      expect(fields, hasLength(1));
      expect(fields.single.number, 1);
      expect(fields.single.varint, (BigInt.one << 64) - BigInt.one);
      expect(
        () => WalletCoreProtoWriter()..uint64(1, BigInt.one << 64),
        throwsArgumentError,
      );
    });

    test('rejects malformed protobuf input', () {
      expect(
        () => WalletCoreProtoReader(
          Uint8List.fromList(<int>[0x0a, 0x02, 0x01]),
        ).readFields().toList(),
        throwsFormatException,
      );
    });
  });

  test('Sui signer uses the pinned protobuf schema', () async {
    final bridge = _ProtoBridge();
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreSuiSigner(
      privateKeyAccess: _KeyAccess(Uint8List.fromList(List<int>.filled(32, 7))),
      runtime: runtime,
    );

    final signed = await signer.sign(
      const SuiRawJsonTransaction(rawJson: '{"tx":"AA=="}'),
    );

    expect(signed.txBytes, 'dW5zaWduZWQ=');
    expect(signed.signature, 'c2lnbmF0dXJl');
    expect(bridge.lastCoinType, 784);
    final fields = WalletCoreProtoReader(
      bridge.lastInput!,
    ).readFields().toList();
    expect(
      fields.singleWhere((field) => field.number == 1).bytes,
      hasLength(32),
    );
    expect(
      fields.singleWhere((field) => field.number == 10).string,
      '{"tx":"AA=="}',
    );
  });

  test('Bitcoin signer uses legacy Wallet Core signing fields', () async {
    final bridge = _ProtoBridge();
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreBitcoinSigner(
      privateKeyAccess: _KeyAccess(
        Uint8List.fromList(<int>[...List<int>.filled(31, 0), 1]),
      ),
      runtime: runtime,
    );

    final signed = await signer.sign(
      BitcoinUnsignedTransaction(
        utxos: <BitcoinUtxo>[
          BitcoinUtxo(
            txHash: '00' * 32,
            vout: 1,
            amount: Decimal.parse('0.01'),
            script: '0014${'00' * 20}',
          ),
        ],
        toAddress: 'bc1qtest',
        changeAddress: 'bc1qchange',
        amount: Decimal.parse('0.001'),
        feeRateSatPerVbyte: Decimal.parse('1.1'),
      ),
    );

    expect(signed.hex, '010203');
    expect(bridge.lastCoinType, 0);
    final fields = WalletCoreProtoReader(
      bridge.lastInput!,
    ).readFields().toList();
    expect(fields.singleWhere((field) => field.number == 1).varint, BigInt.one);
    expect(
      fields.singleWhere((field) => field.number == 2).varint,
      BigInt.from(100000),
    );
    expect(
      fields.singleWhere((field) => field.number == 3).varint,
      BigInt.from(2),
    );
    expect(fields.where((field) => field.number == 6), hasLength(1));
    expect(fields.where((field) => field.number == 8), hasLength(1));
  });

  test('EVM message signer uses owned message bridge and strips 0x', () async {
    final bridge = _ProtoBridge();
    final runtime = WalletCoreNativeRuntime(bridge: bridge);
    await runtime.initialize();
    final signer = WalletCoreEvmMessageSigner(
      privateKeyAccess: _KeyAccess(Uint8List(32)),
      runtime: runtime,
    );

    final signature = await signer.sign(
      type: EvmMessageType.typedData,
      message: '{"types":{}}',
    );

    expect(signature, 'abcd');
    expect(bridge.lastMessageMode, WalletCoreEvmMessageMode.typedData);
    expect(bridge.lastMessage, '{"types":{}}');
    expect(bridge.lastMessageKey, everyElement(0));
  });
}

final class _ProtoBridge
    implements
        WalletCoreNativeBridge,
        WalletCoreProtoBridge,
        WalletCoreEvmMessageBridge {
  int? lastCoinType;
  Uint8List? lastInput;
  WalletCoreEvmMessageMode? lastMessageMode;
  String? lastMessage;
  Uint8List? lastMessageKey;

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
  bool supportsJsonSigning(int coinType) => false;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) => throw UnsupportedError('not used');

  @override
  Uint8List signProto({required int coinType, required Uint8List input}) {
    lastCoinType = coinType;
    lastInput = Uint8List.fromList(input);
    final output = WalletCoreProtoWriter();
    if (coinType == 784) {
      output
        ..string(1, 'dW5zaWduZWQ=')
        ..string(2, 'c2lnbmF0dXJl');
    } else if (coinType == 0) {
      output.bytes(2, <int>[1, 2, 3]);
    }
    return output.takeBytes();
  }

  @override
  String signEvmMessage({
    required WalletCoreEvmMessageMode mode,
    required String message,
    required Uint8List privateKey,
  }) {
    lastMessageMode = mode;
    lastMessage = message;
    lastMessageKey = privateKey;
    return '0xabcd';
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
