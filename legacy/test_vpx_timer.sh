#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-vpx.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [[ -n "${CC:-}" ]]; then
  CC_PATH="$CC"
elif [[ -x "$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang" ]]; then
  CC_PATH="$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang"
else
  CC_PATH="$(xcrun --find clang)"
fi
LINK_ARGS=(-Wl,-fatal_warnings)
if [[ -x "$(dirname "$CC_PATH")/ld64.lld" ]]; then
  LINK_ARGS+=(-fuse-ld=lld)
fi
build_and_run() {
  local config_arch=x64
  if [[ "$1" == arm64 ]]; then config_arch=arm64; fi
  "$CC_PATH" -std=c11 -Wall -Wextra -Werror -Wunguarded-availability \
    --target="$1-apple-macos" -mmacos-version-min="$2" -isysroot "$SDK_PATH" \
    "$3" \
    -I "$ROOT_DIR/third_party/libvpx/source/config/linux/$config_arch" \
    -I "$ROOT_DIR/third_party/libvpx/source/libvpx" \
    "$ROOT_DIR/legacy/tests/vpx_timer_probe.c" "${LINK_ARGS[@]}" \
    -o "$BUILD_DIR/probe"
  "$BUILD_DIR/probe"
}
build_and_run x86_64 10.7 -UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS
if [[ -n "${VPX_TIMER_PROBE_OUTPUT:-}" ]]; then
  cp "$BUILD_DIR/probe" "$VPX_TIMER_PROBE_OUTPUT"
fi
build_and_run x86_64 10.7 -DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1
if [[ -n "${VPX_TIMER_PROBE_OUTPUT:-}" ]]; then
  cp "$BUILD_DIR/probe" "$VPX_TIMER_PROBE_OUTPUT.fallback"
fi
# Apple Silicon's different timebase also checks the integer scaling path.
if [[ "$(uname -m)" == arm64 ]]; then
  build_and_run arm64 13.0 -UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS
  build_and_run arm64 13.0 -DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1
fi
