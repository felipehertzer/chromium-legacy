#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-secure-archive.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++}"
ARCHITECTURES=(x64)

for arch in "${ARCHITECTURES[@]}"; do
  if [[ "$arch" == "x64" ]]; then
    TARGET_ARGS=(--target=x86_64-apple-macos -mmacos-version-min=10.7)
  else
    TARGET_ARGS=(--target=arm64-apple-macos -mmacos-version-min=11.0)
  fi
  TARGET_ARGS+=(-isysroot "$SDK_PATH")
  COMMON_ARGS=(-std=c++17 -Wall -Wextra -Werror -Wunguarded-availability
    -fobjc-arc -fno-exceptions -fno-objc-arc-exceptions -I "$ROOT_DIR"
    -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE
    -D_LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS
    -nostdinc++ -I "$ROOT_DIR/buildtools/third_party/libc++"
    -isystem "$ROOT_DIR/third_party/libc++/src/include"
    -isystem "$ROOT_DIR/third_party/libc++abi/src/include"
    "${TARGET_ARGS[@]}")
  for mode in normal fallback; do
    EXTRA_ARGS=(-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if [[ "$mode" == "fallback" ]]; then
      EXTRA_ARGS=(-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1)
    fi
    "$CXX_PATH" "${COMMON_ARGS[@]}" "${EXTRA_ARGS[@]}" \
      -c "$ROOT_DIR/legacy/tests/secure_archive_probe.mm" -o "$BUILD_DIR/probe.o"
    (cd "$BUILD_DIR" && python3 "$ROOT_DIR/build/toolchain/apple/linker_driver.py" \
      "-Wcrl,driver,$CXX_PATH" "${TARGET_ARGS[@]}" -fuse-ld=lld -Wl,-fatal_warnings \
      "$BUILD_DIR/probe.o" -nostdlib++ -lobjc -framework Foundation \
       -o "$BUILD_DIR/probe")
    "$BUILD_DIR/probe"
    if [[ -n "${SECURE_ARCHIVE_PROBE_OUTPUT:-}" ]]; then
      destination="$SECURE_ARCHIVE_PROBE_OUTPUT.$arch"
      if [[ "$mode" == "fallback" ]]; then destination+=".fallback"; fi
      cp "$BUILD_DIR/probe" "$destination"
    fi
  done
done
