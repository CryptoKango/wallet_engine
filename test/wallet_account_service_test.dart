import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

const _knownMnemonic =
    'test test test test test test test test test test test junk';
const _words24 =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

void main() {
  final accounts = WalletCoreAccountService(
    runtime: WalletCoreNativeRuntime(bridge: _NoopBridge()),
  );

  group('WalletCoreAccountService', () {
    test('validates only supported 12- and 24-word BIP-39 phrases', () {
      expect(accounts.validateMnemonic(_knownMnemonic), isTrue);
      expect(accounts.validateMnemonic('  $_knownMnemonic  '), isTrue);
      expect(accounts.validateMnemonic(_words24), isTrue);
      expect(accounts.validateMnemonic(''), isFalse);
      expect(
        accounts.validateMnemonic(
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon address',
        ),
        isFalse,
      );
      expect(accounts.validateMnemonic('not a valid mnemonic'), isFalse);
    });

    test('rejects account indexes outside the BIP-32 range', () async {
      await expectLater(
        accounts.createWallet12(family: ChainFamily.evm, account: -1),
        throwsA(
          isA<WalletValidationException>().having(
            (error) => error.context['field'],
            'field',
            'account',
          ),
        ),
      );
      await expectLater(
        accounts.createWallet24(family: ChainFamily.evm, account: 0x80000000),
        throwsA(isA<WalletValidationException>()),
      );
    });

    test(
      'rejects invalid mnemonic before entering the native runtime',
      () async {
        const invalid = 'secret words that must not appear in diagnostics';

        await expectLater(
          accounts.deriveAccount(mnemonic: invalid, family: ChainFamily.evm),
          throwsA(
            isA<WalletAccountException>()
                .having(
                  (error) => error.publicCode,
                  'publicCode',
                  WalletErrorCode.accountInvalidMnemonic,
                )
                .having(
                  (error) => error.toString(),
                  'safe message',
                  isNot(contains(invalid)),
                ),
          ),
        );
      },
    );

    test('wallet value objects redact recovery and private material', () {
      const privateKey = 'private-key-that-must-not-be-logged';
      const wallet = WalletAccount(
        family: ChainFamily.evm,
        network: 'mainnet',
        account: 0,
        derivationPath: "m/44'/60'/0'/0/0",
        address: '0x1234',
        publicKey: 'public-key',
        privateKey: privateKey,
      );
      const created = CreatedWallet(
        mnemonic: _knownMnemonic,
        wordCount: MnemonicWordCount.words12,
        wallet: wallet,
      );

      expect(wallet.toString(), isNot(contains(privateKey)));
      expect(created.toString(), isNot(contains(_knownMnemonic)));
      expect(created.toString(), isNot(contains(privateKey)));
    });

    test('creates validated watch-only accounts', () {
      final wallet = accounts.createWatchOnly(
        address: '0x52908400098527886E0F7030069857D2E4169EE7',
        family: ChainFamily.evm,
      );

      expect(wallet.family, ChainFamily.evm);
      expect(wallet.network, 'mainnet');
      expect(wallet.address, startsWith('0x'));
      expect(
        () => accounts.createWatchOnly(
          address: '0x1234',
          family: ChainFamily.evm,
        ),
        throwsA(
          isA<WalletAccountException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.accountInvalidAddress,
          ),
        ),
      );
    });

    test('rejects invalid private keys before native import', () async {
      const invalid = 'private-key-that-must-not-be-logged';
      await expectLater(
        accounts.importPrivateKey(privateKey: invalid, family: ChainFamily.evm),
        throwsA(
          isA<WalletAccountException>()
              .having(
                (error) => error.publicCode,
                'publicCode',
                WalletErrorCode.accountInvalidPrivateKey,
              )
              .having(
                (error) => error.toString(),
                'safe message',
                isNot(contains(invalid)),
              ),
        ),
      );
    });
  });

  group('WalletEngine wallet API', () {
    test(
      'uses configured family and network for 12/24-word creation',
      () async {
        final accounts = _FakeWalletAccountService();
        final engine = WalletEngine(
          config: _config(),
          adapters: const <ChainAdapter>[],
          transport: _FakeTransport(),
          walletAccounts: accounts,
        );

        final words12 = await engine.createWallet12(
          chainKey: 'bitcoin-testnet',
        );
        expect(words12.wordCount, MnemonicWordCount.words12);
        expect(words12.wallet.privateKey, isNull);
        expect(accounts.lastFamily, ChainFamily.bitcoin);
        expect(accounts.lastNetwork, 'testnet');

        final words24 = await engine.createWallet24(
          chainKey: 'bitcoin-testnet',
          exposePrivateKey: true,
        );
        expect(words24.wordCount, MnemonicWordCount.words24);
        expect(words24.wallet.privateKey, 'private');
        expect(engine.validateMnemonic(_knownMnemonic), isTrue);
        expect(
          engine.validateAddress(
            chainKey: 'bitcoin-testnet',
            address: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
          ),
          isTrue,
        );
        await engine.close();
      },
    );

    test('derivation does not echo the supplied mnemonic', () async {
      final engine = WalletEngine(
        config: _config(),
        adapters: const <ChainAdapter>[],
        transport: _FakeTransport(),
        walletAccounts: _FakeWalletAccountService(),
      );

      final wallet = await engine.deriveAccount(
        chainKey: 'bitcoin-testnet',
        mnemonic: _knownMnemonic,
      );

      expect(wallet.family, ChainFamily.bitcoin);
      expect(wallet.network, 'testnet');
      expect(wallet.toString(), isNot(contains(_knownMnemonic)));
      await engine.close();
    });

    test('delegates private-key import and watch-only creation', () async {
      final accounts = _FakeWalletAccountService();
      final engine = WalletEngine(
        config: _config(),
        adapters: const <ChainAdapter>[],
        transport: _FakeTransport(),
        walletAccounts: accounts,
      );

      final imported = await engine.importPrivateKey(
        chainKey: 'bitcoin-testnet',
        privateKey: 'private',
      );
      final watched = engine.createWatchOnly(
        chainKey: 'bitcoin-testnet',
        address: 'tb1qexample',
      );

      expect(imported.source, WalletAccountSource.privateKey);
      expect(watched.address, 'tb1qexample');
      expect(accounts.lastNetwork, 'testnet');
      await engine.close();
    });

    test('rejects wallet creation for an unknown configured key', () async {
      final engine = WalletEngine(
        config: _config(),
        adapters: const <ChainAdapter>[],
        transport: _FakeTransport(),
        walletAccounts: _FakeWalletAccountService(),
      );

      expect(
        () => engine.createWallet12(chainKey: 'unknown'),
        throwsA(
          isA<WalletEngineException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.engineChainNotConfigured,
          ),
        ),
      );
      await engine.close();
    });
  });

  test('account failures map to stable public codes and categories', () {
    const failures = <WalletAccountException>[
      WalletAccountException(
        code: WalletAccountErrorCode.invalidMnemonic,
        message: 'invalid',
      ),
      WalletAccountException(
        code: WalletAccountErrorCode.unsupportedChain,
        message: 'unsupported',
      ),
      WalletAccountException(
        code: WalletAccountErrorCode.invalidAddress,
        message: 'invalid address',
      ),
      WalletAccountException(
        code: WalletAccountErrorCode.invalidPrivateKey,
        message: 'invalid private key',
      ),
      WalletAccountException(
        code: WalletAccountErrorCode.generationFailed,
        message: 'generation failed',
      ),
      WalletAccountException(
        code: WalletAccountErrorCode.derivationFailed,
        message: 'derivation failed',
      ),
    ];

    expect(failures.map((error) => error.publicCode), <WalletErrorCode>[
      WalletErrorCode.accountInvalidMnemonic,
      WalletErrorCode.accountUnsupportedChain,
      WalletErrorCode.accountInvalidAddress,
      WalletErrorCode.accountInvalidPrivateKey,
      WalletErrorCode.accountGenerationFailed,
      WalletErrorCode.accountDerivationFailed,
    ]);
    expect(failures.map((error) => error.category), <WalletErrorCategory>[
      WalletErrorCategory.validation,
      WalletErrorCategory.chain,
      WalletErrorCategory.validation,
      WalletErrorCategory.validation,
      WalletErrorCategory.internal,
      WalletErrorCategory.internal,
    ]);
    expect(failures.every((error) => !error.retryable), isTrue);
    expect(
      failures.map((error) => error.errorCode),
      failures.map((error) => error.publicCode.value),
    );
  });
}

