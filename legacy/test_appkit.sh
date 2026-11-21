#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-appkit.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [[ -n "${CXX:-}" ]]; then
  CXX_PATH="$CXX"
elif [[ -x "$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++" ]]; then
  CXX_PATH="$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++"
else
  CXX_PATH="$(xcrun --find clang++)"
fi
LINK_ARGS=(-Wl,-fatal_warnings)
if [[ -x "$(dirname "$CXX_PATH")/ld64.lld" ]]; then
  LINK_ARGS+=(-fuse-ld=lld)
fi
TARGET_ARGS=(--target=x86_64-apple-macos -isysroot "$SDK_PATH"
  -mmacos-version-min=10.7)
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
  if [[ "$mode" == fallback ]]; then
    EXTRA_ARGS=(-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1)
  fi
  "$CXX_PATH" "${COMMON_ARGS[@]}" "${EXTRA_ARGS[@]}" \
    -c "$ROOT_DIR/legacy/tests/appkit_probe.mm" -o "$BUILD_DIR/probe.o"
  "$CXX_PATH" "${COMMON_ARGS[@]}" "${EXTRA_ARGS[@]}" \
    -c "$ROOT_DIR/ui/base/cocoa/appkit_utils.mm" -o "$BUILD_DIR/appkit.o"
  (cd "$BUILD_DIR" && python3 "$ROOT_DIR/build/toolchain/apple/linker_driver.py" \
    "-Wcrl,driver,$CXX_PATH" "${TARGET_ARGS[@]}" "${LINK_ARGS[@]}" \
    "$BUILD_DIR/probe.o" "$BUILD_DIR/appkit.o" -nostdlib++ -lobjc \
    -framework Foundation -framework AppKit -framework CoreServices -framework CoreText \
    -weak_framework UniformTypeIdentifiers -o "$BUILD_DIR/probe")
  "$BUILD_DIR/probe"
  if [[ -n "${APPKIT_PROBE_OUTPUT:-}" ]]; then
    destination="$APPKIT_PROBE_OUTPUT"
    if [[ "$mode" == fallback ]]; then destination+=".fallback"; fi
    cp "$BUILD_DIR/probe" "$destination"
  fi
done
