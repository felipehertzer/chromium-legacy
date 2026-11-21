#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-pool.XXXXXX")"
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
  "$CC_PATH" -std=c11 -Wall -Wextra -Werror -Wunguarded-availability \
    --target="$1-apple-macos" -mmacos-version-min="$2" -isysroot "$SDK_PATH" \
    -I "$ROOT_DIR/third_party/pthreadpool/src" \
    -I "$ROOT_DIR/third_party/pthreadpool/src/include" \
    "$ROOT_DIR/legacy/tests/pthreadpool_atomic_probe.c" "${LINK_ARGS[@]}" \
    -o "$BUILD_DIR/probe"
  "$BUILD_DIR/probe"
}
build_and_run x86_64 10.7
if [[ -n "${PTHREADPOOL_ATOMIC_PROBE_OUTPUT:-}" ]]; then
  cp "$BUILD_DIR/probe" "$PTHREADPOOL_ATOMIC_PROBE_OUTPUT"
fi
# Verify the same memory-ordering code on Apple Silicon too.
if [[ "$(uname -m)" == arm64 ]]; then
  build_and_run arm64 13.0
fi
