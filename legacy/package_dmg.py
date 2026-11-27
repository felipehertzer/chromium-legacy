#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Create and verify a Lion-readable HFS+/UDZO DMG of a signed application."""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile


def run(*arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify_app(app, manifest):
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    for entry in manifest['binaries']:
        path = (app / entry['path']).resolve(strict=True)
        if not path.is_relative_to(app.resolve()) or sha256(path) != entry['sha256']:
            raise ValueError(f'Application binary differs from manifest: {entry["path"]}')
    snapshot = app / 'Contents/Frameworks/Chromium Framework.framework/Resources/v8_context_snapshot.x86_64.bin'
    if sha256(snapshot) != manifest['context_snapshot']['sha256']:
        raise ValueError('V8 context snapshot differs from manifest')
    return {str(p.relative_to(app)): str(p.readlink())
            for p in app.rglob('*') if p.is_symlink()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True,
                        help='Directory containing build-info.json and README.txt')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('DMG creation requires a macOS build host')
    app = args.app.resolve(strict=True)
    metadata = args.metadata.resolve(strict=True)
    manifest = json.loads((metadata / 'build-info.json').read_text())
    version = manifest['version']
    if not re.fullmatch(r'\d+(?:\.\d+){3}', version):
        raise ValueError('Expected a four-part browser version')
    if manifest['architecture'] != 'x86_64' or manifest['minimum_macos_target'] != '10.7':
        raise ValueError('This package is for the Intel/10.7 port')
    original_symlinks = verify_app(app, manifest)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / f'Chromium-Legacy-{version}-beta-x64-experimental.dmg'
    if dmg.exists():
        raise ValueError(f'Preserving existing image: {dmg}')
    with tempfile.TemporaryDirectory(prefix='chromium-dmg-', dir=output) as temporary:
        temporary = Path(temporary)
        staging = temporary / 'contents'
        staging.mkdir()
        run('/usr/bin/ditto', str(app), str(staging / 'Chromium.app'))
        (staging / 'Applications').symlink_to('/Applications', target_is_directory=True)
        shutil.copyfile(metadata / 'README.txt', staging / 'README.txt')
        evidence = staging / 'Validation'
        evidence.mkdir()
        for name in ['build-info.json', 'catalina-browser-report.json',
                     'catalina-installation-report.json', 'signatures.json',
                     'bundle-abi.json']:
            if (metadata / name).is_file():
                shutil.copyfile(metadata / name, evidence / name)
        # APFS and newer UDIF compression formats cannot be read by Lion.
        run('/usr/bin/hdiutil', 'create', '-srcfolder', str(staging), '-fs',
            'HFS+', '-format', 'UDZO', '-volname', 'Chromium Legacy', str(dmg))
        run('/usr/bin/hdiutil', 'verify', str(dmg))
        mount = temporary / 'mounted'
        mount.mkdir()
        attached = False
        try:
            run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-owners',
                'off', '-mountpoint', str(mount), str(dmg))
            attached = True
            if verify_app(mount / 'Chromium.app', manifest) != original_symlinks:
                raise ValueError('Application symlinks changed inside the DMG')
            if (mount / 'Applications').readlink() != Path('/Applications'):
                raise ValueError('Applications shortcut changed inside the DMG')
        finally:
            if attached:
                run('/usr/bin/hdiutil', 'detach', str(mount))
    result = {'filename': dmg.name, 'bytes': dmg.stat().st_size,
              'sha256': sha256(dmg), 'filesystem': 'HFS+', 'format': 'UDZO',
              'image_verify': 'passed', 'mounted_signatures': 'passed',
              'binary_hashes': 'passed', 'context_snapshot': 'passed',
              'application_symlinks': len(original_symlinks),
              'source_commit': manifest['source_commit']}
    (output / 'dmg-validation.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(f'{result["sha256"]}  {dmg.name}\n')
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    main()
