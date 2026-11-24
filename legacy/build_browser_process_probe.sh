#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:?Usage: build_browser_process_probe.sh OUTPUT [x64|arm64]}"
if [[ "$OUTPUT_PATH" != /* ]]; then OUTPUT_PATH="$PWD/$OUTPUT_PATH"; fi
ARCHITECTURE="${2:-$(uname -m)}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-process.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CC_PATH="${CC:-$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang}"
case "$ARCHITECTURE" in
  x64|x86_64) TARGET_ARGS=(--target=x86_64-apple-macos -mmacos-version-min=10.7) ;;
  arm64) TARGET_ARGS=(--target=arm64-apple-macos -mmacos-version-min=13.0) ;;
  *) echo "Unsupported architecture: $ARCHITECTURE" >&2; exit 2 ;;
esac
TARGET_ARGS+=(-isysroot "$SDK_PATH")
"$CC_PATH" "${TARGET_ARGS[@]}" -std=c11 -Wall -Wextra -Werror \
  -Wunguarded-availability -c "$ROOT_DIR/legacy/tests/browser_process_probe.c" \
  -o "$BUILD_DIR/probe.o"
(cd "$BUILD_DIR" && python3 "$ROOT_DIR/build/toolchain/apple/linker_driver.py" \
  "-Wcrl,driver,$CC_PATH" "${TARGET_ARGS[@]}" -fuse-ld=lld -Wl,-fatal_warnings \
  "$BUILD_DIR/probe.o" -lsandbox -framework ApplicationServices \
  -framework CoreFoundation -o "$OUTPUT_PATH")
