import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet_engine/wallet_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WalletEngine? engine;
  Object? startupError;
  final logStore = WalletDemoLogStore();
  try {
    final logger = WalletLogger(
      minimumLevel: WalletLogLevel.debug,
      sink: logStore.record,
    );
    final walletCore = WalletCoreNativeRuntime(
      bridge: FfiWalletCoreNativeBridge.open(),
      logger: logger,
    );
    await walletCore.initialize();
    engine = WalletEngine(
      config: WalletEngineTestnetPreset.create(
        revision: 1,
        suiEndpoints: <RpcEndpoint>[
          RpcEndpoint.parse('https://fullnode.testnet.sui.io:443'),
        ],
      ),
      adapters: walletEngineDefaultAdapters(),
      transport: DioRpcTransport(),
      logger: logger,
      walletAccounts: WalletCoreAccountService(runtime: walletCore),
    );
  } catch (error) {
    startupError = error;
  }

  runApp(
    WalletEngineExample(
      engine: engine,
      startupError: startupError,
      logStore: logStore,
    ),
  );
}

/// Small in-memory diagnostic buffer used only by the example application.
final class WalletDemoLogStore extends ValueNotifier<List<WalletLogEvent>> {
  WalletDemoLogStore() : super(const <WalletLogEvent>[]);

  static const int maxEntries = 100;

  void record(WalletLogEvent event) {
    debugPrint('[wallet_engine] ${event.toDiagnosticMap()}');
    final next = <WalletLogEvent>[...value, event];
    value = List<WalletLogEvent>.unmodifiable(
      next.length <= maxEntries ? next : next.sublist(next.length - maxEntries),
    );
  }

  void clearEntries() {
    value = const <WalletLogEvent>[];
  }
}

class WalletEngineExample extends StatelessWidget {
  const WalletEngineExample({
    required this.engine,
    required this.startupError,
    required this.logStore,
    super.key,
  });

  final WalletEngine? engine;
  final Object? startupError;
  final WalletDemoLogStore logStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wallet Engine Lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3157d5)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: engine == null
          ? _StartupFailure(error: startupError)
          : WalletLabPage(engine: engine!, logStore: logStore),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Trust Wallet Core 初始化失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(error?.toString() ?? 'Unknown startup error'),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletLabPage extends StatefulWidget {
  const WalletLabPage({
    required this.engine,
    required this.logStore,
    super.key,
  });

  final WalletEngine engine;
  final WalletDemoLogStore logStore;

  @override
  State<WalletLabPage> createState() => _WalletLabPageState();
}

class _WalletLabPageState extends State<WalletLabPage> {
  static const Map<String, String> _chainLabels = <String, String>{
    WalletEngineTestnetPreset.ethereumSepoliaKey: 'Ethereum Sepolia',
    WalletEngineTestnetPreset.solanaDevnetKey: 'Solana Devnet',
    WalletEngineTestnetPreset.tronNileKey: 'TRON Nile',
    WalletEngineTestnetPreset.bitcoinTestnetKey: 'Bitcoin Testnet',
    WalletEngineTestnetPreset.suiTestnetKey: 'Sui Testnet（账户功能）',
  };

  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _privateKeyController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _wordPrefixController = TextEditingController();
  final TextEditingController _solanaOwnerController = TextEditingController();
  final TextEditingController _solanaMintController = TextEditingController();

  String _chainKey = WalletEngineTestnetPreset.ethereumSepoliaKey;
  bool _busy = false;
  bool _revealMnemonic = false;
  bool _revealPrivateKey = false;
  String _status = 'Trust Wallet Core 已完成一次性初始化';
  CreatedWallet? _createdWallet;
  WalletAccount? _account;
  WatchOnlyWallet? _watchOnlyWallet;
  List<String> _wordSuggestions = const <String>[];
  SolanaTokenProgram _solanaTokenProgram = SolanaTokenProgram.token;
  String? _derivedAta;
  SolanaTokenAccount? _ataAccount;
  String _rpcResult = '尚未执行 RPC/API 调试操作。';

