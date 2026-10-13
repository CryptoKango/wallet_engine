# wallet_engine

[English](README.md) | 简体中文

当前正式维护的应用目标平台为 Android、iOS 和 macOS。CI 保证范围及尽力支持的
平台请参阅 [`SUPPORTED_PLATFORMS.md`](SUPPORTED_PLATFORMS.md)。

`wallet_engine` 是一个配置驱动的多链钱包引擎，负责 RPC 访问、手续费估算、交易
构建、签名原语、广播和回执查询等通用链能力。

它不负责应用业务流程、项目专属合约、账户存储、认证 UI 或私钥持久化。

原生签名通过基于官方 Apache-2.0 Trust Wallet Core 源码构建的自有最小化桥接层
完成。所有内置签名器和 HD 账户派生均使用该桥接层，不分发第三方 Dart binding
或二进制包装器。Apple 和 Android 制品均已固定版本、打包，并通过以下命令校验：

```shell
dart run tool/verify_wallet_core_lock.dart --release
```

Android 正式生产发布仍要求在受维护的真机或模拟器镜像上运行自有桥接层的向量
测试套件。

## 架构

```text
业务功能（Feature）
       |
应用服务（Application services）
       |
项目钱包/合约适配层
       |
wallet_engine
  |- 链适配器
  |- RPC 节点池
  |- 手续费估算器
  |- 交易构建器
  |- 签名原语
  |- 广播器
  `- 回执查询器
```

宿主应用负责获取、验证并持久化最后一个有效配置。`wallet_engine` 接收不可变配置
快照，内部仅在内存中保存运行时状态。

## 初始化引擎

使用自有原生签名器时，应在 App 启动阶段初始化一次 runtime，并将同一个实例注入
各签名器：

```dart
final sdkLogger = WalletLogger(
  minimumLevel: WalletLogLevel.debug,
  sink: (event) => debugPrint('[wallet_engine] ${event.toDiagnosticMap()}'),
);

final nativeBridge = FfiWalletCoreNativeBridge.open();
final nativeRuntime = WalletCoreNativeRuntime(
  bridge: nativeBridge,
  logger: sdkLogger,
);
await nativeRuntime.initialize();

final evmSigner = WalletCoreEvmSigner(
  privateKeyAccess: secureKeyAccess,
  runtime: nativeRuntime,
);
```

该路径要求使用原生发布流水线中记录并校验过的平台制品。初始化会验证 ABI、上游
发布版本/提交，以及原生 SHA-256 已知答案测试。任何业务操作都不会懒加载或重复
初始化 runtime。

```dart
final config = WalletEngineConfig(
  revision: 1,
  version: '2026-10-12.1',
  chains: [
    WalletChainConfig(
      key: 'ethereum',
      family: ChainFamily.evm,
      network: 'mainnet',
      chainId: '1',
      nativeSymbol: 'ETH',
      nativeDecimals: 18,
      rpcPool: RpcPoolConfig(
        endpoints: [
          RpcEndpoint.parse('https://example.invalid'),
        ],
      ),
    ),
  ],
);

final engine = WalletEngine(
  config: config,
  adapters: walletEngineDefaultAdapters(),
  transport: DioRpcTransport(
    credentialProvider: projectCredentialProvider,
  ),
  logger: sdkLogger,
  walletAccounts: WalletCoreAccountService(runtime: nativeRuntime),
);
await engine.verifyNetworkIdentities();
final ethereum = engine.sessionAs<EvmChainSession>('ethereum');

final fee = await ethereum.estimateFee(
  const EvmCall(to: '0xRecipient'),
);

final unsigned = await ethereum.prepareTransaction(
  EvmTransactionRequest(
    from: sender,
    to: contractAddress,
    data: encodedProjectContractCall,
  ),
);

final result = await ethereum.signAndBroadcast(
  unsigned,
  signer: WalletCoreEvmSigner(
    privateKeyAccess: projectPrivateKeyAccess,
    runtime: nativeRuntime,
  ),
);

