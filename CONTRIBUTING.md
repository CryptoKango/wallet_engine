# Contributing

Public APIs and serialized error codes are compatibility contracts. Existing
`WalletErrorCode.value` strings must never be renamed or reused. Additive codes
remain on the current protocol version; semantic changes require a new error
protocol version and a migration note.

Before submitting a change, run:

```sh
dart format --output=none --set-exit-if-changed lib test tool example/lib example/test example/integration_test
flutter analyze
flutter test --coverage
dart run tool/check_coverage.dart
dart doc
cd example && flutter analyze && flutter test
```

New chain behavior must include deterministic unit tests. RPC changes should
cover success, malformed responses, deterministic node errors, retryable
transport errors, and endpoint failover. Live testnet smoke tests must not be
part of the deterministic unit-test job and must never contain credentials.
Changes to native signing must also update and run
`example/integration_test/native_signing_test.dart` on a supported host.

Review `DEPENDENCY_REVIEW.md` and `RELEASE_CHECKLIST.md` whenever a direct
dependency or supported platform changes. Native dependency upgrades require
the full-host signing integration suite, not only unit tests.
