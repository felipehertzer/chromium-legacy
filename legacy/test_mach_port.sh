#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-mach.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$(xcrun --find clang++)}"
LINK_ARGS=(-Wl,-fatal_warnings)
# Chromium's compiler bundle uses LLD and does not ship Apple's libLTO.dylib.
if [[ -x "$(dirname "$CXX_PATH")/ld64.lld" ]]; then
    LINK_ARGS+=(-fuse-ld=lld)
fi
COMMON_ARGS=(-std=c++17 -Wall -Wextra -Werror -isysroot "$SDK_PATH" -I "$ROOT_DIR")
# The Mach compatibility implementation has no C++ standard library dependency.
"$CXX_PATH" "${COMMON_ARGS[@]}" -nostdinc++ -target x86_64-apple-macosx10.7 -c \
    "$ROOT_DIR/base/apple/legacy_mach_port.cc" -o "$BUILD_DIR/legacy-mach-lion.o"
"$CXX_PATH" "${COMMON_ARGS[@]}" "$ROOT_DIR/base/apple/legacy_mach_port.cc" \
    "$ROOT_DIR/legacy/tests/mach_port_probe.cc" "${LINK_ARGS[@]}" -o "$BUILD_DIR/mach_port_probe"
# A strong reference would make Lion's dyld fail before the fallback can run.
if ! xcrun nm -m "$BUILD_DIR/mach_port_probe" | grep -E 'weak external _mach_port_construct' >/dev/null; then
    echo "mach_port_construct was not weak-linked" >&2
    exit 1
fi
"$BUILD_DIR/mach_port_probe"