final receipt = await ethereum.waitForTransactionReceipt(
  result.transactionHash,
  confirmations: 2,
  policy: const TransactionConfirmationPolicy(
    timeout: Duration(minutes: 3),
    pollInterval: Duration(seconds: 2),
  ),
);
```

默认 EVM 适配器提供通用 EVM JSON-RPC 调用、余额与 nonce 查询、Gas 估算、
EIP-1559/Legacy 手续费建议、已签名交易广播和回执查询。项目专属 ABI 与合约封装
仍应放在宿主项目的钱包包内。

`EvmTransactionSigner` 是交易构建与签名之间的安全边界。内置 Trust Wallet Core
签名器使用同步、短生命周期的 `PrivateKeyAccess` 回调。UKey、硬件钱包和 MPC
集成应直接实现 `EvmTransactionSigner`，确保私钥不会进入 RPC 层。

Trust Wallet Core 必须在应用启动时初始化一次。签名方法只验证初始化状态，绝不会
在调用时懒初始化原生 runtime：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final walletCore = WalletCoreNativeRuntime(
    bridge: FfiWalletCoreNativeBridge.open(),
  );
  await walletCore.initialize();
  runApp(const WalletApp());
}
```

若在启动初始化完成前调用内置签名器，将抛出
`WalletErrorCode.signingRuntimeNotInitialized`。

## 钱包创建与恢复

引擎提供 12 词和 24 词英文 BIP-39 钱包创建 API。请使用已配置的 `chainKey`，
确保 Bitcoin Testnet 等网络敏感地址按正确网络编码：

```dart
final wallet12 = await engine.createWallet12(chainKey: 'ethereum');
final wallet24 = await engine.createWallet24(chainKey: 'ethereum');

final recoveryPhrase = wallet24.mnemonic;
final address = wallet24.wallet.address;
assert(wallet24.wallet.privateKey == null); // 默认安全行为

final valid = engine.validateMnemonic(recoveryPhrase);
final restored = await engine.deriveAccount(
  chainKey: 'ethereum',
  mnemonic: recoveryPhrase,
  account: 0,
);

// 高风险兼容导出。建议改为在受保护存储内派生并实现 PrivateKeyAccess。
final exported = await engine.deriveAccount(
  chainKey: 'ethereum',
  mnemonic: recoveryPhrase,
  exposePrivateKey: true,
);
final privateKey = exported.privateKey!;

final addressIsValid = engine.validateAddress(
  chainKey: 'ethereum',
  address: address,
);

final watchOnly = engine.createWatchOnly(
  chainKey: 'ethereum',
  address: address,
);

final privateKeyIsValid = engine.validatePrivateKey(
  chainKey: 'ethereum',
  privateKey: privateKey,
);

final imported = await engine.importPrivateKey(
  chainKey: 'ethereum',
  privateKey: privateKey,
);
```

`CreatedWallet.mnemonic` 仅在创建调用中返回。恢复和账户派生返回的
`WalletAccount` 不会再次返回助记词。创建、派生和导入 API 默认都将私钥字段设为
`null`；调用方必须显式设置 `exposePrivateKey: true` 才能导出。Dart 字符串无法
安全擦除，因此兼容导出的私钥必须立即转移到平台受保护存储并丢弃临时值。签名集成
应将密钥字节保持在 `PrivateKeyAccess` 边界内。引擎不会缓存或持久化助记词、
passphrase 或私钥，其 `toString()` 表示也会进行脱敏。

对于不需要 RPC 配置的工具，可直接使用：

```dart
WalletCoreAccountService(runtime: nativeRuntime)
```

runtime 仍必须在应用启动时初始化一次。

规范的英文 BIP-39 词库也通过不可变的进程内 API 提供，可用于恢复输入和自动补全：

```dart
final english = Bip39WordList.english;
final allWords = english.words; // 不可变，共 2,048 个词
final firstWord = english.wordAt(0); // abandon
final wordIndex = english.indexOf('zoo'); // 2047
final isKnown = english.contains('ability');
final suggestions = english.wordsStartingWith('ab', limit: 10);
```

查询辅助方法会去除首尾空白并忽略字母大小写，返回值始终采用规范的小写拼写。词库
API 不执行 RPC、不初始化原生 runtime，也不进行缓存或持久化。

私钥导入、地址验证和观察钱包目前覆盖具有生产适配器的链族：EVM、Solana、Sui、
TRON 和 Bitcoin。不支持的链族会返回稳定错误码 `account.unsupportedChain`，不会
静默套用其他链的密钥或地址规则。Bitcoin 验证会识别网络，在 Testnet 链配置下会
拒绝 Mainnet 地址。

