#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 wallet-core-source-checkout [output-directory]" >&2
  exit 64
fi

wallet_core_source="$(cd "$1" && pwd)"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output_dir="${2:-$repo_root/android/src/main/jniLibs}"

readonly wallet_core_commit=d40d24a63d92619167903369308bf0e2f7eb3a59
readonly rust_toolchain=nightly-2025-12-11
readonly ndk_version=28.2.13676358
readonly cmake_version=3.22.1
readonly boost_sha256=66cc701002c558afb5baf7e1a163ca7f8c3d4c80e7ec4ffb7c66dfcb32ac9358

fail() {
  echo "$1" >&2
  exit "${2:-65}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1" 66
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "SHA-256 mismatch: $file"
}

require_command git
require_command ruby
require_command rustup
require_command cargo
require_command cbindgen
require_command curl
require_command unzip
require_command shasum

actual_commit="$(git -C "$wallet_core_source" rev-parse HEAD)"
[[ "$actual_commit" == "$wallet_core_commit" ]] ||
  fail "Wallet Core checkout must be pinned to $wallet_core_commit"

android_sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$android_sdk_root" ]] || fail "Set ANDROID_HOME or ANDROID_SDK_ROOT" 66
android_ndk_root="${ANDROID_NDK_HOME:-$android_sdk_root/ndk/$ndk_version}"
[[ -d "$android_ndk_root" ]] ||
  fail "Android NDK $ndk_version was not found at $android_ndk_root" 66

cmake_bin="${CMAKE_BIN:-$android_sdk_root/cmake/$cmake_version/bin/cmake}"
ninja_bin="${NINJA_BIN:-$android_sdk_root/cmake/$cmake_version/bin/ninja}"
[[ -x "$cmake_bin" && -x "$ninja_bin" ]] ||
  fail "Android CMake $cmake_version and Ninja are required" 66

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64|Darwin-x86_64) host_tag=darwin-x86_64 ;;
  Linux-x86_64) host_tag=linux-x86_64 ;;
  *) fail "Unsupported Android NDK host" 66 ;;
esac
ndk_bin="$android_ndk_root/toolchains/llvm/prebuilt/$host_tag/bin"
[[ -x "$ndk_bin/llvm-strip" ]] || fail "Invalid Android NDK toolchain" 66

rustup toolchain install "$rust_toolchain" --profile minimal
rustup component add rust-src --toolchain "$rust_toolchain"
rustup target add \
  --toolchain "$rust_toolchain" \
  aarch64-linux-android
[[ "$(cbindgen --version)" == "cbindgen 0.29.4" ]] ||
  fail "cbindgen 0.29.4 is required" 66

export PREFIX="$wallet_core_source/build/local"
export PATH="$PREFIX/bin:$PATH"

(
  cd "$wallet_core_source"
  tools/download-dependencies
)
verify_sha256 "$PREFIX/json/include.zip" \
  a22461d13119ac5c78f205d3df1db13403e58ce1bb1794edc9313677313f4a9d
verify_sha256 "$PREFIX/src/gtest/googletest-1.16.0.tar.gz" \
  78c676fc63881529bf97bf9d45948d905a66833fbfa5318ea2cd7478cb98f399
verify_sha256 "$PREFIX/src/check/check-0.15.2.tar.gz" \
  a8de4e0bacfb4d76dd1c618ded263523b53b85d92a146d8835eb1a52932fa20a
verify_sha256 "$PREFIX/src/protobuf/protobuf-java-3.20.3.tar.gz" \
  aa109c630d85a3ef625d69344a83e72bf3d58df034db8d099c95c51f01cde20e

host_build="$wallet_core_source/build/wallet-engine-host"
protobuf_source="$PREFIX/src/protobuf/protobuf-3.20.3"
"$cmake_bin" \
  -S "$protobuf_source/cmake" \
  -B "$host_build/protobuf" \
  -Dprotobuf_BUILD_TESTS=OFF \
  -Dprotobuf_MODULE_COMPATIBLE=ON
"$cmake_bin" --build "$host_build/protobuf" --parallel
"$cmake_bin" --install "$host_build/protobuf" --prefix "$PREFIX"

"$cmake_bin" \
  -S "$wallet_core_source/protobuf-plugin" \
  -B "$host_build/protobuf-plugin" \
  -DProtobuf_DIR="$PREFIX/lib/cmake/protobuf"
"$cmake_bin" --build "$host_build/protobuf-plugin" --parallel
"$cmake_bin" --install "$host_build/protobuf-plugin" --prefix "$PREFIX"

boost_archive="$host_build/boost-headers-1.83.0.zip"
boost_root="$host_build/boost"
if [[ ! -f "$boost_archive" ]]; then
  curl --fail --location --retry 3 \
    --output "$boost_archive" \
    https://github.com/emscripten-ports/boost/releases/download/boost-1.83.0/boost-headers-1.83.0.zip
