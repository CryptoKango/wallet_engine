# Dependency review

This file records release-relevant properties of direct dependencies. It is a
technical inventory, not legal advice.

## Trust Wallet Core native migration

The production target is the official Apache-2.0
`trustwallet/wallet-core` source through a narrow C ABI owned by this
repository. `native/wallet-core.lock.json` pins release `4.8.4`, its full Git
commit, canonical release URLs, and official release-asset SHA-256 values.
The Dart runtime rejects artifacts whose embedded ABI, upstream version, or
commit differs from that lock.

Owned iOS device, iOS simulator, and Android arm64-v8a artifacts are present
in the lock. Android is built directly
from the pinned source rather than the JNI-oriented upstream AAR. Its bridge is
compiled into a single DSO with the static C++ runtime and a narrow exported
ABI. Android still requires execution of the native vector suite on a
maintained physical device before the first stable release.

Implemented bridge surfaces:

| Surface | Consumers | Status |
| --- | --- | --- |
| Metadata and SHA-256 self-test | Runtime startup | Implemented |
| Protobuf JSON signing | EVM, Solana, Cosmos/Provenance | Implemented |
| Recoverable secp256k1 digest signing | TRON | Implemented |
| Protobuf binary signing | Bitcoin, Sui | Implemented |
| HD derivation/address API | Account service | Implemented |

### Removed third-party bindings

The AGPL/commercial-license wrapper stack was removed from the package:

| Package | Version | Role |
| --- | --- | --- |
| `wallet_core_bindings` | 4.6.0 | Generated Dart API |
| `wallet_core_bindings_native` | 4.6.0 | Native FFI loader |
| `wallet_core_bindings_libs` | 4.6.1 | Platform binaries |

No source or generated code from those packages is shipped. The owned FFI
boundary links directly to the approved Apache-2.0 Trust Wallet Core pin.
Future upstream upgrades must update the source/artifact lock, review upstream
changes, run deterministic vectors and native tests on every maintained
platform, and record any output changes.

## Pure-Dart and transport dependencies

`bip39`, `blockchain_utils`, `decimal`, `dio`, `ffi`, and `on_chain` are
reviewed through the lockfile used by the example application, dependency
automation, deterministic tests, and the release checklist. Any dependency
that gains native code, code generation, or a restrictive license must be
promoted to a dedicated section in this file.