配置持久化明确由宿主应用负责。

配置快照使用稳定、兼容 JSON 的 schema，宿主可验证并缓存实际应用的完整载荷：

```dart
final json = WalletEngineConfigCodec.encode(config);
final restored = WalletEngineConfigCodec.decode(json);
```

该 schema 明确排除运行时 RPC 凭据。引擎会在创建和更新阶段拒绝过期快照。配置
下载、签名验证、跨应用重启的回滚策略，以及最后有效配置持久化仍由宿主负责。

端点验证会拒绝 URL user-info、敏感查询参数和敏感静态 Header 中的凭据。明文
`http`、`tcp` 和 `electrum` 端点必须显式设置 `allowInsecureTransport: true`，
且只应在明确可信的本地开发环境中使用。运行时密钥应通过
`RpcCredentialProvider` 提供。

## SDK 诊断日志

将同一个 `WalletLogger` 传给原生 runtime 和引擎，即可观察完整 SDK 生命周期。
未传 logger 时，通用 SDK 日志默认关闭。Logger 支持 `debug`、`info`、`warning`
和 `error` 最低级别，并会为原生初始化、账户派生、签名、配置变更、Session
生命周期、RPC 尝试和引擎关闭生成结构化 `WalletLogEvent`。

```dart
final sdkLogger = WalletLogger(
  minimumLevel: kDebugMode
      ? WalletLogLevel.debug
      : WalletLogLevel.warning,
  sink: (event) {
    final diagnostic = event.toDiagnosticMap();
    debugPrint('[wallet_engine] $diagnostic');
    // 可选择将 warning/error 事件上报到应用遥测系统。
  },
);
```

Logger sink 的异常会被隔离，不会改变钱包执行结果。事件不会包含私钥、助记词、
passphrase、凭据、原始异常或堆栈。敏感上下文字段会递归脱敏，消息长度也有限制。

### RPC 请求与响应体

可通过配置将 RPC 请求体和响应体附加到结构化日志事件中。两个开关默认均为
`false`：

```dart
final config = WalletEngineConfig(
  revision: 1,
  version: '2026-10-12.1',
  rpcLogging: const RpcLoggingConfig(
    includeRequestBody: true,
    includeResponseBody: true,
    maxBodyCharacters: 8192,
    bodyMode: RpcLogBodyMode.redacted,
  ),
  chains: chains,
);

final engine = WalletEngine(
  config: config,
  adapters: walletEngineDefaultAdapters(),
  transport: DioRpcTransport(),
  logger: sdkLogger,
);
```

Body 日志可能暴露地址、calldata、已签名交易和节点响应，只能在受控调试环境中
开启。端点 URL、Header 和凭据永远不会附加到日志事件。过长 Body 会按照
`maxBodyCharacters` 截断，已知密钥和广播载荷默认脱敏。`RpcLogBodyMode.full`
有意设计为不安全模式，只能用于隔离的开发工具。

为兼容已有集成，旧版 `RpcLogSink` 回调仍然保留；新应用应使用统一的
`WalletLogger` 事件流。

## 金额精度

公开余额、转账金额和面向用户的手续费统一使用 `Decimal`。RPC 与签名协议仍要求
整数基本单位，因此仅在协议边界通过 `AmountCodec` 转换：

```dart
final amount = Decimal.parse('0.125');
final baseUnits = AmountCodec.toBaseUnits(amount, decimals: 18);
final displayAmount = AmountCodec.fromBaseUnits(baseUnits, decimals: 18);
```

如果金额的小数位超过链支持范围，会直接拒绝；`wallet_engine` 绝不会静默舍入转账
金额。要求整数费率的协议只会在最终编码步骤显式向上取整。

## 错误处理

所有公开引擎异常均实现 `WalletError`。公开错误码集中定义在 `WalletErrorCode`
枚举中，并通过稳定的 `value` 序列化。应用服务可以使用强类型 `publicCode`，也可
将 `errorCode` 与 `WalletErrorProtocol.version` 一同持久化。当前错误协议版本为
`1`。