final class _NoopBridge implements WalletCoreNativeBridge {
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
}

WalletEngineConfig _config() {
  return WalletEngineConfig(
    revision: 1,
    version: 'wallet-test',
    chains: <WalletChainConfig>[
      WalletChainConfig(
        key: 'bitcoin-testnet',
        family: ChainFamily.bitcoin,
        network: 'testnet',
        nativeSymbol: 'BTC',
        nativeDecimals: 8,
        rpcPool: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://rpc.example.com'),
          ],
        ),
      ),
    ],
  );
}

final class _FakeWalletAccountService implements WalletAccountService {
  ChainFamily? lastFamily;
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
    lastFamily = family;
    lastNetwork = network;
    return CreatedWallet(
      mnemonic: wordCount == MnemonicWordCount.words12
          ? _knownMnemonic
          : _words24,
      wordCount: wordCount,
      wallet: _wallet(family, network, account, exposePrivateKey),
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
  }) async {
    lastFamily = family;
    lastNetwork = network;
    return _wallet(family, network, account, exposePrivateKey);
  }

  @override
  Future<WalletAccount> importPrivateKey({
    required String privateKey,
    required ChainFamily family,
    String network = 'mainnet',
    bool exposePrivateKey = false,
  }) async {
    lastFamily = family;
    lastNetwork = network;
    return WalletAccount(
      family: family,
      network: network,
      account: 0,
      derivationPath: '',
      address: 'tb1qexample',
      publicKey: 'public',
      privateKey: exposePrivateKey ? privateKey : null,
      source: WalletAccountSource.privateKey,
    );
  }

  @override
  WatchOnlyWallet createWatchOnly({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    lastFamily = family;
    lastNetwork = network;
    return WatchOnlyWallet(family: family, network: network, address: address);
  }

  @override
  bool validateMnemonic(String mnemonic) {
    return mnemonic.trim() == _knownMnemonic || mnemonic.trim() == _words24;
  }

  @override
  bool validateAddress({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    return address.isNotEmpty;
  }

  @override
  bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  }) {
    return privateKey.isNotEmpty;
  }

  WalletAccount _wallet(
    ChainFamily family,
    String network,
    int account,
    bool exposePrivateKey,
  ) {
    return WalletAccount(
      family: family,
      network: network,
      account: account,
      derivationPath: "m/84'/0'/0'/0/$account",
      address: 'tb1qexample',
      publicKey: 'public',
      privateKey: exposePrivateKey ? 'private' : null,
    );
  }
}

final class _FakeTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    return RpcResponse(statusCode: 200, data: const <String, Object?>{});
  }
}
