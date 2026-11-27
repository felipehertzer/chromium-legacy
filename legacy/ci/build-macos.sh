#!/bin/bash
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
set -euo pipefail
: "${CHROMIUM_LEGACY_WORKSPACE:?Set the prepared Chromium workspace containing src}"
: "${CHROMIUM_LION_SYSTEM_ROOT:?Set the extracted original Lion system root}"
: "${CHROMIUM_LEGACY_OUTPUT:?Set a fresh output directory outside src}"
cd "$CHROMIUM_LEGACY_WORKSPACE/src"
if [[ "$(git rev-parse HEAD)" != "${GITHUB_SHA:-$(git rev-parse HEAD)}" ]]; then
  echo 'Prepared checkout must match the selected workflow commit.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Preserving uncommitted source changes; refusing to build a release.' >&2
  exit 1
fi
mkdir "$CHROMIUM_LEGACY_WORKSPACE/.legacy-ci.lock" || {
  echo 'Another build owns the prepared workspace.' >&2
  exit 1
}
trap 'rmdir "$CHROMIUM_LEGACY_WORKSPACE/.legacy-ci.lock"' EXIT
python3 - <<'PY'
import os,pathlib,platform,shutil
if platform.system()!='Darwin': raise SystemExit('A modern Mac build host is required.')
root=pathlib.Path.cwd()
if shutil.disk_usage(root).free < 30*1024**3:
    raise SystemExit('At least 30 GiB free is required for an incremental prepared build; allow 150+ GiB for initial setup.')
for file in ['out/Lion/args.gn','../rust-lion-compiler.gni','../crubit-lion.gni']:
    if not pathlib.Path(file).is_file(): raise SystemExit('Bootstrap the workspace first: missing '+file)
if not pathlib.Path(os.environ['CHROMIUM_LION_SYSTEM_ROOT']).is_dir():
    raise SystemExit('Lion system root is unavailable.')
PY
python3 legacy/apply_dependency_patches.py --check
python3 legacy/apply_rust_std_patches.py --check
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s legacy/tests -p 'test_*.py'
buildtools/mac/gn gen out/Lion --fail-on-unused-args
ninja -C out/Lion -j "${CHROMIUM_LEGACY_JOBS:-4}" -d keeprsp chrome
package=(python3 legacy/package_app.py --app out/Lion/Chromium.app
  --output "$CHROMIUM_LEGACY_OUTPUT/staged"
  --system-root "$CHROMIUM_LION_SYSTEM_ROOT")
if [[ -n "${CHROMIUM_LION_SUPPLEMENTAL_ROOT_1:-}" ]]; then
  package+=(--supplemental-root "$CHROMIUM_LION_SUPPLEMENTAL_ROOT_1")
fi
if [[ -n "${CHROMIUM_LION_SUPPLEMENTAL_ROOT_2:-}" ]]; then
  package+=(--supplemental-root "$CHROMIUM_LION_SUPPLEMENTAL_ROOT_2")
fi
"${package[@]}"
python3 legacy/package_dmg.py --app "$CHROMIUM_LEGACY_OUTPUT/staged/Chromium.app" \
  --metadata "$CHROMIUM_LEGACY_OUTPUT/staged" --output "$CHROMIUM_LEGACY_OUTPUT/assets"