已存在的序列化值永远不会被重命名或复用。新增错误码属于向后兼容；改变现有错误码
的含义则要求提升错误协议主版本。对于由更新包版本引入的未知错误码，
`WalletErrorProtocol.tryParse` 会安全返回 `null`。

`retryable` 为 HTTP、JSON-RPC、签名和链适配器提供统一的重试信号：

```dart
try {
  await ethereum.broadcast(signedTransaction);
} on WalletError catch (error) {
  logger.warning(error.toDiagnosticMap());
  if (error.publicCode == WalletErrorCode.rpcTransportTimeout) {
    // 可选的错误码专项处理。
  }
  if (error.retryable) {
    // 应用宿主的重试策略。
  }
}
```

在可能抛出第三方或 Dart 异常的依赖边界，可使用 `WalletErrorNormalizer.guard`。
归一化错误会保留原始 cause 供本地诊断，但安全诊断信息和 `toString()` 会明确排除
cause、堆栈、端点 URL 和凭据。只有显式开启时，RPC Body 才会出现在
`RpcLogEvent` 中。

## 内置测试网络

`WalletEngineTestnetPreset.create()` 提供可覆盖的开发配置，包含 Ethereum
Sepolia、Solana Devnet、TRON Nile 和 Bitcoin Testnet：

```dart
final config = WalletEngineTestnetPreset.create(
  revision: 1,
  rpcLogging: const RpcLoggingConfig(
    includeRequestBody: true,
    includeResponseBody: true,
  ),
  // 需要时替换共享公共基础设施。
  ethereumEndpoints: <RpcEndpoint>[
    RpcEndpoint.parse(projectSepoliaRpc),
  ],
);

final engine = WalletEngine(
  config: config,
  adapters: walletEngineDefaultAdapters(),
  transport: DioRpcTransport(),
);
final sepolia = engine.sessionAs<EvmChainSession>(
  WalletEngineTestnetPreset.ethereumSepoliaKey,
);
```

内置端点是公共、共享且有速率限制的基础设施，只适用于开发和冒烟测试，不应在生产
环境或确定性 CI 中使用。每个网络方法都支持覆盖端点。

`RpcRetryConfig.maxAttempts` 表示总尝试次数上限，不是不同端点的数量。健康的备用
端点会立即尝试；节点池耗尽后，重试采用有界指数退避。HTTP `Retry-After` 最多只
会等待 `maxBackoff`，避免节点无限期挂起调用方。

默认测试套件有意不包含 Sui，因为 Foundation Fullnode 已禁用弃用的 JSON-RPC
API。生产应用必须通过 `SuiGateway` 注入当前的 gRPC v2 实现：

```dart
final adapters = walletEngineDefaultAdapters(
  sui: SuiChainAdapter(
    gatewayFactory: (config, rpc) => ProjectSuiGrpcGateway(config),
  ),
);
```

Gateway 拥有自己的 Channel，并随引擎关闭。其操作契约将余额和持有 Coin 查询映射
到 `StateService`，将交易查询和链身份映射到 `LedgerService`，将 dry-run 与
提交映射到 `TransactionExecutionService`。`LegacySuiJsonRpcGateway` 仅为明确
保证旧协议兼容的供应商保留，不是推荐的生产路径。Provenance 未包含在测试套件中，
因为 `wallet_engine` 目前只提供其签名器，尚无 RPC 链适配器。

## Solana 关联代币账户

Solana Session 为原始 SPL Token 程序和 Token-2022 提供规范 ATA 操作。地址派生
在本地完成，不需要 RPC 或 Trust Wallet Core 初始化：

```dart
final solana = engine.sessionAs<SolanaChainSession>('solana-devnet');

final ata = solana.deriveAssociatedTokenAddress(
  owner: ownerAddress,
  mint: mintAddress,
  program: SolanaTokenProgram.token,
);

final account = await solana.getAssociatedTokenAccount(
  owner: ownerAddress,
  mint: mintAddress,
);
final exists = await solana.associatedTokenAccountExists(
  owner: ownerAddress,
  mint: mintAddress,
);
final exactBalance = await solana.getTokenAccountBalance(ata);
final accounts = await solana.getTokenAccountsByOwner(
  owner: ownerAddress,
  program: SolanaTokenProgram.token2022,
);
final total = await solana.getTokenBalance(
  owner: ownerAddress,
  mint: mintAddress,
);
```

