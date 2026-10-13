import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('EvmChainSession', () {
    test('provides generic EVM RPC methods', () async {
      final transport = _JsonRpcTransport(<Object?>[
        '0x1',
        '0x10',
        '0x2',
        '0x5208',
        '0xtransaction',
        <String, Object?>{
          'transactionHash': '0xtransaction',
          'blockNumber': '0xa',
          'status': '0x1',
          'gasUsed': '0x5208',
        },
      ]);
      final session = _session(transport);

      expect(await session.getChainId(), BigInt.one);
      expect(
        await session.getBalance('0xaccount'),
        Decimal.parse('0.000000000000000016'),
      );
      expect(await session.getTransactionCount('0xaccount'), BigInt.two);
      expect(
        await session.estimateGas(const EvmCall(to: '0xrecipient')),
        BigInt.from(21000),
      );
      expect(await session.broadcast('0xsigned'), '0xtransaction');
      final receipt = await session.getTransactionReceipt('0xtransaction');
      expect(receipt?.success, isTrue);
      expect(receipt?.blockNumber, BigInt.from(10));
    });

    test('verifies the configured chain id against the RPC node', () async {
      final session = _session(_JsonRpcTransport(<Object?>['0x1']));

      final identity = await session.verifyNetworkIdentity();

      expect(identity.matches, isTrue);
      expect(identity.configured, '1');
      expect(identity.observed, '1');
    });

    test('rejects a mismatched RPC network', () async {
      final session = _session(_JsonRpcTransport(<Object?>['0xaa36a7']));

      await expectLater(
        session.verifyNetworkIdentity(),
        throwsA(
          isA<WalletError>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.configurationNetworkMismatch,
          ),
        ),
      );
    });

    test('estimates EIP-1559 fees', () async {
      final transport = _JsonRpcTransport(<Object?>[
        '0x5208',
        <String, Object?>{'baseFeePerGas': '0x3b9aca00'},
        '0x77359400',
      ]);
      final session = _session(transport);

      final quote = await session.estimateFee(const EvmCall(to: '0xrecipient'));

      expect(quote.isEip1559, isTrue);
      expect(quote.gasLimit, BigInt.from(21000));
      expect(quote.maxPriorityFeePerGas, BigInt.from(2000000000));
      expect(quote.maxFeePerGas, BigInt.from(4000000000));
      expect(quote.maximumCost(nativeDecimals: 18), Decimal.parse('0.000084'));
    });

    test(
      'falls back to legacy fees when latest block has no base fee',
      () async {
        final transport = _JsonRpcTransport(<Object?>[
          '0x5208',
          <String, Object?>{},
          '0x3b9aca00',
        ]);
        final session = _session(transport);

        final quote = await session.estimateFee(
          const EvmCall(to: '0xrecipient'),
        );

        expect(quote.isEip1559, isFalse);
        expect(quote.gasPrice, BigInt.from(1000000000));
      },
    );

    test('prepares an unsigned EIP-1559 transaction', () async {
      final transport = _JsonRpcTransport(<Object?>[
        '0x7',
        '0x5208',
        <String, Object?>{'baseFeePerGas': '0x3b9aca00'},
        '0x77359400',
      ]);
      final session = _session(transport);

      final transaction = await session.prepareTransaction(
        EvmTransactionRequest(
          from: '0xsender',
          to: '0xrecipient',
          value: Decimal.parse('0.000000000000000042'),
          data: '0x1234',
        ),
      );

      expect(transaction.chainId, BigInt.one);
      expect(transaction.nonce, BigInt.from(7));
      expect(transaction.gasLimit, BigInt.from(21000));
      expect(transaction.valueBaseUnits, BigInt.from(42));
      expect(transaction.isEip1559, isTrue);
      expect(transaction.maxFeePerGas, BigInt.from(4000000000));
    });

    test('signs through an injected signer before broadcasting', () async {
      final transport = _JsonRpcTransport(<Object?>['0xtransaction']);
      final session = _session(transport);
      final transaction = EvmUnsignedTransaction.legacy(
        chainId: BigInt.one,
        nonce: BigInt.zero,
        gasLimit: BigInt.from(21000),
        to: '0xrecipient',
        gasPrice: BigInt.from(1000000000),
      );

      final result = await session.signAndBroadcast(
        transaction,
        signer: _FakeEvmSigner(),
      );

      expect(result.transactionHash, '0xtransaction');
      expect(result.signedTransaction.rawTransaction, '0xdeadbeef');
      expect(transport.requests.single['method'], 'eth_sendRawTransaction');
      expect(transport.requests.single['params'], <Object?>['0xdeadbeef']);
    });
  });
}

EvmChainSession _session(RpcTransport transport) {
  final engine = WalletEngine(
    config: WalletEngineConfig(
      revision: 1,
      version: 'test',
      chains: <WalletChainConfig>[
        WalletChainConfig(
          key: 'ethereum',
          family: ChainFamily.evm,
          network: 'mainnet',
          nativeSymbol: 'ETH',
          nativeDecimals: 18,
          chainId: '1',
          rpcPool: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('https://rpc.example.com'),
            ],
          ),
        ),
      ],
    ),
    adapters: const <ChainAdapter>[EvmChainAdapter()],
    transport: transport,
  );
  return engine.sessionAs<EvmChainSession>('ethereum');
}

final class _JsonRpcTransport implements RpcTransport {
  _JsonRpcTransport(this._results);

  final List<Object?> _results;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  int _index = 0;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    final body = request.body! as Map<String, Object?>;
    requests.add(body);
    return RpcResponse(
      statusCode: 200,
      data: <String, Object?>{
        'jsonrpc': '2.0',
        'id': body['id']!,
        'result': _results[_index++],
      },
    );
  }
}

final class _FakeEvmSigner implements EvmTransactionSigner {
  @override
  Future<EvmSignedTransaction> sign(EvmUnsignedTransaction transaction) async {
    return EvmSignedTransaction('deadbeef');
  }
}
