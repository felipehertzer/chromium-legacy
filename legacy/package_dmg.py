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
import os
import shutil
import stat
import subprocess
import tempfile
import zipfile

from release_privacy import (public_manifest, public_readme, require_public_tree,
                             verify_hfs_no_xattrs, clear_image_finder_info)


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
                        help='Private build-info.json and optional Catalina runtime report directory')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--zip', action='store_true', help='Also create and verify a clean ZIP')
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
    report_file = metadata / "catalina-browser-report.json"
    browser_report = json.loads(report_file.read_text()) if report_file.is_file() else None
    public = public_manifest(manifest, browser_report)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / f'Chromium-Legacy-{version}-beta-x64-experimental.dmg'
    archive = dmg.with_suffix('.zip')
    if dmg.exists() or (args.zip and archive.exists()):
        raise ValueError('Preserving existing release files')
    zip_result = None
    with tempfile.TemporaryDirectory(prefix='chromium-dmg-', dir=output) as temporary:
        temporary = Path(temporary)
        staging = temporary / 'contents'
        staging.mkdir()
        run('/usr/bin/ditto', '--norsrc', '--noextattr', '--noacl', '--noqtn', '--noclone',
            str(app), str(staging / 'Chromium.app'))
        (staging / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (staging / 'README.txt').write_text(public_readme(public))
        evidence = staging / 'Validation'
        evidence.mkdir()
        (evidence / 'build-info.json').write_text(json.dumps(public, indent=2) + '\n')
        require_public_tree(staging, allow_local_provenance=True)
        # Author HFS+ directly: -srcfolder copies protected local provenance
        # metadata on some macOS versions even after a metadata-free copy.
        # The hybrid HFS+ author omits extended attributes; verify the raw fork.
        filesystem = temporary / 'filesystem.dmg'
        run('/usr/bin/hdiutil', 'makehybrid', '-hfs', '-hfs-volume-name',
            'Chromium Legacy', '-o', str(filesystem), str(staging))
        verify_hfs_no_xattrs(filesystem)
        # The HFS+ author creates Finder type/creator information that modern
        # strict code validation rejects. Normalize those ordinary catalog fields
        # in our own image, preserving symlinks and each file's original mode.
        writable = temporary / 'filesystem-writable.dmg'
        run('/usr/bin/hdiutil', 'convert', str(filesystem), '-format', 'UDRW',
            '-o', str(writable))
        writable_mount = temporary / 'writable-mounted'
        writable_mount.mkdir()
        writable_attached = False
        try:
            run('/usr/bin/hdiutil', 'attach', '-readwrite', '-nobrowse', '-owners',
                'off', '-mountpoint', str(writable_mount), str(writable))
            writable_attached = True
            finder_info_cleared = clear_image_finder_info(writable_mount)
            if {p.name for p in writable_mount.iterdir()} != {p.name for p in staging.iterdir()}:
                raise ValueError('Unexpected files appeared on the writable image')
            if verify_app(writable_mount / 'Chromium.app', manifest) != original_symlinks:
                raise ValueError('Application symlinks changed while authoring HFS+')
            require_public_tree(writable_mount)
        finally:
            if writable_attached:
                run('/usr/bin/hdiutil', 'detach', str(writable_mount))
        image_privacy = verify_hfs_no_xattrs(writable)
        run('/usr/bin/hdiutil', 'convert', str(writable), '-format', 'UDZO',
            '-o', str(dmg))
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
            privacy = require_public_tree(mount)
            if (mount / 'Applications').readlink() != Path('/Applications'):
                raise ValueError('Applications shortcut changed inside the DMG')
        finally:
            if attached:
                run('/usr/bin/hdiutil', 'detach', str(mount))
        if args.zip:
            # Write ZIP entries ourselves: no AppleDouble, xattrs, UID/GID,
            # local timestamps or other creator filesystem metadata are encoded.
            with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as zipped:
                entries = [(p, str(p.relative_to(staging)))
                           for p in [staging / 'Chromium.app', *(staging / 'Chromium.app').rglob('*')]]
                entries += [(staging / 'README.txt', 'README.txt'),
                            (evidence / 'build-info.json', 'build-info.json')]
                for path, name in entries:
                    mode = path.lstat().st_mode
                    directory = stat.S_ISDIR(mode)
                    entry = zipfile.ZipInfo(name + ('/' if directory else ''),
                                            date_time=(1980, 1, 1, 0, 0, 0))
                    entry.create_system = 3
                    entry.external_attr = (mode & 0xFFFF) << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    if directory:
                        entry.external_attr |= 0x10
                        zipped.writestr(entry, b'')
                    elif stat.S_ISLNK(mode):
                        zipped.writestr(entry, os.fsencode(os.readlink(path)))
                    else:
                        with path.open('rb') as source, zipped.open(entry, 'w') as target:
                            shutil.copyfileobj(source, target, 1024 * 1024)
            with zipfile.ZipFile(archive) as zipped:
                if zipped.testzip() is not None:
                    raise ValueError('ZIP CRC verification failed')
                if any(item.extra or item.comment for item in zipped.infolist()):
                    raise ValueError('Unexpected creator metadata in ZIP entries')
                if any(name.startswith('__MACOSX/') or Path(name).name.startswith('._')
                       for name in zipped.namelist()):
                    raise ValueError('AppleDouble metadata in ZIP')
                if len(zipped.namelist()) != len(set(zipped.namelist())):
                    raise ValueError('Duplicate ZIP entries')
            extracted = temporary / 'zip-roundtrip'
            extracted.mkdir()
            run('/usr/bin/ditto', '-x', '-k', str(archive), str(extracted))
            if verify_app(extracted / 'Chromium.app', manifest) != original_symlinks:
                raise ValueError('Application symlinks changed in ZIP')
            zip_result = {'filename': archive.name, 'bytes': archive.stat().st_size,
                          'sha256': sha256(archive), 'crc': 'passed',
                          'extracted_signatures': 'passed', 'binary_hashes': 'passed',
                          'privacy_scan': require_public_tree(extracted, allow_local_provenance=True),
                          'serialized_extended_attributes': 'absent'}
    result = {'filename': dmg.name, 'bytes': dmg.stat().st_size,
              'sha256': sha256(dmg), 'filesystem': 'HFS+', 'format': 'UDZO',
              'image_verify': 'passed', 'mounted_signatures': 'passed',
              'binary_hashes': 'passed', 'context_snapshot': 'passed',
              'application_symlinks': len(original_symlinks),
              'source_commit': manifest['source_commit'],
              'privacy_scan': privacy, 'image_privacy': image_privacy,
              'finder_info_entries_normalized': finder_info_cleared}
    (output / 'dmg-validation.json').write_text(json.dumps(result, indent=2) + '\n')
    sums = f'{result["sha256"]}  {dmg.name}\n'
    if zip_result is not None:
        (output / 'zip-validation.json').write_text(json.dumps(zip_result, indent=2) + '\n')
        sums += f'{zip_result["sha256"]}  {archive.name}\n'
    (output / 'build-info.json').write_text(json.dumps(public, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(sums)
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    main()
