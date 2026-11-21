#!/usr/bin/env python3
"""Apply compatibility patches only to their exact pinned dependency revisions."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def git(repo, *args):
    return subprocess.run(
        ['git', '-C', str(repo), *args],
        check=False, text=True, capture_output=True,
    )


def apply_patches(root, manifest_path, check_only=False):
    root = Path(root).resolve()
    manifest_path = Path(manifest_path).resolve()
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('schema_version') != 1:
        raise ValueError('Unsupported dependency patch manifest version')
    pending = []
    for entry in manifest['patches']:
        repo = (root / entry['path']).resolve()
        patch = (manifest_path.parent / entry['patch']).resolve()
        if not repo.is_relative_to(root) or repo == root:
            raise ValueError('Dependency path must stay inside the checkout')
        if not patch.is_relative_to(manifest_path.parent):
            raise ValueError('Patch path must stay inside the legacy directory')
        revision = entry['revision']
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Dependency revisions must be full commit IDs')
        top = git(repo, 'rev-parse', '--show-toplevel')
        head = git(repo, 'rev-parse', 'HEAD')
        if top.returncode or Path(top.stdout.strip()).resolve() != repo:
            raise ValueError(f'{entry["path"]}: expected a separate dependency checkout')
        if head.returncode or head.stdout.strip() != revision:
            raise ValueError(f'{entry["path"]}: expected pinned revision {revision}')
        if not git(repo, 'apply', '--reverse', '--check', str(patch)).returncode:
            print(f'{entry["path"]}: already applied')
            continue
        ready = git(repo, 'apply', '--check', '--whitespace=error', str(patch))
        if ready.returncode:
            raise ValueError(f'{entry["path"]}: patch does not apply:\n{ready.stderr}')
        pending.append((repo, patch))
    for repo, patch in pending:
        if check_only:
            print(f'{repo.relative_to(root)}: patch applies cleanly')
            continue
        result = git(repo, 'apply', '--whitespace=error', str(patch))
        if result.returncode:
            raise ValueError(f'{repo.relative_to(root)}: {result.stderr}')
        print(f'{repo.relative_to(root)}: applied {patch.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true',
                        help='Validate applicability without modifying dependencies')
    args = parser.parse_args()
    legacy = Path(__file__).resolve().parent
    try:
        apply_patches(legacy.parent, legacy / 'dependency_patches.json', args.check)
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
