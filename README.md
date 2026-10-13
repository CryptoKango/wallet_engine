# wallet_engine

English | [简体中文](README.zh-CN.md)

Maintained application targets are Android, iOS, and macOS. See
`SUPPORTED_PLATFORMS.md` for the CI guarantees and best-effort targets.

`wallet_engine` is a configuration-driven, multi-chain wallet engine. It owns
generic chain capabilities such as RPC access, fee estimation, transaction
building, signing primitives, broadcasting, and receipt lookup.

It does not own application workflows, project-specific contracts, account
storage, authentication UI, or private-key persistence.

Native signing uses an owned, minimal bridge built from the official
Apache-2.0 Trust Wallet Core source. All bundled signers plus HD account
derivation use that bridge; no third-party Dart binding or binary wrapper is
shipped. Apple and Android artifacts are pinned, packaged, and verified by
`dart run tool/verify_wallet_core_lock.dart --release`. Android production
rollout still requires the owned-bridge vector suite on a maintained device or
emulator image.

## Architecture

```text
Application features
       |
Application services
       |
Project wallet/contract adapter
       |
wallet_engine
  |- chain adapters
  |- RPC pools
  |- fee estimators
  |- transaction builders
  |- signing primitives
  |- broadcasters
  `- receipt providers
```

The host application fetches, validates, and persists its last-known-good
configuration. `wallet_engine` receives an immutable configuration snapshot
and keeps only runtime state in memory.

## Initializing the engine

For the owned native signer, initialize one runtime during App startup and
inject that same instance into signers:

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

This path requires a verified platform artifact recorded by the native release
pipeline. Initialization validates its ABI, upstream release/commit, and a
native SHA-256 known-answer test. It never initializes lazily per operation.

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

The first adapter provides generic EVM JSON-RPC calls, balance and nonce
queries, gas estimation, EIP-1559/legacy fee suggestions, signed transaction
broadcasting, and receipt lookup. Project-specific ABI and contract wrappers
remain in the host project's wallet package.

`EvmTransactionSigner` is the security boundary between transaction building
and signing. The bundled Trust Wallet Core signer uses a synchronous,
short-lived `PrivateKeyAccess` callback. UKey, hardware-wallet, and MPC
integrations should implement `EvmTransactionSigner` directly, so no private
key enters the RPC layer.

Trust Wallet Core must be initialized once during application startup. Signing
methods only verify this state and never initialize the native runtime lazily:

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

Calling a bundled signer before startup initialization completes throws
`WalletErrorCode.signingRuntimeNotInitialized`.

## Wallet creation and recovery

The engine exposes 12- and 24-word English BIP-39 wallet creation APIs. Use a
configured chain key so network-sensitive addresses, such as Bitcoin testnet,
are encoded for the correct network:

```dart
final wallet12 = await engine.createWallet12(chainKey: 'ethereum');
final wallet24 = await engine.createWallet24(chainKey: 'ethereum');

final recoveryPhrase = wallet24.mnemonic;
final address = wallet24.wallet.address;
assert(wallet24.wallet.privateKey == null); // safe default

final valid = engine.validateMnemonic(recoveryPhrase);
final restored = await engine.deriveAccount(
  chainKey: 'ethereum',
  mnemonic: recoveryPhrase,
  account: 0,
);

// High-risk compatibility export. Prefer deriving inside protected storage
// and implementing PrivateKeyAccess instead.
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

`CreatedWallet.mnemonic` is returned only by a creation call. Recovery and
account derivation return `WalletAccount` without echoing the mnemonic.
Private-key fields are `null` by default for create, derive, and import APIs;
the caller must explicitly opt in with `exposePrivateKey: true`. Dart strings
cannot be securely erased, so compatibility exports must be moved immediately
into platform-protected storage and discarded. Signing integrations should
keep bytes behind `PrivateKeyAccess`. The engine never caches or persists
mnemonics, passphrases, or private keys, and their `toString()` representations
are redacted.

For tools that do not need RPC configuration, use
`WalletCoreAccountService(runtime: nativeRuntime)` directly. The runtime must
still be initialized once at application startup.

The canonical English BIP-39 word list is also available as an immutable,
process-local API for recovery input and autocomplete:

```dart
final english = Bip39WordList.english;
final allWords = english.words; // immutable, 2,048 entries
final firstWord = english.wordAt(0); // abandon
final wordIndex = english.indexOf('zoo'); // 2047
final isKnown = english.contains('ability');
final suggestions = english.wordsStartingWith('ab', limit: 10);
```

Lookup helpers trim whitespace and ignore letter case. Returned words always
use their canonical lowercase spelling. The word-list API performs no RPC,
native-runtime initialization, caching, or persistent storage.

Private-key import, address validation, and watch-only accounts currently cover
the chain families with production adapters: EVM, Solana, Sui, TRON, and
Bitcoin. Unsupported families fail with the stable
`account.unsupportedChain` code instead of silently applying another chain's
key or address rules. Bitcoin validation is network-aware and rejects a
mainnet address when used with a testnet chain configuration.

Configuration persistence deliberately remains in the host application.

