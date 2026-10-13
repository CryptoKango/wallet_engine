import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('SolanaChainSession', () {
    test('queries balances, blockhash, priority fee, and receipt', () async {
      final transport = _RoutingRpcTransport((operation, body) {
        return switch (operation) {
          'getBalance' => <String, Object?>{'value': 42},
          'getLatestBlockhash' => <String, Object?>{
            'value': <String, Object?>{'blockhash': 'blockhash'},
          },
          'getRecentPrioritizationFees' => <Object?>[
            <String, Object?>{'prioritizationFee': 1},
            <String, Object?>{'prioritizationFee': 9},
            <String, Object?>{'prioritizationFee': 5},
            <String, Object?>{'prioritizationFee': 7},
          ],
          'sendTransaction' => 'signature',
          'getSignatureStatuses' => <String, Object?>{
            'value': <Object?>[
              <String, Object?>{
                'slot': 10,
                'confirmationStatus': 'finalized',
                'err': null,
              },
            ],
          },
          _ => throw StateError('Unexpected operation $operation'),
        };
      });
      final session = _solanaSession(transport);

      expect(await session.getBalance('owner'), Decimal.parse('0.000000042'));
      expect(await session.getLatestBlockhash(), 'blockhash');
      expect(await session.getRecentPriorityFeeP75(), BigInt.from(7));
      expect(
        await session.broadcast(
          const SolanaSignedTransaction(base64Transaction: 'encoded'),
        ),
        'signature',
      );
      final receipt = await session.getTransactionReceipt('signature');
      expect(receipt?.success, isTrue);
      expect(receipt?.finalized, isTrue);
    });
  });

  group('SuiChainSession', () {
    test(
      'queries coins, estimates gas, broadcasts, and reads receipt',
      () async {
        final transport = _RoutingRpcTransport((operation, body) {
          return switch (operation) {
            'suix_getBalance' => <String, Object?>{'totalBalance': '100'},
            'suix_getAllCoins' => <String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'coinObjectId': '0xcoin',
                  'version': '2',
                  'digest': 'digest',
                  'coinType': '0x2::sui::SUI',
                  'balance': '100',
                },
              ],
              'hasNextPage': false,
              'nextCursor': null,
            },
            'sui_dryRunTransactionBlock' => <String, Object?>{
              'effects': <String, Object?>{
                'gasUsed': <String, Object?>{
                  'computationCost': '100',
                  'storageCost': '50',
                  'storageRebate': '25',
                },
              },
            },
            'sui_executeTransactionBlock' => <String, Object?>{
              'digest': 'tx-digest',
            },
            'sui_getTransactionBlock' => <String, Object?>{
              'digest': 'tx-digest',
              'checkpoint': '7',
              'timestampMs': '8',
              'effects': <String, Object?>{
                'status': <String, Object?>{'status': 'success'},
              },
            },
            _ => throw StateError('Unexpected operation $operation'),
          };
        });
        final session = _suiSession(transport);

        expect(await session.getBalance('0xowner'), Decimal.parse('0.0000001'));
        final coins = await session.getAllCoins('0xowner');
        expect(coins.single.balance, Decimal.parse('0.0000001'));
        expect(await session.estimateGasBudget('txBytes'), BigInt.from(150));
        expect(
          await session.broadcast(
            const SuiSignedTransaction(
              txBytes: 'txBytes',
              signature: 'signature',
            ),
          ),
          'tx-digest',
        );
        expect(
          (await session.getTransactionReceipt('tx-digest'))?.success,
          isTrue,
        );
      },
    );
  });

  group('TronChainSession', () {
    test(
      'builds raw transaction, queries fees, broadcasts, and reads receipt',
      () async {
        final raw = _tronRawTransaction();
        final transport = _RoutingRpcTransport((operation, body) {
          return switch (operation) {
            'wallet/getaccount' => <String, Object?>{'balance': 123},
            'wallet/createtransaction' => <String, Object?>{
              'raw_data_hex': raw.toHex,
            },
            'wallet/getchainparameters' => <String, Object?>{
              'chainParameter': <Object?>[
                <String, Object?>{'key': 'getTransactionFee', 'value': 1000},
                <String, Object?>{'key': 'getEnergyFee', 'value': 100},
                <String, Object?>{
                  'key': 'getCreateAccountFee',
                  'value': 100000,
                },
              ],
            },
            'wallet/broadcasthex' => <String, Object?>{
              'result': true,
              'txid': raw.txID,
            },
            'wallet/gettransactioninfobyid' => <String, Object?>{
              'blockNumber': 99,
              'fee': 10,
              'receipt': <String, Object?>{
                'result': 'SUCCESS',
                'energy_usage_total': 2,
                'net_usage': 3,
              },
            },
            _ => throw StateError('Unexpected operation $operation'),
          };
        });
        final session = _tronSession(transport);

        expect(await session.getBalance('Towner'), Decimal.parse('0.000123'));
        final unsigned = await session.buildTransfer(
          from: 'Towner',
          to: 'Trecipient',
          amount: Decimal.parse('0.000001'),
        );
        expect(unsigned.txId, raw.txID);
        expect(
          (await session.getFeeSchedule()).energyFee,
          Decimal.parse('0.0001'),
        );
        final txId = await session.broadcast(
          TronSignedTransaction(
            encodedTransaction: Transaction(
              rawData: raw,
              signature: <List<int>>[List<int>.filled(65, 0)],
            ).toHex,
            txId: raw.txID,
          ),
        );
        expect(txId, raw.txID);
        final receipt = await session.getTransactionReceipt(txId);
        expect(receipt?.success, isTrue);
        expect(receipt?.blockNumber, BigInt.from(99));
      },
    );
  });

  group('BitcoinChainSession', () {
    test('uses Electrum for UTXOs, balance, fees, and broadcast', () async {
      final electrum = _FakeElectrumTransport();
      final engine = WalletEngine(
        config: _config(
          family: ChainFamily.bitcoin,
          key: 'bitcoin',
          endpoint: 'tls://electrum.example.com:50002',
        ),
        adapters: <ChainAdapter>[
          BitcoinChainAdapter(transportFactory: () => electrum),
        ],
        transport: _RoutingRpcTransport((_, _) => null),
      );
      final session = engine.sessionAs<BitcoinChainSession>('bitcoin');
      const address = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';

      final utxos = await session.listUnspent(address);
      expect(utxos.single.amount, Decimal.parse('0.00001'));
      expect(await session.getBalance(address), Decimal.parse('0.000009'));
      expect(await session.estimateFeeRate(), Decimal.fromInt(2));
      expect(
        await session.broadcast(const BitcoinSignedTransaction(hex: '00')),
        'btc-txid',
      );
      expect(electrum.methods, contains('blockchain.scripthash.listunspent'));
    });
  });
}