  @override
  void dispose() {
    _mnemonicController.dispose();
    _privateKeyController.dispose();
    _addressController.dispose();
    _wordPrefixController.dispose();
    _solanaOwnerController.dispose();
    _solanaMintController.dispose();
    unawaited(widget.engine.close());
    super.dispose();
  }

  Future<void> _run(
    String successMessage,
    Future<void> Function() operation,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '执行中…';
    });
    try {
      await operation();
      if (!mounted) return;
      setState(() => _status = successMessage);
    } catch (error) {
      if (!mounted) return;
      final message = error is WalletError
          ? '${error.errorCode}: ${error.message}'
          : error.toString();
      setState(() => _status = '失败：$message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifySelectedNetwork() async {
    await _run('网络身份检查已完成', () async {
      final identities = await widget.engine.verifyNetworkIdentities(
        chainKeys: <String>[_chainKey],
      );
      final identity = identities[_chainKey];
      if (!mounted) return;
      setState(() {
        _rpcResult = identity == null
            ? '${_chainLabels[_chainKey]} 当前没有可验证的链标识。'
            : 'configured=${identity.configured}\n'
                  'observed=${identity.observed}\n'
                  'matches=${identity.matches}';
      });
    });
  }

  Future<void> _runRpcProbe() async {
    await _run('只读 RPC 探针执行成功', () async {
      final session = widget.engine.session(_chainKey);
      final result = switch (session) {
        EvmChainSession() => await _probeEvm(session),
        SolanaChainSession() => await _probeSolana(session),
        TronChainSession() => await _probeTron(session),
        BitcoinChainSession() => await _probeBitcoin(session),
        SuiChainSession() => await _probeSui(session),
        _ => '当前 Session 没有配置示例探针。',
      };
      if (!mounted) return;
      setState(() => _rpcResult = result);
    });
  }

  Future<String> _probeEvm(EvmChainSession session) async {
    final block = await session.getBlockNumber();
    final gasPrice = await session.getGasPrice();
    return 'eth_blockNumber=$block\neth_gasPrice=$gasPrice wei';
  }

  Future<String> _probeSolana(SolanaChainSession session) async {
    final blockhash = await session.getLatestBlockhash();
    return 'getLatestBlockhash=$blockhash';
  }

  Future<String> _probeTron(TronChainSession session) async {
    final header = await session.getBlockHeader();
    return 'getnowblock.number=${header.number}\n'
        'timestamp=${header.timestamp}';
  }

  Future<String> _probeBitcoin(BitcoinChainSession session) async {
    final feeRate = await session.estimateFeeRate();
    return 'estimateFeeRate=$feeRate sat/vB';
  }

  Future<String> _probeSui(SuiChainSession session) async {
    final checkpoint = await session.getLatestCheckpointSequenceNumber();
    return 'latestCheckpoint=$checkpoint';
  }

  void _showConfigSnapshot() {
    final snapshot = WalletEngineConfigCodec.encode(widget.engine.config);
    setState(() {
      _rpcResult = const JsonEncoder.withIndent('  ').convert(snapshot);
      _status = '已通过公共 API 导出配置快照；运行时 RPC 凭证不会包含在其中';
    });
  }

  Future<void> _createWallet(int words) async {
    await _run('已创建 $words 词钱包；敏感信息仅保存在当前页面内存中', () async {
      final result = words == 12
          ? await widget.engine.createWallet12(
              chainKey: _chainKey,
              exposePrivateKey: true,
            )
          : await widget.engine.createWallet24(
              chainKey: _chainKey,
              exposePrivateKey: true,
            );
      if (!mounted) return;
      setState(() {
        _createdWallet = result;
        _account = result.wallet;
        _watchOnlyWallet = null;
        _revealMnemonic = false;
        _revealPrivateKey = false;
      });
    });
  }

  Future<void> _restoreWallet() async {
    final mnemonic = _mnemonicController.text.trim();
    await _run('助记词有效，账户派生成功', () async {
      if (!widget.engine.validateMnemonic(mnemonic)) {
        throw StateError('请输入有效的 12 或 24 词英文 BIP-39 助记词');
      }
      final result = await widget.engine.deriveAccount(
        chainKey: _chainKey,
        mnemonic: mnemonic,
        exposePrivateKey: true,
      );
      if (!mounted) return;
      setState(() {
        _createdWallet = null;
        _account = result;
        _watchOnlyWallet = null;
        _revealPrivateKey = false;
      });
    });
  }

  Future<void> _importPrivateKey() async {
    final privateKey = _privateKeyController.text.trim();
    await _run('私钥有效，账户导入成功', () async {
      final result = await widget.engine.importPrivateKey(
        chainKey: _chainKey,
        privateKey: privateKey,
        exposePrivateKey: true,
      );
      if (!mounted) return;
      setState(() {
        _createdWallet = null;
        _account = result;
        _watchOnlyWallet = null;
        _revealPrivateKey = false;
      });
    });
  }

  void _validatePrivateKey() {
    final valid = widget.engine.validatePrivateKey(
      chainKey: _chainKey,
      privateKey: _privateKeyController.text.trim(),
    );
    setState(() => _status = valid ? '私钥格式有效' : '私钥格式无效');
  }

  void _validateAddress() {
    final valid = widget.engine.validateAddress(
      chainKey: _chainKey,
      address: _addressController.text.trim(),
    );
    setState(() => _status = valid ? '地址格式有效' : '地址格式无效');
  }

  void _searchBip39Words() {
    final prefix = _wordPrefixController.text;
    final matches = Bip39WordList.english.wordsStartingWith(prefix, limit: 20);
    setState(() {
      _wordSuggestions = matches;
      _status = matches.isEmpty
          ? 'BIP-39 英文词库中没有匹配项'
          : '找到 ${matches.length} 个匹配词（最多显示 20 个）';
    });
  }

  void _deriveSolanaAta() {
    try {
      final address = widget.engine
          .sessionAs<SolanaChainSession>(
            WalletEngineTestnetPreset.solanaDevnetKey,
          )
          .deriveAssociatedTokenAddress(
            owner: _solanaOwnerController.text,
            mint: _solanaMintController.text,
            program: _solanaTokenProgram,
          );
      setState(() {
        _derivedAta = address;
        _ataAccount = null;
        _status = 'ATA 已在本地派生，没有发送 RPC 请求';
      });
    } catch (error) {
      final message = error is WalletError
          ? '${error.errorCode}: ${error.message}'
          : error.toString();
      setState(() => _status = '失败：$message');
    }
  }

  Future<void> _querySolanaAta() async {
    await _run('ATA 链上查询完成', () async {
      final session = widget.engine.sessionAs<SolanaChainSession>(
        WalletEngineTestnetPreset.solanaDevnetKey,
      );
      final address = session.deriveAssociatedTokenAddress(
        owner: _solanaOwnerController.text,
        mint: _solanaMintController.text,
        program: _solanaTokenProgram,
      );
      final account = await session.getAssociatedTokenAccount(
        owner: _solanaOwnerController.text,
        mint: _solanaMintController.text,
        program: _solanaTokenProgram,
      );
      if (!mounted) return;
      setState(() {
        _derivedAta = address;
        _ataAccount = account;
      });
    });
  }

  Future<void> _createWatchOnly() async {
    await _run('Watch-only 账户创建成功', () async {
      final result = widget.engine.createWatchOnly(
        chainKey: _chainKey,
        address: _addressController.text.trim(),
      );
      setState(() {
        _watchOnlyWallet = result;
        _createdWallet = null;
        _account = null;
      });
    });
  }

  void _clearSecrets() {
    _mnemonicController.clear();
    _privateKeyController.clear();
    setState(() {
      _createdWallet = null;
      _account = null;
      _revealMnemonic = false;
      _revealPrivateKey = false;
      _status = '敏感字段已从页面状态清除';
    });
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 已复制；请及时清理剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Engine Lab'),
        actions: <Widget>[
          IconButton(
            onPressed: _clearSecrets,
            tooltip: '清除敏感信息',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _noticeCard(),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('chain-selector'),
                      initialValue: _chainKey,
                      decoration: const InputDecoration(labelText: '测试网络'),
                      items: _chainLabels.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _chainKey = value;
                                _createdWallet = null;
                                _account = null;
                                _watchOnlyWallet = null;
                                _status = '已切换网络';
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    _rpcApiSection(),
                    const SizedBox(height: 16),
                    _section(
                      title: 'BIP-39 英文词库',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            '共 ${Bip39WordList.english.length} 个标准单词，'
                            '查询完全在本地完成。',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('bip39-prefix'),
                            controller: _wordPrefixController,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchBip39Words(),
                            decoration: InputDecoration(
                              labelText: '输入英文前缀，例如 ab',
                              suffixIcon: IconButton(
                                key: const Key('search-bip39'),
                                onPressed: _searchBip39Words,
                                tooltip: '查询词库',
                                icon: const Icon(Icons.search),
                              ),
                            ),
                          ),
                          if (_wordSuggestions.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _wordSuggestions
                                  .map(
                                    (word) => ActionChip(
                                      label: Text(word),
                                      onPressed: () {
                                        _wordPrefixController.text = word;
                                        setState(
                                          () => _status =
                                              '“$word”的词库索引：'
                                              '${Bip39WordList.english.indexOf(word)}',
                                        );
                                      },
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      title: '创建钱包',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          FilledButton.icon(
                            key: const Key('create-12'),
                            onPressed: _busy ? null : () => _createWallet(12),
                            icon: const Icon(Icons.add),
                            label: const Text('创建 12 词钱包'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('create-24'),
                            onPressed: _busy ? null : () => _createWallet(24),
                            icon: const Icon(Icons.add),
                            label: const Text('创建 24 词钱包'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      title: '助记词恢复',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _mnemonicController,
                            minLines: 2,
                            maxLines: 3,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: '12 / 24 词英文助记词',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.tonal(
                              onPressed: _busy ? null : _restoreWallet,
                              child: const Text('校验并派生账户'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      title: '私钥导入',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _privateKeyController,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: '链对应的私钥格式',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: _busy ? null : _validatePrivateKey,
                                child: const Text('仅校验'),
                              ),
                              FilledButton.tonal(
                                onPressed: _busy ? null : _importPrivateKey,
                                child: const Text('导入账户'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      title: '地址与 Watch-only',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _addressController,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: '钱包地址',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: _busy ? null : _validateAddress,
                                child: const Text('校验地址'),
                              ),
                              FilledButton.tonal(
                                onPressed: _busy ? null : _createWatchOnly,
                                child: const Text('创建 Watch-only'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      title: 'Solana Associated Token Account',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          DropdownButtonFormField<SolanaTokenProgram>(
                            initialValue: _solanaTokenProgram,
                            decoration: const InputDecoration(
                              labelText: 'Token Program',
                            ),
                            items: SolanaTokenProgram.values
                                .map(
                                  (program) =>
                                      DropdownMenuItem<SolanaTokenProgram>(
                                        value: program,
                                        child: Text(
                                          program == SolanaTokenProgram.token
                                              ? 'SPL Token'
                                              : 'Token-2022',
                                        ),
                                      ),
                                )
                                .toList(growable: false),
                            onChanged: _busy
                                ? null
                                : (program) {
                                    if (program == null) return;
                                    setState(() {
                                      _solanaTokenProgram = program;
                                      _derivedAta = null;
                                      _ataAccount = null;
                                    });
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('solana-ata-owner'),
                            controller: _solanaOwnerController,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Owner 地址',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('solana-ata-mint'),
                            controller: _solanaMintController,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Mint 地址',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: _busy ? null : _deriveSolanaAta,
                                child: const Text('本地派生 ATA'),
                              ),
                              FilledButton.tonal(
                                onPressed: _busy ? null : _querySolanaAta,
                                child: const Text('查询链上 ATA'),
                              ),
                            ],
                          ),
                          if (_derivedAta case final address?) ...<Widget>[
                            const SizedBox(height: 12),
                            _valueRow('ATA 地址', address),
                            Text(
                              _ataAccount == null
                                  ? '链上账户：不存在或尚未查询'
                                  : '链上账户：存在 · '
                                        '余额 ${_ataAccount!.tokenAmount.amount} · '
                                        '状态 ${_ataAccount!.state.name}',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _resultCard(),
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: <Widget>[
                            if (_busy) ...<Widget>[
                              const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(_status, key: const Key('status')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noticeCard() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '仅用于本地集成测试。钱包、助记词和私钥不会写入磁盘，'
          '但复制操作会进入系统剪贴板；请勿使用真实资产或生产助记词。',
        ),
      ),
    );
  }

  Widget _rpcApiSection() {
    return _section(
      title: 'RPC / API 调试',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '调用当前测试链的只读 RPC，并展示 wallet_engine 输出的结构化日志。'
            '请求/响应 body 默认关闭，日志不会包含助记词、私钥或 RPC 凭证。',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.tonalIcon(
                key: const Key('verify-network'),
                onPressed: _busy ? null : _verifySelectedNetwork,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('验证网络身份'),
              ),
              FilledButton.icon(
                key: const Key('rpc-probe'),
                onPressed: _busy ? null : _runRpcProbe,
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('执行只读 RPC'),
              ),
              OutlinedButton.icon(
                key: const Key('config-snapshot'),
                onPressed: _busy ? null : _showConfigSnapshot,
                icon: const Icon(Icons.data_object),
                label: const Text('查看配置快照'),
              ),
              OutlinedButton.icon(
                key: const Key('clear-sdk-logs'),
                onPressed: widget.logStore.clearEntries,
                icon: const Icon(Icons.clear_all),
                label: const Text('清空日志'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('API 结果', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            key: const Key('rpc-result'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(_rpcResult),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'SDK 日志（最近 12 条）',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              ValueListenableBuilder<List<WalletLogEvent>>(
                valueListenable: widget.logStore,
                builder: (context, events, _) => Text('${events.length}/100'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<List<WalletLogEvent>>(
            valueListenable: widget.logStore,
            builder: (context, events, _) {
              if (events.isEmpty) {
                return const Text(
                  '暂无日志。执行网络验证、RPC、账户或配置 API 后会显示。',
                  key: Key('sdk-log-empty'),
                );
              }
              final visible = events.reversed.take(12).toList(growable: false);
              return Column(
                key: const Key('sdk-log-list'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: visible
                    .map(
                      (event) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          const JsonEncoder().convert(event.toDiagnosticMap()),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final account = _account;
    final watchOnly = _watchOnlyWallet;
    if (account == null && watchOnly == null) {
      return _section(title: '结果', child: const Text('尚未创建、恢复或导入账户。'));
    }

    return _section(
      title: '结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _valueRow('地址', account?.address ?? watchOnly!.address),
          if (account != null) ...<Widget>[
            _valueRow('来源', account.source.name),
            _valueRow('派生路径', account.derivationPath),
            _secretRow(
              label: '私钥',
              value: account.privateKey ?? '默认未导出',
              revealed: _revealPrivateKey,
              onToggle: () {
                setState(() => _revealPrivateKey = !_revealPrivateKey);
              },
            ),
          ],
          if (_createdWallet case final created?)
            _secretRow(
              label: '助记词（${created.wordCount.value} 词）',
              value: created.mnemonic,
              revealed: _revealMnemonic,
              onToggle: () {
                setState(() => _revealMnemonic = !_revealMnemonic);
              },
            ),
        ],
      ),
    );
  }

  Widget _valueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _secretRow({
    required String label,
    required String value,
    required bool revealed,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(revealed ? value : '••••••••••••••••••••••••'),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton.icon(
                onPressed: onToggle,
                icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
                label: Text(revealed ? '隐藏' : '显示'),
              ),
              TextButton.icon(
                onPressed: () => _copy(label, value),
                icon: const Icon(Icons.copy),
                label: const Text('复制'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