Configuration snapshots use a stable JSON-compatible schema so a host can
verify and cache the exact payload it applies:

```dart
final json = WalletEngineConfigCodec.encode(config);
final restored = WalletEngineConfigCodec.decode(json);
```

The schema deliberately excludes runtime RPC credentials. The engine rejects
expired snapshots at creation and update time. Downloading configuration,
signature verification, rollback policy across application restarts, and
last-known-good persistence remain host responsibilities.

Endpoint validation rejects credentials in URL user-info, sensitive query
parameters, and sensitive static headers. Clear-text `http`, `tcp`, and
`electrum` endpoints require `allowInsecureTransport: true` and should be
limited to explicitly trusted local development environments. Runtime secrets
belong in `RpcCredentialProvider`.

## SDK diagnostics

Pass the same `WalletLogger` to the native runtime and engine to observe the
complete SDK lifecycle. Omitting it disables general SDK logs. The logger
supports `debug`, `info`, `warning`, and `error` minimum levels and emits
structured `WalletLogEvent` values for native initialization, account
derivation, signing, configuration changes, session lifecycle, RPC attempts,
and engine shutdown.

```dart
final sdkLogger = WalletLogger(
  minimumLevel: kDebugMode
      ? WalletLogLevel.debug
      : WalletLogLevel.warning,
  sink: (event) {
    final diagnostic = event.toDiagnosticMap();
    debugPrint('[wallet_engine] $diagnostic');
    // Optionally forward warning/error events to application telemetry.
  },
);
```

Logger sink failures are isolated and never change wallet execution. Events
exclude private keys, mnemonics, passphrases, credentials, raw exceptions, and
stack traces. Sensitive context fields are recursively redacted and messages
are length limited.

### RPC request and response bodies

RPC request and response bodies can be attached to structured log events via
configuration. Both switches default to `false`:

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

Body logging may expose addresses, calldata, signed transactions, and node
responses. Enable it only in controlled debugging environments. Endpoint URLs,
headers, and credentials are never attached to log events. Oversized bodies
are truncated according to `maxBodyCharacters`. Known secrets and broadcast
payloads are redacted by default. `RpcLogBodyMode.full` is intentionally unsafe
and should be limited to isolated developer tooling.

The legacy `RpcLogSink` callback remains available for existing integrations,
but new applications should consume the unified `WalletLogger` stream.

## Amount precision

Public balances, transfer amounts, and user-facing fees use `Decimal`. RPC and
signing protocols still require integer base units, so conversion happens only
at the protocol boundary through `AmountCodec`:

```dart
final amount = Decimal.parse('0.125');
final baseUnits = AmountCodec.toBaseUnits(amount, decimals: 18);
final displayAmount = AmountCodec.fromBaseUnits(baseUnits, decimals: 18);
```

An amount with more fractional digits than the chain supports is rejected;
wallet_engine never silently rounds transfer amounts. Protocols that require
an integer fee rate use explicit upward rounding at their final encoding step.

## Error handling

All public engine exceptions implement `WalletError`. Public codes are defined
centrally by the `WalletErrorCode` enum and serialized through its stable
`value`. Application services can use the strongly typed `publicCode`, or
persist `errorCode` together with `WalletErrorProtocol.version`. The current
protocol version is `1`.

Existing serialized values are never renamed or reused. Adding a code is
backward compatible; changing the meaning of an existing code requires a new
major error protocol version. `WalletErrorProtocol.tryParse` safely returns
`null` for codes introduced by newer package versions.

`retryable` provides a single retry signal across HTTP, JSON-RPC, signing, and
chain adapters:

```dart
try {
  await ethereum.broadcast(signedTransaction);
} on WalletError catch (error) {
  logger.warning(error.toDiagnosticMap());
  if (error.publicCode == WalletErrorCode.rpcTransportTimeout) {
    // Optional code-specific handling.
  }
  if (error.retryable) {
    // Apply the application retry policy.
  }
}
```

`WalletErrorNormalizer.guard` is available at dependency boundaries that may
throw third-party or Dart exceptions. Normalized errors retain their original
cause for local diagnosis, but safe diagnostics and `toString()` deliberately
exclude causes, stack traces, endpoint URLs, and credentials. RPC bodies appear
only on `RpcLogEvent` when explicitly enabled.

## Built-in test networks

`WalletEngineTestnetPreset.create()` provides an overridable development suite
for Ethereum Sepolia, Solana Devnet, TRON Nile, and Bitcoin Testnet:

