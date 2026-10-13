import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart' show SolanaPrivateKey;
import 'package:wallet_engine/wallet_engine.dart';

const _mint = 'So11111111111111111111111111111111111111112';

void main() {
  group('Solana ATA', () {
    late String owner;

    setUpAll(() {
      owner = SolanaPrivateKey.fromSeed(
        List<int>.generate(32, (index) => index),
      ).publicKey().toAddress().address;
    });

    test('derives deterministic Token and Token-2022 addresses locally', () {
      final session = _session(_RpcTransport((_, _) => null));

      expect(
        session.deriveAssociatedTokenAddress(owner: owner, mint: _mint),
        '6G1uk4kms3xPSeX1RwzMaYumnqWBs9xxCEUjZk5MxPvF',
      );
      expect(
        session.deriveAssociatedTokenAddress(
          owner: owner,
          mint: _mint,
          program: SolanaTokenProgram.token2022,
        ),
        'GFEpmcy6uNzCHLivEEr9zKLJJDhxqWZwaGYyVWdxoUjS',
      );
      expect(
        () =>
            session.deriveAssociatedTokenAddress(owner: 'invalid', mint: _mint),
        throwsA(
          isA<WalletValidationException>().having(
            (error) => error.context['field'],
            'field',
            'owner',
          ),
        ),
      );
    });

    test(
      'lists accounts, identifies the ATA, and aggregates balances',
      () async {
        late SolanaChainSession session;
        final transport = _RpcTransport((operation, body) {
          final ata = session.deriveAssociatedTokenAddress(
            owner: owner,
            mint: _mint,
          );
          return switch (operation) {
            'getTokenAccountsByOwner' => <String, Object?>{
              'value': <Object?>[
                _listedAccount(
                  address: ata,
                  account: _account(owner: owner, amount: '1250000'),
                ),
                _listedAccount(
                  address: _mint,
                  account: _account(owner: owner, amount: '750000'),
                ),
              ],
            },
            _ => throw StateError('Unexpected operation $operation'),
          };
        });
        session = _session(transport);

        final accounts = await session.getTokenAccountsByOwner(
          owner: owner,
          mint: _mint,
        );
        expect(accounts, hasLength(2));
        expect(accounts.first.isAssociated, isTrue);
        expect(accounts.last.isAssociated, isFalse);
        expect(accounts.first.program, SolanaTokenProgram.token);
        expect(accounts.first.state, SolanaTokenAccountState.initialized);
        expect(accounts.first.tokenAmount.baseUnits, BigInt.from(1250000));
        expect(accounts.first.tokenAmount.amount, Decimal.parse('1.25'));
        expect(
          await session.getTokenBalance(owner: owner, mint: _mint),
          Decimal.parse('2'),
        );
        expect(
          await session.getTokenAccountAddress(owner: owner, mint: _mint),
          accounts.first.address,
        );
      },
    );

    test(
      'queries ATA existence, parsed state, and exact address balance',
      () async {
        late SolanaChainSession session;
        var accountExists = true;
        final transport = _RpcTransport((operation, body) {
          return switch (operation) {
            'getAccountInfo' => <String, Object?>{
              'value': accountExists
                  ? _account(owner: owner, amount: '42000000')
                  : null,
            },
            'getTokenAccountBalance' => <String, Object?>{
              'value': <String, Object?>{'amount': '42000000', 'decimals': 6},
            },
            _ => throw StateError('Unexpected operation $operation'),
          };
        });
        session = _session(transport);
        final ata = session.deriveAssociatedTokenAddress(
          owner: owner,
          mint: _mint,
        );

        final account = await session.getAssociatedTokenAccount(
          owner: owner,
          mint: _mint,
        );
        expect(account?.address, ata);
        expect(account?.isAssociated, isTrue);
        expect(
          await session.associatedTokenAccountExists(owner: owner, mint: _mint),
          isTrue,
        );
        final balance = await session.getTokenAccountBalance(ata);
        expect(balance.baseUnits, BigInt.from(42000000));
        expect(balance.amount, Decimal.fromInt(42));

        accountExists = false;
        expect(
          await session.getAssociatedTokenAccount(owner: owner, mint: _mint),
          isNull,
        );
        expect(
          await session.associatedTokenAccountExists(owner: owner, mint: _mint),
          isFalse,
        );
      },
    );

    test('uses the selected program as the owner query filter', () async {
      late SolanaChainSession session;
      final transport = _RpcTransport((operation, body) {
        final params = body!['params']! as List<Object?>;
        expect(params[1], <String, Object?>{
          'programId': SolanaTokenProgram.token2022.programId,
        });
        final ata = session.deriveAssociatedTokenAddress(
          owner: owner,
          mint: _mint,
          program: SolanaTokenProgram.token2022,
        );
        return <String, Object?>{
          'value': <Object?>[
            _listedAccount(
              address: ata,
              account: _account(
                owner: owner,
                amount: '1000000',
                program: SolanaTokenProgram.token2022,
              ),
            ),
          ],
        };
      });
      session = _session(transport);

      final accounts = await session.getTokenAccountsByOwner(
        owner: owner,
        program: SolanaTokenProgram.token2022,
      );
      expect(accounts, hasLength(1));
      expect(accounts.single.program, SolanaTokenProgram.token2022);
      expect(accounts.single.isAssociated, isTrue);
      expect(accounts.single.tokenAmount.amount, Decimal.one);
    });
  });
}

Map<String, Object?> _listedAccount({
  required String address,
  required Map<String, Object?> account,
}) {
  return <String, Object?>{'pubkey': address, 'account': account};
}

Map<String, Object?> _account({
  required String owner,
  required String amount,
  SolanaTokenProgram program = SolanaTokenProgram.token,
}) {
  return <String, Object?>{
    'owner': program.programId,
    'data': <String, Object?>{
      'parsed': <String, Object?>{
        'type': 'account',
        'info': <String, Object?>{
          'owner': owner,
          'mint': _mint,
          'state': 'initialized',
          'isNative': false,
          'tokenAmount': <String, Object?>{'amount': amount, 'decimals': 6},
        },
      },
    },
  };
}

SolanaChainSession _session(RpcTransport transport) {
  final engine = WalletEngine(
    config: WalletEngineConfig(
      revision: 1,
      version: 'test',
      chains: <WalletChainConfig>[
        WalletChainConfig(
          key: 'solana',
          family: ChainFamily.solana,
          network: 'devnet',
          nativeSymbol: 'SOL',
          nativeDecimals: 9,
          rpcPool: RpcPoolConfig(
            endpoints: <RpcEndpoint>[
              RpcEndpoint.parse('https://rpc.example.com'),
            ],
          ),
        ),
      ],
    ),
    adapters: const <ChainAdapter>[SolanaChainAdapter()],
    transport: transport,
  );
  return engine.sessionAs<SolanaChainSession>('solana');
}

typedef _Result =
    Object? Function(String operation, Map<String, Object?>? body);

final class _RpcTransport implements RpcTransport {
  const _RpcTransport(this.result);

  final _Result result;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    final body = request.body! as Map<String, Object?>;
    return RpcResponse(
      statusCode: 200,
      data: <String, Object?>{
        'jsonrpc': '2.0',
        'id': body['id']!,
        'result': result(request.operation, body),
      },
    );
  }
}