`getTokenBalance` 会聚合所有匹配账户，而不是假定第一个 Token Account 就是 ATA。
为保持向后兼容，`getTokenAccountAddress` 仍然可用，但明确只返回第一个匹配项。
对于 PDA Owner，派生或查询规范 ATA 时需显式设置 `allowOwnerOffCurve: true`。

## 生产接入检查清单

- 创建签名器前初始化 Trust Wallet Core。
- 在宿主中解码、验证并持久化已签名配置快照。
- 启用交易提交前调用 `verifyNetworkIdentities()`。
- 运行时注入 RPC 凭据，绝不在配置快照中持久化。
- 生产 Sui 访问必须注入 gRPC v2 `SuiGateway`。
- 生产日志中关闭 RPC Body。
- 调用 `waitForTransactionReceipt` 时设置产品级超时和所需确认数。
- 每次变更运行确定性单元测试，发布前单独运行已认证的测试网冒烟测试。
- 应用 runtime 销毁时关闭引擎。

当 transport 实现 `ClosableRpcTransport` 时，引擎默认拥有并关闭它。只有宿主明确在
多个引擎间共享同一个 transport 并自行管理生命周期时，才设置
`closeTransportOnClose: false`。

可运行以下命令对内置公共测试网执行只读检查：

```shell
dart run tool/testnet_smoke.dart
```

公共端点存在速率限制且可能临时不可用，因此该检查应与确定性 CI 分离。

## Codex 接入 Skill

仓库内提供了可分发的 Codex Skill：
[`skills/wallet-engine-integration`](skills/wallet-engine-integration)。将该目录安装或
复制到接入团队的 Codex Skills 集合后，在集成、测试或排查本包时调用
`$wallet-engine-integration`。该 Skill 会引导 Agent 使用当前公开 API、遵守链能力
边界和安全规则，并执行对应的生产校验命令。

示例提示词：

- `使用 $wallet-engine-integration 将 wallet_engine 接入这个 Flutter App。`
- `使用 $wallet-engine-integration 检查这个 App 的钱包集成是否满足生产要求。`
- `使用 $wallet-engine-integration 排查这个 RPC 或签名故障。`

## 本地示例应用

[`example/`](example/) 下的 Flutter 应用会在启动时初始化一次 Trust Wallet Core，
并提供 12/24 词钱包创建、助记词恢复、私钥导入、地址验证和观察钱包的本地 UI。
它还提供只读多链 RPC 探针、网络身份校验、配置快照查看和内存结构化 SDK 日志
查看器。敏感材料只保留在内存中，不会写入日志或本地存储。

```shell
cd example
flutter pub get
flutter run -d <ios-or-android-device-id>
```

示例支持 Android arm64 和 iOS Target。只能使用一次性测试密钥；复制敏感信息仍会
将其写入操作系统剪贴板。

## 已实现协议

| 协议 | RPC 与交易能力 | 签名能力 |
| --- | --- | --- |
| EVM | Decimal 余额、调用、nonce、Gas、Legacy/EIP-1559 手续费、构建、广播、回执 | 交易、个人消息、EIP-712/Hyperliquid |
| Solana | 余额、SPL 余额/账户、blockhash、优先费、租金、广播、回执 | SOL 和 SPL/Token-2022 转账 |
| Sui | 余额、分页 Coin、Gas Price/dry-run、广播、回执 | 原始 JSON、`paySui` 和 `pay` |
| TRON | 余额、区块头、原生/合约构建、常量调用、费用计划、广播、回执 | 精确 `raw_data` 字节和序列化交易组装 |
| Bitcoin | Electrum UTXO、余额、费率、广播、确认查询 | P2WPKH 转账和找零密钥输入 |
| Provenance | 仅交易签名；源包中没有链上客户端 | Cosmos-SDK JSON bank-send 签名 |

其余 `ChainFamily` 值是扩展点，并不表示已经实现适配器。Aptos、TON、XRP、
Cardano、Cosmos、Polkadot 和 NEAR 在源包中只有钱包派生支持；应在产品工作流确实
需要时再增加对应 RPC/交易适配器。

## 许可证

`wallet_engine` 采用 Apache License 2.0，完整条款见 [`LICENSE`](LICENSE)。
第三方声明及源码位置记录在
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
