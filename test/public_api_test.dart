import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('public App API', () {
    test('runs an end-to-end engine lifecycle through exported APIs', () async {
      final events = <WalletLogEvent>[];
      final accounts = _PublicAccounts();
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[_PublicAdapter()],
        transport: _PublicTransport(),
        walletAccounts: accounts,
        logger: WalletLogger(
          sink: events.add,
          minimumLevel: WalletLogLevel.debug,
        ),
      );

      final identities = await engine.verifyNetworkIdentities(requireAll: true);
      expect(identities['ethereum']?.matches, isTrue);

      final session = engine.sessionAs<_PublicSession>('ethereum');
      expect(await session.ping(), 'pong');

      final created = await engine.createWallet12(chainKey: 'ethereum');
      expect(created.wordCount, MnemonicWordCount.words12);
      expect(created.wallet.family, ChainFamily.evm);
      expect(created.wallet.privateKey, isNull);
      expect(accounts.lastNetwork, 'mainnet');

      final previousSession = session;
      await engine.applyConfig(_config(revision: 2));
      final nextSession = engine.sessionAs<_PublicSession>('ethereum');
      expect(nextSession, isNot(same(previousSession)));
      expect(previousSession.closed, isTrue);

      await engine.close();

      expect(
        () => engine.session('ethereum'),
        throwsA(
          isA<WalletEngineException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.engineClosed,
          ),
        ),
      );
      expect(
        events.map((event) => event.operation),
        containsAll(<String>[
          'engine.create',
          'network.verify',
          'session.open',
          'rpc.success',
          'account.create12',
          'config.apply',
          'engine.close',
        ]),
      );
    });

    test(
      'surfaces account failures through stable API and log codes',
      () async {
        final events = <WalletLogEvent>[];
        final accounts = _PublicAccounts(
          createError: const NormalizedWalletException(
            category: WalletErrorCategory.validation,
            publicCode: WalletErrorCode.accountGenerationFailed,
            message: 'Wallet generation failed.',
            retryable: false,
          ),
        );
        final engine = WalletEngine(
          config: _config(revision: 1),
          adapters: <ChainAdapter>[_PublicAdapter()],
          transport: _PublicTransport(),
          walletAccounts: accounts,
          logger: WalletLogger(
            sink: events.add,
            minimumLevel: WalletLogLevel.debug,
          ),
        );
        addTearDown(engine.close);

        await expectLater(
          engine.createWallet24(chainKey: 'ethereum'),
          throwsA(
            isA<WalletError>().having(
              (error) => error.errorCode,
              'errorCode',
              'account.generationFailed',
            ),
          ),
        );

        final failure = events.lastWhere(
          (event) => event.operation == 'account.create24',
        );
        expect(failure.level, WalletLogLevel.error);
        expect(failure.errorCode, 'account.generationFailed');
        expect(failure.context['retryable'], isFalse);
      },
    );

    test('keeps public API constants and collections stable', () {
      expect(WalletErrorProtocol.version, 1);
      expect(Bip39WordList.english.words, hasLength(2048));
      expect(
        () => Bip39WordList.english.words.add('not-allowed'),
        throwsUnsupportedError,
      );
      expect(
        WalletErrorProtocol.tryParse('rpc.transport.timeout'),
        WalletErrorCode.rpcTransportTimeout,
      );
      expect(WalletErrorProtocol.tryParse('future.unknown'), isNull);
    });
  });
}

WalletEngineConfig _config({required int revision}) {
  return WalletEngineConfig(
    revision: revision,
    version: 'public-api-$revision',
    chains: <WalletChainConfig>[
      WalletChainConfig(
        key: 'ethereum',
        family: ChainFamily.evm,
        network: 'mainnet',
        chainId: '1',
        nativeSymbol: 'ETH',
        nativeDecimals: 18,
        rpcPool: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://rpc.example.com'),
          ],
        ),
      ),
    ],
  );
}

final class _PublicAdapter implements ChainAdapter {
  @override
  ChainFamily get family => ChainFamily.evm;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) => _PublicSession(config, rpc);
}

final class _PublicSession
    implements ChainSession, ChainNetworkIdentityVerifier {
  _PublicSession(this.config, this._rpc);

  @override
  final WalletChainConfig config;
  final RpcClient _rpc;
  bool closed = false;

  Future<String> ping() async {
    final response = await _rpc.send(RpcRequest(operation: 'api_ping'));
    return response.data! as String;
  }

  @override
  Future<ChainNetworkIdentity> verifyNetworkIdentity() async {
    return ChainNetworkIdentity(
      family: config.family,
      configured: config.chainId!,
      observed: config.chainId!,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _PublicTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async => RpcResponse(statusCode: 200, data: 'pong');
}

final class _PublicAccounts implements WalletAccountService {
  _PublicAccounts({this.createError});

  final WalletError? createError;
  String? lastNetwork;

  @override
  Future<CreatedWallet> createWallet12({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    return createWallet(
      family: family,
      wordCount: MnemonicWordCount.words12,
      network: network,
      account: account,
      passphrase: passphrase,
      exposePrivateKey: exposePrivateKey,
    );
  }

  @override
  Future<CreatedWallet> createWallet24({
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    return createWallet(
      family: family,
      wordCount: MnemonicWordCount.words24,
      network: network,
      account: account,
      passphrase: passphrase,
      exposePrivateKey: exposePrivateKey,
    );
  }

  @override
  Future<CreatedWallet> createWallet({
    required ChainFamily family,
    required MnemonicWordCount wordCount,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) async {
    final error = createError;
    if (error != null) throw error;
    lastNetwork = network;
    return CreatedWallet(
      mnemonic: List<String>.filled(wordCount.value, 'abandon').join(' '),
      wordCount: wordCount,
      wallet: _account(family, network, account),
    );
  }

  @override
  Future<WalletAccount> deriveAccount({
    required String mnemonic,
    required ChainFamily family,
    String network = 'mainnet',
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) async => _account(family, network, account);

  @override
  Future<WalletAccount> importPrivateKey({
    required String privateKey,
    required ChainFamily family,
    String network = 'mainnet',
    bool exposePrivateKey = false,
  }) async => _account(family, network, 0);

  @override
  WatchOnlyWallet createWatchOnly({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) => WatchOnlyWallet(family: family, network: network, address: address);

  @override
  bool validateMnemonic(String mnemonic) => mnemonic.trim().isNotEmpty;

  @override
  bool validateAddress({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) => address.isNotEmpty;

  @override
  bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  }) => privateKey.isNotEmpty;

  static WalletAccount _account(
    ChainFamily family,
    String network,
    int account,
  ) {
    return WalletAccount(
      family: family,
      network: network,
      account: account,
      derivationPath: "m/44'/60'/0'/0/0",
      address: '0x0000000000000000000000000000000000000001',
      publicKey: 'public',
    );
  }
}