fi
verify_sha256 "$boost_archive" "$boost_sha256"
mkdir -p "$boost_root"
unzip -q -o "$boost_archive" -d "$boost_root"
[[ -f "$boost_root/boost/version.hpp" ]] || fail "Boost headers are incomplete"

export RUSTUP_TOOLCHAIN="$rust_toolchain"
export AR="$ndk_bin/llvm-ar"
export CC_aarch64_linux_android="$ndk_bin/aarch64-linux-android23-clang"
export CXX_aarch64_linux_android="$ndk_bin/aarch64-linux-android23-clang++"
export RUSTFLAGS="-Zlocation-detail=none --remap-path-prefix=$wallet_core_source=/wallet-core"
export SOURCE_DATE_EPOCH="$(git -C "$wallet_core_source" show -s --format=%ct HEAD)"

(
  cd "$wallet_core_source/rust"
  cargo build \
    --locked \
    -Z build-std=std,panic_abort \
    --target aarch64-linux-android \
    --release \
    --lib
  cbindgen \
    --crate wallet-core-rs \
    --output ../src/rust/bindgen/WalletCoreRSBindgen.h
)
(
  cd "$wallet_core_source"
  codegen/bin/coins
  cd codegen-v2
  cargo run --locked -- cpp
)
(
  cd "$wallet_core_source"
  codegen/bin/codegen
  tools/doxygen_convert_comments
  protoc -I="$PREFIX/include" -I=src/proto \
    --cpp_out=src/proto src/proto/*.proto
  protoc -I="$PREFIX/include" -I=src/Tron/Protobuf \
    --cpp_out=src/Tron/Protobuf src/Tron/Protobuf/*.proto
  protoc -I="$PREFIX/include" -I=src/Zilliqa/Protobuf \
    --cpp_out=src/Zilliqa/Protobuf src/Zilliqa/Protobuf/*.proto
  protoc -I="$PREFIX/include" -I=src/Hedera/Protobuf \
    --cpp_out=src/Hedera/Protobuf src/Hedera/Protobuf/*.proto
  protoc -I="$PREFIX/include" -I=src/proto \
    --plugin="$PREFIX/bin/protoc-gen-c-typedef" \
    --c-typedef_out=include/TrustWalletCore src/proto/*.proto
)

bridge_injection="$repo_root/native/bridge/android/WalletEngineBridge.cmake"
bridge_export_map="$repo_root/native/bridge/android/wallet_engine.exports.map"
[[ -f "$bridge_injection" && -f "$bridge_export_map" ]] ||
  fail "Android bridge build files are incomplete" 66
build_root="$wallet_core_source/build/wallet-engine-android"

build_abi() {
  local abi="$1"
  local build_dir="$build_root/$abi"
  local destination="$output_dir/$abi"
  "$cmake_bin" \
    -S "$wallet_core_source" \
    -B "$build_dir" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$android_ndk_root/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-23 \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DTW_UNITY_BUILD=ON \
    -DBoost_INCLUDE_DIR="$boost_root" \
    -DCMAKE_PROJECT_INCLUDE="$bridge_injection" \
    -DCMAKE_MAKE_PROGRAM="$ninja_bin"
  "$cmake_bin" --build "$build_dir" --target TrustWalletCore --parallel
  mkdir -p "$destination"
  install -m 0755 \
    "$build_dir/libwallet_engine_core.so" \
    "$destination/libwallet_engine_core.so"
  "$ndk_bin/llvm-strip" --strip-unneeded \
    "$destination/libwallet_engine_core.so"
}

build_abi arm64-v8a

for library in "$output_dir"/*/libwallet_engine_core.so; do
  exported_symbols="$(
    "$ndk_bin/llvm-nm" -D --defined-only "$library" |
      awk '{print $3}' |
      sed '/^$/d'
  )"
  unexpected_symbols="$(
    printf '%s\n' "$exported_symbols" |
      grep -v '^wallet_engine_wallet_core_' || true
  )"
  [[ -z "$unexpected_symbols" ]] || {
    printf 'Unexpected exported symbols in %s:\n%s\n' \
      "$library" "$unexpected_symbols" >&2
    fail "Android artifact exports symbols outside the owned ABI: $library"
  }
  symbol_count="$(
    printf '%s\n' "$exported_symbols" |
      grep -c '^wallet_engine_wallet_core_'
  )"
  [[ "$symbol_count" == 13 ]] || fail "Unexpected bridge ABI: $library"
  if "$ndk_bin/llvm-readelf" -d "$library" | grep -q 'libc++_shared.so'; then
    fail "Android artifact must use the static C++ runtime: $library"
  fi
  file "$library"
  shasum -a 256 "$library"
done
