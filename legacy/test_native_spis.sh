#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-spis.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++}"
ARCHITECTURES=(x64)
if [[ "$(uname -m)" == arm64 ]]; then ARCHITECTURES+=(arm64); fi
for arch in "${ARCHITECTURES[@]}"; do
  if [[ "$arch" == x64 ]]; then
    TARGET_ARGS=(--target=x86_64-apple-macos -mmacos-version-min=10.7)
  else
    TARGET_ARGS=(--target=arm64-apple-macos -mmacos-version-min=11.0)
  fi
  TARGET_ARGS+=(-isysroot "$SDK_PATH")
  for mode in normal fallback; do
    DEFINE=-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS
    if [[ "$mode" == fallback ]]; then DEFINE=-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1; fi
    for probe in capture_region guarded_fd; do
      source="$ROOT_DIR/legacy/tests/$probe"
      frameworks=(-lobjc)
      if [[ "$probe" == capture_region ]]; then
        source+=_probe.mm
        frameworks=(-lobjc -framework AppKit -framework CoreGraphics -framework CoreFoundation)
      else
        source+=_probe.cc
      fi
      "$CXX_PATH" "${TARGET_ARGS[@]}" -std=c++17 -Wall -Wextra -Werror \
        -Wunguarded-availability -fobjc-arc -fno-objc-arc-exceptions -fno-exceptions \
        -fno-rtti -nostdinc++ -I "$ROOT_DIR/buildtools/third_party/libc++" \
        -isystem "$ROOT_DIR/third_party/libc++/src/include" \
        -isystem "$ROOT_DIR/third_party/libc++abi/src/include" \
        -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE \
        -D_LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS -I "$ROOT_DIR" "$DEFINE" \
        -c "$source" -o "$BUILD_DIR/probe.o"
      (cd "$BUILD_DIR" && python3 "$ROOT_DIR/build/toolchain/apple/linker_driver.py" \
        "-Wcrl,driver,$CXX_PATH" "${TARGET_ARGS[@]}" -fuse-ld=lld -Wl,-fatal_warnings \
        -nostdlib++ -lc++abi "$BUILD_DIR/probe.o" "${frameworks[@]}" \
        -o "$BUILD_DIR/probe")
      "$BUILD_DIR/probe"
      if [[ -n "${NATIVE_SPI_PROBE_OUTPUT:-}" ]]; then
        destination="$NATIVE_SPI_PROBE_OUTPUT.$probe.$arch"
        if [[ "$mode" == fallback ]]; then destination+=".fallback"; fi
        cp "$BUILD_DIR/probe" "$destination"
      fi
    done
  done
done
