import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart' as on_chain;
import 'package:wallet_engine/src/codec/wallet_codec.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  test(
    'hashes raw_data and serializes the native recoverable signature',
    () async {
      final bridge = _TronBridge();
      final runtime = WalletCoreNativeRuntime(bridge: bridge);
      await runtime.initialize();
      final signer = WalletCoreTronSigner(
        privateKeyAccess: _KeyAccess(
          Uint8List.fromList(List<int>.filled(32, 1)),
        ),
        runtime: runtime,
      );
      final raw = _rawTransaction();

      final result = await signer.sign(
        TronUnsignedTransaction(
          rawData: Uint8List.fromList(raw.toBuffer()),
          txId: raw.txID,
        ),
      );

      final decoded = on_chain.Transaction.deserialize(
        WalletCodec.hexToBytes(result.encodedTransaction),
      );
      expect(result.txId, raw.txID);
      expect(decoded.rawData.toBuffer(), raw.toBuffer());
      expect(
        decoded.signature.single,
        List<int>.generate(65, (index) => index),
      );
      expect(bridge.digest, hasLength(32));
    },
  );
}

on_chain.TransactionRaw _rawTransaction() {
  const address = 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb';
  final transfer = on_chain.TransferContract(
    amount: BigInt.one,
    ownerAddress: on_chain.TronAddress(address),
    toAddress: on_chain.TronAddress(address),
  );
  return on_chain.TransactionRaw(
    refBlockBytes: const <int>[0, 0],
    refBlockHash: List<int>.filled(8, 0),
    expiration: BigInt.from(100),
    timestamp: BigInt.from(200),
    contract: <on_chain.TransactionContract>[
      on_chain.TransactionContract(
        type: on_chain.TransactionContractType.transferContract,
        parameter: on_chain.Any(
          typeUrl: 'type.googleapis.com/protocol.TransferContract',
          value: transfer,
        ),
      ),
    ],
  );
}

final class _TronBridge
    implements WalletCoreNativeBridge, WalletCoreSecp256k1Bridge {
  Uint8List? digest;

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
  Uint8List signSecp256k1({
    required Uint8List privateKey,
    required Uint8List digest,
  }) {
    expect(privateKey, hasLength(32));
    this.digest = Uint8List.fromList(digest);
    return Uint8List.fromList(List<int>.generate(65, (index) => index));
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
