import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';
import 'package:wallet_engine_example/main.dart';

void main() {
  testWidgets('shows a startup failure without exposing sensitive data', (
    WidgetTester tester,
  ) async {
    final logStore = WalletDemoLogStore();
    addTearDown(logStore.dispose);
    await tester.pumpWidget(
      WalletEngineExample(
        engine: null,
        startupError: 'native runtime unavailable',
        logStore: logStore,
      ),
    );

    expect(find.text('Trust Wallet Core 初始化失败'), findsOneWidget);
    expect(find.text('native runtime unavailable'), findsOneWidget);
  });

  testWidgets('creates a wallet and keeps secrets hidden by default', (
    WidgetTester tester,
  ) async {
    final logStore = WalletDemoLogStore();
    addTearDown(logStore.dispose);
    final engine = WalletEngine(
      config: WalletEngineTestnetPreset.create(),
      adapters: const <ChainAdapter>[],
      transport: _UnusedTransport(),
      walletAccounts: _FakeWalletAccounts(),
    );

    await tester.pumpWidget(
      WalletEngineExample(
        engine: engine,
        startupError: null,
        logStore: logStore,
      ),
    );
    expect(find.text('Wallet Engine Lab'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('bip39-prefix')), 'ab');
    final searchButton = find.byKey(const Key('search-bip39'));
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pump();
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('ability'), findsOneWidget);

    final createButton = find.byKey(const Key('create-12'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text(_FakeWalletAccounts.address), findsOneWidget);
    expect(find.text(_FakeWalletAccounts.mnemonic), findsNothing);
    expect(find.text(_FakeWalletAccounts.privateKey), findsNothing);
    expect(find.textContaining('敏感信息仅保存在当前页面内存中'), findsOneWidget);
  });

  testWidgets('runs the RPC/API demo and renders structured SDK logs', (
    WidgetTester tester,
  ) async {
    final logStore = WalletDemoLogStore();
    addTearDown(logStore.dispose);
    final engine = WalletEngine(
      config: WalletEngineTestnetPreset.create(),
      adapters: <ChainAdapter>[const EvmChainAdapter()],
      transport: _EvmRpcTransport(),
      logger: WalletLogger(
        sink: logStore.record,
        minimumLevel: WalletLogLevel.debug,
      ),
    );

    await tester.pumpWidget(
      WalletEngineExample(
        engine: engine,
        startupError: null,
        logStore: logStore,
      ),
    );

    final verifyButton = find.byKey(const Key('verify-network'));
    await tester.ensureVisible(verifyButton);
    await tester.tap(verifyButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('matches=true'), findsOneWidget);

    final rpcButton = find.byKey(const Key('rpc-probe'));
    await tester.ensureVisible(rpcButton);
    await tester.tap(rpcButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('eth_blockNumber=100'), findsOneWidget);
    expect(find.byKey(const Key('sdk-log-list')), findsOneWidget);
    expect(find.textContaining('rpc.success'), findsWidgets);

    final snapshotButton = find.byKey(const Key('config-snapshot'));
    await tester.ensureVisible(snapshotButton);
    await tester.tap(snapshotButton);
    await tester.pump();
    expect(find.textContaining('"schemaVersion": 1'), findsOneWidget);
  });
}

final class _UnusedTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) {
    throw UnsupportedError('RPC is not used by this widget test.');
  }
}

final class _EvmRpcTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    final body = request.body! as Map<String, Object?>;
    final method = body['method']! as String;
    final result = switch (method) {
      'eth_chainId' => '0xaa36a7',
      'eth_blockNumber' => '0x64',
      'eth_gasPrice' => '0x3b9aca00',
      _ => throw StateError('Unexpected EVM method: $method'),
    };
    return RpcResponse(
      statusCode: 200,
      data: <String, Object?>{
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': result,
      },
    );
  }
}

final class _FakeWalletAccounts implements WalletAccountService {
  static const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  static const String address = '0x0000000000000000000000000000000000000001';
  static const String privateKey =
      '0000000000000000000000000000000000000000000000000000000000000001';

  WalletAccount _account(
    ChainFamily family,
    String network, {
    WalletAccountSource source = WalletAccountSource.hd,
  }) {
    return WalletAccount(
      family: family,
      network: network,
      account: 0,
      derivationPath: "m/44'/60'/0'/0/0",
      address: address,
      publicKey: 'public-key',
      privateKey: privateKey,
      source: source,
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
    return CreatedWallet(
      mnemonic: mnemonic,
      wordCount: wordCount,
      wallet: _account(family, network),
    );
  }

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
    return _account(family, network);
  }

  @override
  Future<WalletAccount> importPrivateKey({
    required String privateKey,
    required ChainFamily family,
    String network = 'mainnet',
    bool exposePrivateKey = false,
  }) async {
    return _account(family, network, source: WalletAccountSource.privateKey);
  }

  @override
  WatchOnlyWallet createWatchOnly({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    return WatchOnlyWallet(family: family, network: network, address: address);
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
  bool validateMnemonic(String mnemonic) => mnemonic.trim().isNotEmpty;

  @override
  bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  }) {
    return privateKey.isNotEmpty;
  }
}
