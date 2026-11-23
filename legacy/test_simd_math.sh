#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-simd-math.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++}"
for mode in normal fallback; do
  MODE_ARGS=(-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if [[ "$mode" == "fallback" ]]; then
    MODE_ARGS=(-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1)
  fi
  "$CXX_PATH" -std=c++17 -Wall -Wextra -Werror -Wunguarded-availability \
    -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE \
    -fno-exceptions -fno-rtti -nostdinc++ -nostdlib++ \
    -I "$ROOT_DIR/buildtools/third_party/libc++" \
    -isystem "$ROOT_DIR/third_party/libc++/src/include" \
    -isystem "$ROOT_DIR/third_party/libc++abi/src/include" \
    -target x86_64-apple-macosx10.7 -isysroot "$SDK_PATH" -I "$ROOT_DIR" \
    "${MODE_ARGS[@]}" "$ROOT_DIR/legacy/tests/simd_math_probe.cc" \
    -fuse-ld=lld -Wl,-fatal_warnings -o "$BUILD_DIR/probe"
  "$BUILD_DIR/probe"
  if [[ -n "${SIMD_MATH_PROBE_OUTPUT:-}" ]]; then
    destination="$SIMD_MATH_PROBE_OUTPUT"
    if [[ "$mode" == "fallback" ]]; then destination+=".fallback"; fi
    cp "$BUILD_DIR/probe" "$destination"
  fi
done
