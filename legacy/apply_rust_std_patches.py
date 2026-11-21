#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Patch the distributed Rust source only after validating its exact contents."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_apply(directory, patch, *options):
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')}
    result = subprocess.run(['git', 'apply', *options, str(patch)],
                            cwd=directory, env=environment, text=True,
                            capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'Rust source patch failed')
    return result.stdout


def apply_patches(toolchain, manifest_path, check_only=False):
    toolchain = toolchain.resolve()
    manifest_path = manifest_path.resolve()
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('schema_version') != 1:
        raise ValueError('Unsupported Rust patch manifest')
    if not re.fullmatch(r'[0-9a-f]{40}', manifest['revision']):
        raise ValueError('Expected a full Rust revision')
    version = (toolchain / 'VERSION').read_bytes()
    if (digest(version) != manifest['toolchain_version_sha256'] or
            manifest['revision'].encode() not in version):
        raise ValueError('Expected the exact pinned Chromium Rust toolchain')
    source = (toolchain / 'lib/rustlib/src/rust').resolve()
    patch = (manifest_path.parent / manifest['patch']).resolve()
    if not patch.is_relative_to(manifest_path.parent):
        raise ValueError('Rust patch must stay inside the legacy directory')
    entries, current, pending = {}, {}, []
    for entry in manifest['files']:
        relative = Path(entry['path'])
        target = (source / relative).resolve()
        if (relative.is_absolute() or '..' in relative.parts or
                not target.is_relative_to(source) or entry['path'] in entries):
            raise ValueError('Rust source path must stay inside the source tree')
        if not all(re.fullmatch(r'[0-9a-f]{64}', entry[key])
                   for key in ('before', 'after')):
            raise ValueError('Expected complete Rust source SHA-256 hashes')
        data = target.read_bytes()
        fingerprint = digest(data)
        if fingerprint not in (entry['before'], entry['after']):
            raise ValueError(f'{relative}: source differs from the pinned versions')
        entries[entry['path']] = entry
        current[entry['path']] = data
        if fingerprint == entry['before']:
            pending.append(entry['path'])
    if not entries:
        raise ValueError('Empty Rust patch manifest')
    if not pending:
        print('Rust std: already applied')
        return
    # Preflight in a disposable tree, including recovery from an interrupted
    # earlier application. Validate both the patch paths and resulting hashes.
    with tempfile.TemporaryDirectory(prefix='chromium-rust-patch-') as temporary:
        stage = Path(temporary)
        listed = git_apply(stage, patch, '--numstat')
        patch_paths = [line.split('\t', 2)[2] for line in listed.splitlines()]
        if set(patch_paths) != set(entries) or len(patch_paths) != len(entries):
            raise ValueError('Rust patch paths do not match the manifest')
        for name, data in current.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            if name not in pending:
                git_apply(stage, patch, '--reverse', '--include=' + name)
        git_apply(stage, patch, '--check', '--whitespace=error')
        git_apply(stage, patch, '--whitespace=error')
        for name, entry in entries.items():
            if digest((stage / name).read_bytes()) != entry['after']:
                raise ValueError(f'{name}: patched hash does not match')
        if check_only:
            print('Rust std: patch applies cleanly')
            return
        for name, data in current.items():
            if (source / name).read_bytes() != data:
                raise ValueError(f'{name}: source changed during preflight')
        for name in pending:
            target = source / name
            temporary_name = None
            try:
                with tempfile.NamedTemporaryFile(dir=target.parent,
                                                 delete=False) as output:
                    temporary_name = Path(output.name)
                    output.write((stage / name).read_bytes())
                    output.flush()
                    os.fsync(output.fileno())
                temporary_name.chmod(target.stat().st_mode & 0o777)
                os.replace(temporary_name, target)
            finally:
                if temporary_name is not None:
                    temporary_name.unlink(missing_ok=True)
    print(f'Rust std: patched {len(pending)} files')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    legacy = Path(__file__).resolve().parent
    try:
        apply_patches(legacy.parent / 'third_party/rust-toolchain',
                      legacy / 'rust_std_patches.json', args.check)
    except (OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
