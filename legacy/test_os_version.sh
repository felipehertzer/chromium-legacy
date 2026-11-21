#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-probe.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$(xcrun --find clang++)}"
LINK_ARGS=(-Wl,-fatal_warnings)
# Chromium's compiler bundle uses LLD and does not ship Apple's libLTO.dylib.
if [[ -x "$(dirname "$CXX_PATH")/ld64.lld" ]]; then
    LINK_ARGS+=(-fuse-ld=lld)
fi
COMMON_ARGS=(-std=c++17 -fobjc-arc -Wall -Wextra -Werror -isysroot "$SDK_PATH" -I "$ROOT_DIR")
# Compile the production fallback for Lion, even on Apple silicon hosts.
# This Foundation-only helper needs no C++ standard library headers. The full
# browser's C++ runtime is checked separately by legacy:runtime_probe.
"$CXX_PATH" "${COMMON_ARGS[@]}" -nostdinc++ -target x86_64-apple-macosx10.7 -c \
    "$ROOT_DIR/base/mac/legacy_os_compat.mm" -o "$BUILD_DIR/legacy-lion.o"
# Execute the same implementation natively, without the Chromium dependency tree.
"$CXX_PATH" "${COMMON_ARGS[@]}" "$ROOT_DIR/base/mac/legacy_os_compat.mm" \
    "$ROOT_DIR/legacy/tests/os_version_probe.mm" -framework Foundation "${LINK_ARGS[@]}" -o "$BUILD_DIR/os_version_probe"
"$BUILD_DIR/os_version_probe"
