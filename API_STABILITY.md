# API stability policy

`wallet_engine` follows semantic versioning for its public Dart entrypoint,
serialized configuration schema, and serialized error codes.

## Before 1.0

The package is integration-preview software. Breaking changes are allowed only
when documented in `CHANGELOG.md` and accompanied by a migration note.

## From 1.0

- Existing `WalletErrorCode.value` strings are never renamed or reused.
- Configuration schema changes remain backward-readable for at least one major
  package version.
- A public API is marked deprecated for at least two minor releases before
  removal, except when retaining it would expose private material or produce an
  invalid blockchain transaction.
- Security and consensus-correctness fixes may disable unsafe behavior without
  a deprecation window. The release notes must identify the impact.
- Chain-specific experimental entrypoints are explicitly documented as such
  and do not weaken the stability of core RPC, signing, amount, or error APIs.

Every stable release must complete `RELEASE_CHECKLIST.md`.
