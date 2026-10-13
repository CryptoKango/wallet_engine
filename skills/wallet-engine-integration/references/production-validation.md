# Production validation

## Security review

Before approving an App integration, verify all of the following:

- One native runtime is initialized during App startup and reused by bundled
  account services and signers.
- The host verifies remote configuration authenticity, expiry, and rollback
  policy before applying it, and persists only a last-known-good snapshot.
- RPC credentials come from `RpcCredentialProvider`, not URLs, static headers,
  config snapshots, source, fixtures, or logs.
- Mnemonics, passphrases, private keys, complete signed transactions, and raw
  exceptions never enter logs, analytics, crash reports, screenshots, or test
  fixtures.
- Production key material lives in platform-protected storage or hardware/MPC
  custody and is exposed to software signing only through the smallest possible
  `PrivateKeyAccess` boundary.
- `verifyNetworkIdentities()` succeeds before transaction submission is
  enabled.
- RPC body logging is off in production.
- Transaction confirmation uses a bounded timeout and a product-specific
  confirmation requirement.
- The engine and any host-owned shared transport are closed by their owner.

## Stable public errors

All public engine failures implement `WalletError`. Handle `publicCode` in App
logic, persist the string `errorCode` only with `WalletErrorProtocol.version`,
and treat unknown future codes as an expected compatibility case. Existing
serialized code values must never be renamed or reused.

`retryable` is a classification signal, not permission for an unbounded retry
loop. Bound attempts, delay, and total elapsed time in the host. Never retry a
signing failure or broadcast blindly if transaction submission may already have
succeeded; query the chain state or receipt first.

## Diagnosing integration failures

1. Capture structured `WalletLogger` events at `debug` level in a controlled
   development build.
2. Check the earliest lifecycle/configuration error before looking at later RPC
   failures.
3. If native startup fails, verify the packaged artifact and
   `native/wallet-core.lock.json`; do not add lazy retries inside signers.
4. If RPC fails, inspect endpoint health, network identity, retry classification,
   and redacted request/response bodies. Never request production credentials or
   seed material from the reporter.
5. If signing succeeds but confirmation times out, query the returned
   transaction hash before resubmitting.
6. Reproduce with the local `example/` and a throwaway test wallet when possible.

## Validation commands

For an application integration, run focused host tests plus the platform build
that will ship. For changes inside `wallet_engine`, start with:

```shell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test --coverage
dart run tool/check_coverage.dart
dart doc
```

For native or release changes, also run the repository's release gates:

```shell
dart run tool/verify_wallet_core_lock.dart --release
bash tool/verify_android_artifacts.sh
bash tool/verify_android_apk.sh <path-to-apk>
```

Use `dart run tool/testnet_smoke.dart` only as a separate read-only smoke test;
shared public endpoints are nondeterministic and must stay outside deterministic
CI. Funded build/sign/broadcast/confirmation checks must use authenticated
testnets, protected throwaway keys, and supported devices outside public CI.

Run the example's full-host native signing integration suite on a supported
host when a native signer, packaged artifact, or bridge ABI changes:

```shell
cd example
flutter test integration_test/native_signing_test.dart -d <ios-or-android-device-id>
```

Consult `RELEASE_CHECKLIST.md` and `SUPPORTED_PLATFORMS.md` before making a
production-support claim. A passing unit suite does not by itself satisfy the
remaining physical-device and platform release gates.
