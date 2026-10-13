#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 TrustWalletCore.tar.xz [output-directory]" >&2
  exit 64
fi

archive="$1"
output_dir="${2:-darwin/wallet_engine}"
expected_sha256="6d87c490c16a12fb51d3ddb5bca4d277f08d26aad172c48deb773d3dd4b72567"
actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Wallet Core release archive SHA-256 mismatch" >&2
  exit 65
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_root="$(mktemp -d /tmp/wallet-engine-apple-xcframework.XXXXXX)"
trap 'rm -rf "$build_root"' EXIT

tar -xf "$archive" -C "$build_root" \
  ./WalletCoreCommon.xcframework \
  ./include

common="$build_root/WalletCoreCommon.xcframework"
bridge_source="$repo_root/native/bridge/src/wallet_engine_wallet_core.cpp"
bridge_headers="$repo_root/native/bridge/include"
framework_info="$repo_root/native/bridge/apple/Info.plist"
framework_module="$repo_root/native/bridge/apple/module.modulemap"
version_define='-DWALLET_ENGINE_WALLET_CORE_VERSION="4.8.4"'
commit_define='-DWALLET_ENGINE_WALLET_CORE_COMMIT="d40d24a63d92619167903369308bf0e2f7eb3a59"'

build_library() {
  local sdk="$1"
  local framework_slice="$2"
  local minimum_flag="$3"
  local destination="$4"
  shift 4

  mkdir -p "$(dirname "$destination")"
  xcrun --sdk "$sdk" clang++ \
    -std=c++17 \
    -dynamiclib \
    "$@" \
    "$minimum_flag" \
    -fvisibility=hidden \
    -Wall -Wextra -Werror \
    "$version_define" \
    "$commit_define" \
    -I"$bridge_headers" \
    -I"$build_root/include" \
    -F"$common/$framework_slice" \
    "$bridge_source" \
    -framework WalletCoreCommon \
    -framework Foundation \
    -framework Security \
    -lz \
    -Wl,-dead_strip \
    -Wl,-install_name,@rpath/WalletEngineCore.framework/WalletEngineCore \
    -o "$destination"
}

prepare_framework() {
  local framework="$1"
  mkdir -p "$framework/Headers" "$framework/Modules"
  install -m 0644 \
    "$bridge_headers/wallet_engine_wallet_core.h" \
    "$framework/Headers/wallet_engine_wallet_core.h"
  install -m 0644 "$framework_module" "$framework/Modules/module.modulemap"
  install -m 0644 "$framework_info" "$framework/Info.plist"
}

ios_framework="$build_root/bridge/ios-arm64/WalletEngineCore.framework"
ios_simulator_framework="$build_root/bridge/ios-simulator/WalletEngineCore.framework"
prepare_framework "$ios_framework"
prepare_framework "$ios_simulator_framework"

build_library \
  iphoneos \
  ios-arm64 \
  -mios-version-min=14.0 \
  "$ios_framework/WalletEngineCore" \
  -arch arm64

build_library \
  iphonesimulator \
  ios-arm64_x86_64-simulator \
  -mios-simulator-version-min=14.0 \
  "$ios_simulator_framework/WalletEngineCore" \
  -arch arm64 -arch x86_64

required_symbols=(
  wallet_engine_wallet_core_abi_version
  wallet_engine_wallet_core_self_test
  wallet_engine_wallet_core_sign_json
  wallet_engine_wallet_core_sign_secp256k1
  wallet_engine_wallet_core_sign_proto
  wallet_engine_wallet_core_sign_evm_message
  wallet_engine_wallet_core_derive_key
  wallet_engine_wallet_core_inspect_key
)
for library in "$build_root"/bridge/*/WalletEngineCore.framework/WalletEngineCore; do
  symbols="$(nm -gU "$library")"
  for symbol in "${required_symbols[@]}"; do
    if ! grep -q "_$symbol" <<<"$symbols"; then
      echo "Missing exported bridge symbol in $library: $symbol" >&2
      exit 66
    fi
  done
done

mkdir -p "$output_dir"
xcframework="$output_dir/WalletEngineCore.xcframework"
archive_output="$output_dir/WalletEngineCore.xcframework.zip"
rm -rf "$xcframework"
rm -f "$archive_output"
xcodebuild -create-xcframework \
  -framework "$ios_framework" \
  -framework "$ios_simulator_framework" \
  -output "$xcframework"

find "$xcframework" -exec touch -t 198001010000 {} +

plutil -lint "$xcframework/Info.plist"
file "$xcframework"/*/WalletEngineCore.framework/WalletEngineCore
shasum -a 256 "$xcframework"/*/WalletEngineCore.framework/WalletEngineCore

if [[ "${WALLET_ENGINE_SKIP_ARCHIVE:-0}" != "1" ]]; then
  (
    cd "$output_dir"
    find WalletEngineCore.xcframework -print | LC_ALL=C sort | \
      zip -X -q "$archive_output" -@
  )
  shasum -a 256 "$archive_output"
fi