SolanaChainSession _solanaSession(RpcTransport transport) {
  final engine = WalletEngine(
    config: _config(family: ChainFamily.solana, key: 'solana'),
    adapters: const <ChainAdapter>[SolanaChainAdapter()],
    transport: transport,
  );
  return engine.sessionAs<SolanaChainSession>('solana');
}

SuiChainSession _suiSession(RpcTransport transport) {
  final engine = WalletEngine(
    config: _config(family: ChainFamily.sui, key: 'sui'),
    adapters: const <ChainAdapter>[SuiChainAdapter()],
    transport: transport,
  );
  return engine.sessionAs<SuiChainSession>('sui');
}

TronChainSession _tronSession(RpcTransport transport) {
  final engine = WalletEngine(
    config: _config(family: ChainFamily.tron, key: 'tron'),
    adapters: const <ChainAdapter>[TronChainAdapter()],
    transport: transport,
  );
  return engine.sessionAs<TronChainSession>('tron');
}

WalletEngineConfig _config({
  required ChainFamily family,
  required String key,
  String endpoint = 'https://rpc.example.com',
}) {
  return WalletEngineConfig(
    revision: 1,
    version: 'test',
    chains: <WalletChainConfig>[
      WalletChainConfig(
        key: key,
        family: family,
        network: 'mainnet',
        nativeSymbol: key.toUpperCase(),
        nativeDecimals: switch (family) {
          ChainFamily.evm => 18,
          ChainFamily.solana || ChainFamily.sui => 9,
          ChainFamily.tron => 6,
          ChainFamily.bitcoin => 8,
          _ => 0,
        },
        rpcPool: RpcPoolConfig(
          endpoints: <RpcEndpoint>[RpcEndpoint.parse(endpoint)],
        ),
      ),
    ],
  );
}

TransactionRaw _tronRawTransaction() {
  const address = 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb';
  final transfer = TransferContract(
    amount: BigInt.one,
    ownerAddress: TronAddress(address),
    toAddress: TronAddress(address),
  );
  return TransactionRaw(
    refBlockBytes: const <int>[0, 0],
    refBlockHash: List<int>.filled(8, 0),
    expiration: BigInt.from(100),
    timestamp: BigInt.from(200),
    contract: <TransactionContract>[
      TransactionContract(
        type: TransactionContractType.transferContract,
        parameter: Any(
          typeUrl: 'type.googleapis.com/protocol.TransferContract',
          value: transfer,
        ),
      ),
    ],
  );
}

typedef _RpcResult =
    Object? Function(String operation, Map<String, Object?>? body);

final class _RoutingRpcTransport implements RpcTransport {
  const _RoutingRpcTransport(this.result);

  final _RpcResult result;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    final body = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : null;
    final value = result(request.operation, body);
    if (body != null && body['jsonrpc'] == '2.0') {
      return RpcResponse(
        statusCode: 200,
        data: <String, Object?>{
          'jsonrpc': '2.0',
          'id': body['id']!,
          'result': value,
        },
      );
    }
    return RpcResponse(statusCode: 200, data: value);
  }
}

final class _FakeElectrumTransport implements ElectrumTransport {
  final List<String> methods = <String>[];

  @override
  Future<Object?> request({
    required RpcEndpoint endpoint,
    required String method,
    required List<Object?> params,
    required Duration timeout,
  }) async {
    methods.add(method);
    return switch (method) {
      'blockchain.scripthash.listunspent' => <Object?>[
        <String, Object?>{'tx_hash': '00' * 32, 'tx_pos': 0, 'value': 1000},
      ],
      'blockchain.scripthash.get_balance' => <String, Object?>{
        'confirmed': 1000,
        'unconfirmed': -100,
      },
      'blockchain.estimatefee' => 0.00002,
      'blockchain.transaction.broadcast' => 'btc-txid',
      _ => throw StateError('Unexpected Electrum method $method'),
    };
  }

  @override
  Future<void> close() async {}
}
