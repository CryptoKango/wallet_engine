import 'dart:io';
import 'dart:typed_data';

import 'package:wallet_engine/wallet_engine.dart';

const _mnemonic = 'test test test test test test test test test test test junk';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'usage: dart run tool/native_bridge_smoke.dart [native-library]',
    );
    exitCode = 64;
    return;
  }
  final runtime = WalletCoreNativeRuntime(
    bridge: FfiWalletCoreNativeBridge.open(
      libraryPath: arguments.isEmpty ? null : arguments.single,
    ),
  );
  final info = await runtime.initialize();
  final derived = runtime.deriveKey(
    coinType: 60,
    mnemonic: _mnemonic,
    passphrase: '',
    derivationPath: "m/44'/60'/0'/0/0",
    publicKeyMode: WalletCorePublicKeyMode.secp256k1Compressed,
  );
  try {
    if (derived.address.toLowerCase() !=
        '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266') {
      throw StateError('Unexpected deterministic EVM address.');
    }
    final inspected = runtime.inspectKey(
      coinType: 60,
      privateKey: derived.privateKey,
      publicKeyMode: WalletCorePublicKeyMode.secp256k1Compressed,
    );
    try {
      if (inspected.address.toLowerCase() != derived.address.toLowerCase()) {
        throw StateError('Key inspection address mismatch.');
      }
    } finally {
      inspected.privateKey.fillRange(0, inspected.privateKey.length, 0);
    }

    final access = _KeyAccess(derived.privateKey);
    final signed =
        await WalletCoreEvmSigner(
          privateKeyAccess: access,
          runtime: runtime,
        ).sign(
          EvmUnsignedTransaction.legacy(
            chainId: BigInt.one,
            nonce: BigInt.zero,
            gasLimit: BigInt.from(21000),
            to: '0x000000000000000000000000000000000000dEaD',
            gasPrice: BigInt.from(1000000000),
            valueBaseUnits: BigInt.one,
          ),
        );
    if (!signed.rawTransaction.startsWith('0x')) {
      throw StateError('EVM transaction signing failed.');
    }
    final signature = await WalletCoreEvmMessageSigner(
      privateKeyAccess: access,
      runtime: runtime,
    ).sign(type: EvmMessageType.personal, message: 'wallet_engine smoke');
    if (signature.length != 130) {
      throw StateError('EVM message signing failed.');
    }
    final digestSignature = runtime.signSecp256k1(
      privateKey: derived.privateKey,
      digest: Uint8List.fromList(List<int>.filled(32, 1)),
    );
    if (digestSignature.length != 65) {
      throw StateError('Digest signing failed.');
    }
    final protoOutput = runtime.signProto(
      coinType: 0,
      input: Uint8List.fromList(<int>[0x08, 0x01]),
    );
    if (protoOutput.isEmpty) {
      throw StateError('Protobuf signing dispatch failed.');
    }

    final sui =
        await WalletCoreSuiSigner(
          privateKeyAccess: access,
          runtime: runtime,
        ).sign(
          SuiPaySuiTransaction(
            inputCoins: <SuiObjectRef>[
              SuiObjectRef(
                objectId: '0x${'1'.padLeft(64, '0')}',
                version: BigInt.one,
                digest: '11111111111111111111111111111111',
              ),
            ],
            recipients: <String>['0x${'2'.padLeft(64, '0')}'],
            amounts: <Decimal>[Decimal.parse('0.000000001')],
            decimals: 9,
            gasBudget: BigInt.from(1000000),
            referenceGasPrice: BigInt.one,
          ),
        );
    if (sui.txBytes.isEmpty || sui.signature.isEmpty) {
      throw StateError('Sui protobuf signing failed.');
    }

    final bitcoinSigner = WalletCoreBitcoinSigner(
      privateKeyAccess: access,
      runtime: runtime,
    );
    final bitcoinAddress = await bitcoinSigner.segwitAddress(
      network: 'testnet',
    );
    final bitcoinSession = _bitcoinSession();
    try {
      final bitcoin = await bitcoinSigner.sign(
        BitcoinUnsignedTransaction(
          utxos: <BitcoinUtxo>[
            BitcoinUtxo(
              txHash: '00' * 32,
              vout: 0,
              amount: Decimal.parse('0.01'),
              script: bitcoinSession.scriptFromSegwitAddress(bitcoinAddress),
            ),
          ],
          toAddress: bitcoinAddress,
          changeAddress: bitcoinAddress,
          amount: Decimal.parse('0.001'),
          feeRateSatPerVbyte: Decimal.fromInt(2),
        ),
      );
      if (bitcoin.hex.isEmpty) {
        throw StateError('Bitcoin protobuf signing failed.');
      }
    } finally {
      await bitcoinSession.close();
    }
  } finally {
    derived.privateKey.fillRange(0, derived.privateKey.length, 0);
  }

  stdout.writeln(
    'Native bridge smoke passed: ABI ${info.abiVersion}, '
    'Wallet Core ${info.upstreamVersion}.',
  );
}

BitcoinChainSession _bitcoinSession() {
  final engine = WalletEngine(
    config: WalletEngineConfig(
      revision: 1,
      version: 'native-smoke',
      chains: <WalletChainConfig>[
        WalletChainConfig(
          key: 'bitcoin',
          family: ChainFamily.bitcoin,
          network: 'testnet',
          nativeSymbol: 'BTC',
          nativeDecimals: 8,
          rpcPool: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('tls://electrum.example.com:50002'),
            ],
          ),
        ),
      ],
    ),
    adapters: <ChainAdapter>[
      BitcoinChainAdapter(transportFactory: _NoopElectrumTransport.new),
    ],
    transport: const _NoopRpcTransport(),
  );
  return engine.sessionAs<BitcoinChainSession>('bitcoin');
}

final class _NoopElectrumTransport implements ElectrumTransport {
  @override
  Future<void> close() async {}

  @override
  Future<Object?> request({
    required RpcEndpoint endpoint,
    required String method,
    required List<Object?> params,
    required Duration timeout,
  }) {
    throw StateError('Electrum is not used by the native smoke test.');
  }
}

final class _NoopRpcTransport implements RpcTransport {
  const _NoopRpcTransport();

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) {
    throw StateError('RPC is not used by the native smoke test.');
  }
}

final class _KeyAccess implements PrivateKeyAccess {
  const _KeyAccess(this.key);

  final Uint8List key;

  @override
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation) {
    final copy = Uint8List.fromList(key);
    try {
      return operation(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }
}
