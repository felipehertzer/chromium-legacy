#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-media.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$ROOT_DIR/third_party/llvm-build/Release+Asserts/bin/clang++}"
for architecture in x86_64 arm64; do
  if [[ "$architecture" == arm64 && "$(uname -m)" != arm64 ]]; then continue; fi
  minimum=10.7
  if [[ "$architecture" == arm64 ]]; then minimum=11.0; fi
  TARGET_ARGS=(--target="$architecture-apple-macos" -isysroot "$SDK_PATH"
    -mmacos-version-min="$minimum")
  for mode in normal fallback; do
    DEFINE=-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS
    if [[ "$mode" == fallback ]]; then DEFINE=-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1; fi
    "$CXX_PATH" "${TARGET_ARGS[@]}" -std=c++17 -Wall -Wextra -Werror \
      -Wunguarded-availability -fobjc-arc -fno-objc-arc-exceptions -fno-exceptions \
      -fno-rtti -nostdinc++ -I "$ROOT_DIR/buildtools/third_party/libc++" \
      -isystem "$ROOT_DIR/third_party/libc++/src/include" \
      -isystem "$ROOT_DIR/third_party/libc++abi/src/include" \
      -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE \
      -D_LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS -I "$ROOT_DIR" "$DEFINE" -c "$ROOT_DIR/legacy/tests/media_platform_probe.mm" \
      -o "$BUILD_DIR/probe.o"
    (cd "$BUILD_DIR" && python3 "$ROOT_DIR/build/toolchain/apple/linker_driver.py" \
      "-Wcrl,driver,$CXX_PATH" "${TARGET_ARGS[@]}" -fuse-ld=lld -Wl,-fatal_warnings \
      -nostdlib++ -lc++abi -lobjc "$BUILD_DIR/probe.o" -framework CoreVideo \
      -framework CoreFoundation -o "$BUILD_DIR/probe")
    "$BUILD_DIR/probe"
    if [[ "$architecture" == x86_64 && -n "${MEDIA_PLATFORM_PROBE_OUTPUT:-}" ]]; then
      destination="$MEDIA_PLATFORM_PROBE_OUTPUT"
      if [[ "$mode" == fallback ]]; then destination+=".fallback"; fi
      cp "$BUILD_DIR/probe" "$destination"
    fi
  done
done
