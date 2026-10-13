# App integration

## Dependency

The package is not published to pub.dev. Pin a tag or commit for production:

```yaml
dependencies:
  wallet_engine:
    git:
      url: https://github.com/CryptoKango/wallet_engine.git
      ref: your-reviewed-tag-or-commit
```

For local development, use a path dependency instead:

```yaml
dependencies:
  wallet_engine:
    path: ../wallet_engine
```

Import only the public entrypoint:

```dart
import 'package:wallet_engine/wallet_engine.dart';
```

Supported production application targets are Android, iOS, and macOS. Verify
their current minimum versions and native-signing gates in
`SUPPORTED_PLATFORMS.md`.

## Application ownership

Keep the dependency direction:

```text
Feature
  -> application service
  -> project contract/wallet adapter
  -> wallet_engine
  -> RPC / build / sign / broadcast / confirm
```

Project contract wrappers encode and decode ABI or product-specific calls.
`wallet_engine` accepts their encoded payload and supplies generic chain
operations. The host also owns secure key storage, remote-config download and
signature verification, last-known-good config persistence, authentication,
and UI.

## Initialize once

Create the native runtime at App startup before constructing bundled signers.
Pass the same logger to the runtime and engine to get one structured event
stream:

```dart
Future<WalletEngine> createWalletEngine() async {
  final logger = WalletLogger(
    minimumLevel: WalletLogLevel.debug,
    sink: (event) => appDiagnostics.record(event.toDiagnosticMap()),
  );

  final runtime = WalletCoreNativeRuntime(
    bridge: FfiWalletCoreNativeBridge.open(),
    logger: logger,
  );
  await runtime.initialize();

  final config = WalletEngineTestnetPreset.create(revision: 1);
  final engine = WalletEngine(
    config: config,
    adapters: walletEngineDefaultAdapters(),
    transport: DioRpcTransport(
      credentialProvider: projectCredentialProvider,
    ),
    walletAccounts: WalletCoreAccountService(runtime: runtime),
    logger: logger,
  );

  await engine.verifyNetworkIdentities();
  return engine;
}
```

The preset uses shared, rate-limited public testnets and is not a production
configuration. Production configuration must come from an authenticated,
expiry-checked host snapshot. Use `WalletEngineConfigCodec` for its stable JSON
shape; runtime credentials are intentionally excluded. Apply a newer snapshot
with `engine.applyConfig(next)` and close the engine on App shutdown.

The example names `appDiagnostics` and `projectCredentialProvider` are host
implementations, not SDK globals.

## Accounts and recovery

Use a configured `chainKey` so network-sensitive addresses are derived for the
correct network:

```dart
final created12 = await engine.createWallet12(chainKey: chainKey);
final created24 = await engine.createWallet24(chainKey: chainKey);
final restored = await engine.deriveAccount(
  chainKey: chainKey,
  mnemonic: recoveryPhrase,
);
final imported = await engine.importPrivateKey(
  chainKey: chainKey,
  privateKey: importedKey,
);
final watchOnly = engine.createWatchOnly(
  chainKey: chainKey,
  address: address,
);
```

Creation returns the mnemonic once. Derivation and import hide private keys by
default. `exposePrivateKey: true` is a high-risk compatibility path: move the
value immediately to platform-protected storage and discard it. Prefer a
short-lived synchronous `PrivateKeyAccess` callback or a custom hardware/MPC
signer.

Recovery input can use immutable `Bip39WordList.english` lookup and prefix
helpers. The word-list API performs no RPC, persistence, or native startup.

## Diagnostics

General SDK diagnostics are opt-in through `WalletLogger`. Consume
`WalletLogEvent.toDiagnosticMap()` and send only warning/error events to
production telemetry as appropriate. Sink failures are isolated by the SDK.

RPC bodies are separately opt-in through `RpcLoggingConfig`:

```dart
const RpcLoggingConfig(
  includeRequestBody: true,
  includeResponseBody: true,
  maxBodyCharacters: 8192,
  bodyMode: RpcLogBodyMode.redacted,
)
```

Enable this only in controlled debugging. Even redacted bodies can expose
addresses and transaction metadata. Never use `RpcLogBodyMode.full` in a
production App.

## Error boundary

```dart
try {
  await operation();
} on WalletError catch (error) {
  appDiagnostics.record(error.toDiagnosticMap());
  if (error.publicCode == WalletErrorCode.rpcTransportTimeout) {
    // Apply a product-specific response.
  }
  if (error.retryable) {
    // Feed this signal into the host's bounded retry policy.
  }
}
```

Use `WalletErrorNormalizer.guard` only at third-party or Dart exception
boundaries. Do not expose `cause`, raw exceptions, stack traces, endpoints, or
credentials to users or telemetry.
