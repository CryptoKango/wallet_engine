# Supported platforms

`wallet_engine` maintains the following Flutter application targets:

The packaged Apple minimum is iOS 14.

| Platform | CI gate | Native signing |
| --- | --- | --- |
| Android | Debug APK and native ELF/APK audit | Packaged arm64-v8a bridge; physical-device signing remains a pre-1.0 release gate |
| iOS | Simulator build | Packaged device/simulator framework; device execution is a pre-1.0 release gate |

The iOS plugin supports both CocoaPods and Swift Package Manager from a single
shared Darwin artifact. Android ships a locked arm64-v8a native artifact built
from the pinned source. Its production claim remains gated on running the
native signing suite on a maintained physical Android device. macOS, 32-bit
Android, Android x86_64, Linux, Windows, and Web are unsupported.

RPC-only and watch-only APIs may work on additional Dart or Flutter targets,
but that does not make those targets supported. A platform becomes maintained
only after its example host, native asset loading, signing suite, and release
build are continuously validated.

Applications must still run their own device tests for key storage, lifecycle,
backup/recovery, secure-screen behavior, and hardware-backed signing.
