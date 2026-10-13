# Changelog

## Unreleased

- Limit packaged native artifacts to Android arm64-v8a and iOS
  device/simulator slices; remove macOS and 32-bit/x86_64 Android support.
- Added failure-isolated structured SDK diagnostics for native initialization,
  accounts, signing, configuration, sessions, RPC lifecycle, and shutdown.
- Added severity filtering and recursive redaction of sensitive log context.
- Added public API lifecycle tests and RPC diagnostics/integration cases for
  retry metadata, redaction, truncation, priority selection, runtime
  credentials, path/query resolution, and custom protocol error mapping.

- Add the first-party Wallet Core native bridge boundary, official 4.8.4
  source/artifact pins, startup metadata verification, and SHA-256 self-test.
- Add owned-bridge signers for EVM, Solana, Provenance/Cosmos, TRON, Bitcoin,
  and Sui, plus owned HD derivation and key inspection.
- Add stable native-version and native-self-test error codes plus a
  release-mode native lock verifier. Remove the legacy AGPL Dart bindings and
  binary-wrapper packages from the dependency graph.
- Package the owned Apple bridge as a dynamic XCFramework for iOS device and
  simulator, with shared CocoaPods and SwiftPM support.
- Add a locked Android arm64-v8a FFI artifact plus a reproducible
  source-build pipeline. The single-DSO bridge uses a static C++ runtime and
  exposes only the versioned wallet_engine C ABI.
- Correct Bitcoin BIP-84 testnet/signet/regtest derivation paths, Regtest HRP
  handling, and Electrum TLS scheme selection.
- Make private-key string exports opt-in through `exposePrivateKey`; account
  creation, recovery, and import now return public account data by default.
- Reject embedded RPC credentials, unsupported schemes, and accidental
  clear-text transports unless explicitly enabled for development.
- Add a strongly typed, protocol-neutral Sui gateway for production gRPC v2
  providers while retaining an explicitly named JSON-RPC compatibility layer.
- Add Dio loopback integration tests and full-host native signing tests for
  EVM, Solana, Sui, TRON, and Bitcoin.
- Add repository metadata, API stability policy, Dependabot, documentation CI,
  example tests, and Android/iOS build gates.
- Define Android arm64 and iOS as the maintained platform matrix; other
  platforms remain best-effort until native signing is validated in CI.
- Add a third-party dependency review and make native-binding commercial or
  AGPL authorization an explicit stable-release gate.
- Direct `SuiChainSession` callers must migrate to
  `SuiChainSession.withGateway`; adapter-based construction is unchanged.
- Keep the previous configuration snapshot active and return a stable error
  when session shutdown prevents a configuration update.
- Expose the canonical immutable 2,048-word BIP-39 English word list with
  index, membership, and prefix-query APIs.
- Add canonical Solana ATA derivation, SPL Token/Token-2022 account discovery,
  existence checks, parsed account state, exact balances, and owner balance
  aggregation.
- Add stateless 12- and 24-word BIP-39 wallet creation, validation, recovery,
  and multi-chain HD account derivation APIs.
- Derive Bitcoin receive/change addresses using the configured mainnet,
  testnet/signet, or regtest Bech32 prefix.
- Add stable account-generation error codes and redact mnemonic/private-key
  material from public string and diagnostic output.
- Add private-key import, chain-aware address/private-key validation, and
  watch-only accounts for EVM, Solana, Sui, TRON, and Bitcoin.
- Enforce EIP-55, Base58Check, Bech32/Bech32m, Ed25519, and secp256k1 format
  rules without RPC calls or secret retention.
- Add configuration schema v1 encoding/decoding and expiry enforcement.
- Add EVM RPC network identity verification and engine-wide verification.
- Add Solana, Sui, and Bitcoin network identity verification when a genesis
  hash or chain identifier is configured.
- Add cancellable, timeout-bounded transaction confirmation polling helpers.
- Add confirmation helpers for EVM, Solana, Sui, TRON, and Bitcoin sessions.
- Redact signed payloads and known sensitive fields from RPC bodies by default.
- Keep raw JSON-RPC server error text only in the private diagnostic cause;
  public messages and serialized diagnostics remain stable and sanitized.
- Make `maxAttempts` a true total-attempt limit, including single-endpoint
  retries, with bounded exponential backoff and HTTP `Retry-After` support.
- Add Sui transaction digest derivation, safe gas fallback, and stable
  Sui-specific public error codes.
- Add CI, contribution requirements, and security integration guidance.
- Add a checked coverage baseline and a formal release checklist.
- Add a read-only public-testnet smoke tool outside deterministic CI.
- Add explicit RPC transport ownership and close Dio connection pools when the
  engine is disposed.

## 0.1.0

- Establish the standalone `wallet_engine` package.
- Add immutable chain and RPC configuration models.
- Add the chain adapter/session extension points.
- Add atomic, revision-guarded configuration replacement.
- Add transport-neutral RPC requests and a Dio transport implementation.
- Add per-chain RPC endpoint health, cooldown, and failover.
- Add JSON-RPC 2.0 decoding with protocol-aware retry behavior.
- Add the first generic EVM adapter for calls, fees, broadcast, and receipts.
- Add EVM transaction preparation with legacy and EIP-1559 fee modes.
- Add a signer boundary for local keys, UKey, hardware, and MPC providers.
- Add an idempotent Trust Wallet Core runtime and local EVM signer.
- Add Solana RPC, SOL/SPL transaction signing, broadcast, and receipts.
- Add Sui coin queries, dry-run gas estimates, signing, broadcast, and receipts.
- Add TRON REST RPC, raw-data transaction building/signing, fees, and receipts.
- Add Bitcoin Electrum transport, UTXO/fee queries, signing, and confirmations.
- Add EVM message/EIP-712 and Provenance transfer signing.
- Use `Decimal` for public balances, transfer amounts, and display fees, with
  checked conversion to integer protocol base units.
- Normalize engine, validation, RPC, signing, and chain failures behind the
  common `WalletError` contract with stable codes and safe diagnostics.
- Centralize public codes in `WalletErrorCode` and version their serialized
  diagnostic contract through `WalletErrorProtocol.version`.
- Add opt-in, length-limited RPC request and response body logging through
  `RpcLoggingConfig`.
- Require explicit Trust Wallet Core initialization during application startup;
  bundled signers no longer initialize the native runtime per operation.
- Add an overridable built-in test-network preset for Ethereum Sepolia, Solana
  Devnet, TRON Nile, and Bitcoin Testnet, with opt-in legacy Sui Testnet.
