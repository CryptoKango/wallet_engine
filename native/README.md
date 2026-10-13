# Owned Wallet Core native bridge

This directory defines the native trust boundary used by `wallet_engine`.
Only official `trustwallet/wallet-core` source matching
`wallet-core.lock.json` may be linked into release artifacts.

## Build contract

1. Fetch the canonical repository and checkout the exact locked commit.
2. Verify that the locked tag resolves to that commit.
3. Build in an isolated CI worker with a pinned compiler/container image.
4. Build `native/bridge` against that checkout.
5. Strip non-public symbols, sign artifacts where applicable, and calculate
   SHA-256 for every target artifact.
6. Add the artifact metadata to `wallet-core.lock.json` and run
   `dart run tool/verify_wallet_core_lock.dart --release`.
7. Run address and signing golden vectors on every maintained target.

The application build must consume those verified artifacts. It must not
download or compile Wallet Core implicitly during an App Store build.

## Current status

ABI metadata, startup symbol validation, the native known-answer self-test,
JSON/protobuf signing, EVM message signing, recoverable secp256k1 digest
signing, key inspection, and HD derivation are implemented. EVM, Solana,
Provenance/Cosmos, TRON, Bitcoin, and Sui all use this owned bridge.

The checked-in Apple XCFramework contains iOS device and iOS simulator
dynamic-framework slices. It is consumed from the shared `darwin/` plugin
through both CocoaPods and Swift Package Manager. Android contains one locked
arm64-v8a single-DSO artifact built directly from the pinned source. Only the
owned, versioned bridge ABI is exported; the C++ runtime is linked statically.
Android execution vectors remain a stable-release gate until they pass on a
maintained physical device.

No legacy third-party Dart binding or binary wrapper remains in this package.

## Reproducible builds

Build Apple artifacts from the pinned official release archive:

```shell
bash tool/build_apple_xcframework.sh TrustWalletCore-4.8.4.tar.xz
```

Build Android artifacts from a clean checkout at the locked commit. The build
requires Android NDK 28.2.13676358, Android CMake 3.22.1, Rust
nightly-2025-12-11, and cbindgen 0.29.4:

```shell
bash tool/build_android_artifacts.sh /path/to/wallet-core
```

The Android script verifies the checkout commit and dependency archives,
regenerates Rust/C++/protobuf bindings, builds the maintained arm64-v8a ABI, checks the
exported symbol count and runtime dependencies, and strips the result. Every
shipped file must then match the SHA-256 value in the native lock.
