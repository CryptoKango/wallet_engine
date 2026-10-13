# Release checklist

## Required for every release

- `dart format --output=none --set-exit-if-changed lib test tool`
- `flutter analyze`
- `flutter test --coverage`
- `dart run tool/check_coverage.dart`
- `dart doc` with zero warnings and errors
- Read-only public-testnet smoke, or equivalent checks against dedicated RPCs
- Dependency and native-library review
- `dart run tool/verify_wallet_core_lock.dart --release`
- `bash tool/build_apple_xcframework.sh <verified-release-archive>`
- Changelog and semantic-version review
- Verify no keys, credentials, signed payloads, or production endpoints exist
  in source, fixtures, logs, or configuration examples

## Required before the first stable public release

- [x] License repository code under Apache-2.0 and document third-party notices
- [x] Remove `wallet_core_bindings`, `wallet_core_bindings_native`, and
  `wallet_core_bindings_libs` from all manifests and resolved lockfiles
- [x] Build, hash, and record owned Wallet Core artifacts for every maintained
  target in `native/wallet-core.lock.json`
- [x] Restrict Android native exports to the owned C ABI, audit dynamic
  dependencies, and verify all packaged APK ABI payloads against the lock
- [ ] Run owned-bridge address and signing vectors on Android and Apple hosts
- [ ] Run the macOS native suite on macOS 11, or rebuild Wallet Core from the
  pinned source without the upstream deployment-target linker warnings
- [x] Add canonical repository and issue-tracker metadata to `pubspec.yaml`
- [x] Provide a public Sui gateway boundary and document gRPC v2 as the
  required production provider contract
- Run funded testnet build/sign/broadcast/confirmation tests on every supported
  platform; these tests must use secret storage and stay outside public CI
- Run device tests for 12/24-word creation, mnemonic recovery, private-key
  import, watch-only validation, and deterministic address derivation.
- Validate Trust Wallet Core native assets on every platform claimed as
  supported by the consuming application
- [x] Establish the deprecation window for public APIs and error protocol
  versions in `API_STABILITY.md`
- [x] Raise the deterministic line-coverage floor to 60% and add a full-host
  native signing integration harness
- [x] Define the maintained platform matrix in `SUPPORTED_PLATFORMS.md` and
  gate Android, iOS, and macOS integration paths in CI