```dart
final config = WalletEngineTestnetPreset.create(
  revision: 1,
  rpcLogging: const RpcLoggingConfig(
    includeRequestBody: true,
    includeResponseBody: true,
  ),
  // Replace shared public infrastructure when required.
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

The bundled endpoints are public, shared, and rate-limited. They are intended
for development and smoke tests, not production or deterministic CI. Every
network method accepts endpoint overrides.

`RpcRetryConfig.maxAttempts` is the total attempt limit, not the number of
distinct endpoints. Healthy alternate endpoints are tried immediately; after
the pool has been exhausted, retries use bounded exponential backoff. HTTP
`Retry-After` is honored up to `maxBackoff` so a node cannot suspend the caller
indefinitely.

Sui is intentionally excluded from the default suite because Foundation
fullnodes have disabled the deprecated JSON-RPC API. Production applications
must inject a current gRPC v2 implementation through `SuiGateway`:

```dart
final adapters = walletEngineDefaultAdapters(
  sui: SuiChainAdapter(
    gatewayFactory: (config, rpc) => ProjectSuiGrpcGateway(config),
  ),
);
```

The gateway owns its channel and is closed with the engine. Its operation
contract maps balance and owned-coin queries to `StateService`, transaction
lookup and chain identity to `LedgerService`, dry-run and submission to
`TransactionExecutionService`. `LegacySuiJsonRpcGateway` is retained only for
providers that explicitly guarantee legacy compatibility; it is not the
recommended production path. Provenance is not included because wallet_engine
currently provides its signer but no RPC chain adapter.

## Solana associated token accounts

The Solana session exposes canonical ATA operations for both the original SPL
Token program and Token-2022. Address derivation is local and does not require
RPC or Trust Wallet Core initialization:

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

`getTokenBalance` aggregates every matching account rather than assuming the
first token account is the ATA. `getTokenAccountAddress` remains available for
backward compatibility and explicitly returns only the first match. For PDA
owners, opt in with `allowOwnerOffCurve: true` when deriving or querying the
canonical ATA.

## Production integration checklist

- Initialize Trust Wallet Core before creating signers.
- Decode, verify, and persist a signed configuration snapshot in the host.
- Call `verifyNetworkIdentities()` before enabling transaction submission.
- Inject RPC credentials at runtime; never persist them in snapshots.
- Inject a gRPC v2 `SuiGateway` for production Sui access.
- Keep RPC bodies disabled in production logging.
- Use `waitForTransactionReceipt` with a product-specific timeout and required
  confirmation level.
- Run deterministic unit tests on every change and separate authenticated
  testnet smoke tests before release.
- Close the engine when the application runtime is disposed.

The engine owns and closes its transport by default when that transport
implements `ClosableRpcTransport`. Set `closeTransportOnClose: false` only when
the host intentionally shares one transport across multiple engines and owns
its lifecycle itself.

For a read-only check against the bundled public testnets, run
`dart run tool/testnet_smoke.dart`. Keep it outside deterministic CI because
public endpoints are rate-limited and can be temporarily unavailable.

## Codex integration skill

The repository includes a distributable Codex skill at
[`skills/wallet-engine-integration`](skills/wallet-engine-integration). Install
or copy that directory into the consuming team's Codex skills collection, then
invoke `$wallet-engine-integration` when integrating, testing, or diagnosing
this package. The skill routes an agent to the current public APIs, chain
capability boundaries, security rules, and production validation commands.

Example prompts:

- `Use $wallet-engine-integration to add wallet_engine to this Flutter App.`
- `Use $wallet-engine-integration to review this App's wallet integration for production.`
- `Use $wallet-engine-integration to diagnose this RPC or signing failure.`

## Local example application

The Flutter application under [`example/`](example/) initializes Trust Wallet
Core once at startup and provides a local UI for 12/24-word wallet creation,
mnemonic recovery, private-key import, address validation, and watch-only
accounts. It also exposes read-only multi-chain RPC probes, network identity
verification, configuration snapshot inspection, and an in-memory structured
SDK log viewer. It keeps secret material in memory only and never writes it to
logs or local storage.

```shell
cd example
flutter pub get
flutter run -d <ios-or-android-device-id>
```

Android arm64 and iOS targets are included. Use only throwaway test keys;
copying a secret still places it in the operating-system clipboard.

## Implemented protocols

| Protocol | RPC and transaction capabilities | Signing |
| --- | --- | --- |
| EVM | decimal balance, calls, nonce, gas, legacy/EIP-1559 fees, prepare, broadcast, receipt | transaction, personal message, EIP-712/Hyperliquid |
| Solana | balance, SPL balance/account, blockhash, priority fee, rent, broadcast, receipt | SOL and SPL/Token-2022 transfers |
| Sui | balance, paginated coins, gas price/dry-run, broadcast, receipt | raw JSON, `paySui`, and `pay` |
| TRON | balance, block header, native/contract build, constant call, fee schedule, broadcast, receipt | exact `raw_data` bytes and serialized transaction assembly |
| Bitcoin | Electrum UTXO, balance, fee rate, broadcast, confirmation lookup | P2WPKH transfer and change-key inputs |
| Provenance | transaction signing only; no on-chain client existed in the source package | Cosmos-SDK JSON bank-send signature |

The remaining `ChainFamily` values are extension points, not claims of an
implemented adapter. Aptos, TON, XRP, Cardano, Cosmos, Polkadot, and NEAR only
had wallet derivation support in the source package; their RPC/transaction
adapters should be added when product workflows require them.

## License

`wallet_engine` is available under the Apache License 2.0. See
[`LICENSE`](LICENSE) for the full terms. Third-party notices and source
locations are documented in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
