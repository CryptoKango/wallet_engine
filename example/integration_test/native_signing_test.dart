import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:on_chain/on_chain.dart' as on_chain;
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtime = WalletCoreNativeRuntime(
    bridge: FfiWalletCoreNativeBridge.open(),
  );
  final key = _EphemeralPrivateKey(
    List<int>.generate(32, (index) => index + 1),
  );

  setUpAll(runtime.initialize);

  testWidgets('loads the native runtime and signs deterministic EVM payloads', (
    tester,
  ) async {
    await runtime.initialize();
    expect(runtime.isInitialized, isTrue);

    final transactionSigner = WalletCoreEvmSigner(
      privateKeyAccess: key,
      runtime: runtime,
    );
    final transaction = EvmUnsignedTransaction.legacy(
      chainId: BigInt.one,
      nonce: BigInt.zero,
      gasLimit: BigInt.from(21000),
      to: '0x000000000000000000000000000000000000dEaD',
      gasPrice: BigInt.from(1000000000),
      valueBaseUnits: BigInt.one,
    );
    final firstTransaction = await transactionSigner.sign(transaction);
    final secondTransaction = await transactionSigner.sign(transaction);

    expect(firstTransaction.rawTransaction, startsWith('0x'));
    expect(firstTransaction.rawTransaction.length, greaterThan(100));
    expect(secondTransaction.rawTransaction, firstTransaction.rawTransaction);

    final messageSigner = WalletCoreEvmMessageSigner(
      privateKeyAccess: key,
      runtime: runtime,
    );
    final firstMessage = await messageSigner.sign(
      type: EvmMessageType.personal,
      message: 'wallet_engine native signing test',
    );
    final secondMessage = await messageSigner.sign(
      type: EvmMessageType.personal,
      message: 'wallet_engine native signing test',
    );

    expect(firstMessage, hasLength(130));
    expect(secondMessage, firstMessage);
    expect(key.activeCopies, 0);
  });

  testWidgets('signs Solana, Sui, TRON, and Bitcoin transactions', (
    tester,
  ) async {
    final solana = WalletCoreSolanaSigner(
      privateKeyAccess: key,
      runtime: runtime,
    );
    final solanaTransaction = SolanaTransferTransaction(
      recentBlockhash: '11111111111111111111111111111111',
      recipient: '11111111111111111111111111111111',
      amount: Decimal.parse('0.000000001'),
    );
    final signedSolana = await solana.sign(solanaTransaction);
    expect(signedSolana.base64Transaction, isNotEmpty);

    final sui = WalletCoreSuiSigner(privateKeyAccess: key, runtime: runtime);
    final signedSui = await sui.sign(
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
    expect(signedSui.txBytes, isNotEmpty);
    expect(signedSui.signature, isNotEmpty);

    final tron = WalletCoreTronSigner(privateKeyAccess: key, runtime: runtime);
    final tronRaw = _tronRawTransaction();
    final signedTron = await tron.sign(
      TronUnsignedTransaction(
        rawData: Uint8List.fromList(tronRaw.toBuffer()),
        txId: tronRaw.txID,
      ),
    );
    expect(signedTron.encodedTransaction, isNotEmpty);
    expect(signedTron.txId, tronRaw.txID);

    final bitcoin = WalletCoreBitcoinSigner(
      privateKeyAccess: key,
      runtime: runtime,
    );
    final bitcoinAddress = await bitcoin.segwitAddress(network: 'testnet');
    final bitcoinSession = _bitcoinSession();
    final signedBitcoin = await bitcoin.sign(
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
    expect(signedBitcoin.hex, isNotEmpty);
    await bitcoinSession.close();
    expect(key.activeCopies, 0);
  });
}

on_chain.TransactionRaw _tronRawTransaction() {
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

BitcoinChainSession _bitcoinSession() {
  final engine = WalletEngine(
    config: WalletEngineConfig(
      revision: 1,
      version: 'native-test',
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
    throw StateError('Electrum is not used by the native signing test.');
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
    throw StateError('RPC is not used by the native signing test.');
  }
}

final class _EphemeralPrivateKey implements PrivateKeyAccess {
  _EphemeralPrivateKey(List<int> bytes)
    : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  int activeCopies = 0;

  @override
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation) {
    final copy = Uint8List.fromList(_bytes);
    activeCopies++;
    try {
      return operation(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
      activeCopies--;
    }
  }
}
