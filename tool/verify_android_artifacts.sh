#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

fail() {
  echo "$1" >&2
  exit 64
}

find_llvm_tool() {
  local name="$1"
  local candidate
  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    for candidate in "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/"$name"; do
      [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return; }
    done
  fi
  if [[ -n "$sdk_root" ]]; then
    for candidate in "$sdk_root"/ndk/*/toolchains/llvm/prebuilt/*/bin/"$name"; do
      [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return; }
    done
  fi
  command -v "$name" 2>/dev/null || command -v "${name#llvm-}" 2>/dev/null ||
    fail "Missing $name (install LLVM/binutils or configure the Android NDK)."
}

nm_tool="$(find_llvm_tool llvm-nm)"
readelf_tool="$(find_llvm_tool llvm-readelf)"

verify_library() {
  local abi="$1"
  local expected_machine="$2"
  local library="$repo_root/android/src/main/jniLibs/$abi/libwallet_engine_core.so"
  [[ -f "$library" ]] || fail "Missing Android artifact: $library"

  local header
  header="$($readelf_tool -h "$library")"
  grep -Eq "Machine:.*$expected_machine" <<<"$header" ||
    fail "Unexpected ELF architecture: $library"

  local symbols unexpected symbol_count
  symbols="$($nm_tool -D --defined-only "$library" | awk '{print $3}' | sed '/^$/d')"
  unexpected="$(
    printf '%s\n' "$symbols" |
      grep -v '^wallet_engine_wallet_core_' || true
  )"
  [[ -z "$unexpected" ]] || {
    printf 'Unexpected exported symbols in %s:\n%s\n' "$library" "$unexpected" >&2
    fail "Android artifact exports symbols outside the owned ABI: $library"
  }
  symbol_count="$(
    printf '%s\n' "$symbols" |
      grep -c '^wallet_engine_wallet_core_'
  )"
  [[ "$symbol_count" == 13 ]] || fail "Unexpected bridge ABI: $library"

  local dynamic dependencies dependency
  dynamic="$($readelf_tool -d "$library")"
  grep -q 'SONAME.*\[libwallet_engine_core.so\]' <<<"$dynamic" ||
    fail "Unexpected SONAME: $library"
  dependencies="$(
    awk '/\(NEEDED\)/ { value=$NF; gsub(/^\[/, "", value); gsub(/\]$/, "", value); print value }' \
      <<<"$dynamic"
  )"
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    case "$dependency" in
      liblog.so|libm.so|libdl.so|libc.so) ;;
      *) fail "Unexpected dynamic dependency $dependency: $library" ;;
    esac
  done <<<"$dependencies"

  echo "$abi: 13 owned exports; system-only dynamic dependencies"
}

verify_library arm64-v8a AArch64
