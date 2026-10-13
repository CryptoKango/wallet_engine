---
name: wallet-engine-integration
description: Integrate, configure, use, test, or troubleshoot the wallet_engine Flutter plugin in an application. Use for native startup, wallet/account APIs, multichain RPC sessions, transaction signing and broadcasting, diagnostics, stable error handling, or production-readiness checks. Do not use it to move project-specific contract ABI or business workflows into wallet_engine.
---

# Wallet Engine Integration

Use this skill to make application-side `wallet_engine` changes that follow the
library's public API and security boundaries.

## Start with the repository contract

1. Locate the `wallet_engine` checkout or installed package source.
2. Read the public export file `lib/wallet_engine.dart` and the relevant
   implementation before writing code. Do not infer support from a
   `ChainFamily` enum value.
3. Treat these repository documents as authoritative:
   - `README.md` for current APIs and examples.
   - `SECURITY.md` for secret and logging boundaries.
   - `SUPPORTED_PLATFORMS.md` for supported host targets.
   - `API_STABILITY.md` and `RELEASE_CHECKLIST.md` for public changes.
4. Identify whether the request is an App integration, a chain operation, or a
   library/release change, then read only the matching reference below.

## Route the task

- Read [references/app-integration.md](references/app-integration.md) for
  dependency setup, one-time initialization, configuration, accounts,
  diagnostics, lifecycle, and App architecture.
- Read [references/chain-capabilities.md](references/chain-capabilities.md) when
  selecting a chain session, adding transaction flows, handling Solana ATA, or
  deciding whether a protocol is implemented.
- Read [references/production-validation.md](references/production-validation.md)
  for security review, error handling, tests, native artifacts, CI, release, or
  diagnosing a failed integration.

## Preserve these boundaries

- Initialize one `WalletCoreNativeRuntime` during App startup. Inject that same
  initialized runtime into account services and bundled signers; never add
  per-operation lazy initialization.
- Keep business services, product workflows, and project-specific contract ABI
  wrappers in the host application. Use `wallet_engine` for generic RPC, fee,
  transaction construction, signing, broadcasting, and confirmations.
- Let the host fetch, authenticate, persist, and roll back remote configuration.
  Give the engine an immutable validated snapshot; it keeps runtime state only.
- Supply RPC secrets through `RpcCredentialProvider`. Never place credentials in
  endpoint URLs, static headers, config snapshots, source, fixtures, or logs.
- Keep mnemonics and private keys out of logs, analytics, crash reports, and
  ordinary Dart persistence. Default to `exposePrivateKey: false` and keep
  signing material behind `PrivateKeyAccess` or a hardware/MPC signer.
- Use `Decimal` for public/user-facing amounts and `AmountCodec` only at protocol
  boundaries. Never silently round transfer amounts.
- Catch public failures as `WalletError`; branch on `publicCode`, serialize
  `errorCode` with `WalletErrorProtocol.version`, and use `retryable` only as an
  input to the host retry policy.
- Keep RPC request/response bodies disabled in production. If debugging requires
  them, use redacted mode and a bounded body length.
- Close the engine with the application runtime. If transport ownership is
  shared, set `closeTransportOnClose: false` and close it in the host.

## Make changes safely

When editing an application, prefer the smallest integration that uses public
exports from `package:wallet_engine/wallet_engine.dart`. Do not import `src/`
paths. When editing the library, add or update deterministic tests and public
documentation in the same change. Do not claim production readiness for a
platform or protocol that is still gated in `SUPPORTED_PLATFORMS.md` or
`RELEASE_CHECKLIST.md`.

End with the validation level appropriate to the change. At minimum format and
analyze changed Dart code and run focused tests; use the complete release checks
for public API, native bridge, packaging, or release work.
