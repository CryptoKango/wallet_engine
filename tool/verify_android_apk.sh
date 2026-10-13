#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path-to-apk" >&2
  exit 64
fi

apk="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[[ -f "$apk" ]] || { echo "APK not found: $apk" >&2; exit 66; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
apk_entries="$(unzip -Z1 "$apk")"

for abi in arm64-v8a; do
  entry="lib/$abi/libwallet_engine_core.so"
  source_library="$repo_root/android/src/main/jniLibs/$abi/libwallet_engine_core.so"
  grep -Fxq "$entry" <<<"$apk_entries" || {
    echo "APK is missing $entry" >&2
    exit 64
  }
  cmp -s <(unzip -p "$apk" "$entry") "$source_library" || {
    echo "APK contains a modified $entry" >&2
    exit 64
  }
  echo "$abi: packaged artifact matches the locked source file"
done
