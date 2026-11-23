#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Build the pinned Crubit Rust frontend with the Lion-capable Rust toolchain."""

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def symlink(source, destination):
    if destination.is_symlink() and destination.resolve() == source.resolve():
        return
    if destination.exists() or destination.is_symlink():
        raise ValueError(f'Preserving unexpected existing path: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(
        source.resolve(), target_is_directory=source.is_dir()
    )


def promote_public_dependencies(text, targets):
    """Export only the exact pinned dependencies included by public headers."""
    for target, dependencies in targets.items():
        pattern = r'(source_set\("' + re.escape(target) + r'"\) \{.*?\n\})'
        matches = list(re.finditer(pattern, text, re.DOTALL))
        if len(matches) != 1:
            raise ValueError(f'Expected one C++ support target: {target}')
        match = matches[0]
        block = match.group()
        deps_match = re.search(r'  deps = \[\n(.*?)  \]\n', block, re.DOTALL)
        if not deps_match or '  public_deps = ' in block:
            raise ValueError(f'Unexpected dependency declaration: {target}')
        lines = deps_match[1].splitlines(keepends=True)
        public, private = [], []
        remaining = set(dependencies)
        for line in lines:
            label = line.strip().removesuffix(',').strip('"')
            if label in remaining:
                public.append(line)
                remaining.remove(label)
            else:
                private.append(line)
        if remaining:
            raise ValueError(
                f'Missing pinned dependencies in {target}: {remaining}'
            )
        replacement = '  public_deps = [\n' + ''.join(public) + '  ]\n'
        if private:
            replacement += '  deps = [\n' + ''.join(private) + '  ]\n'
        block = (
            block[: deps_match.start()]
            + replacement
            + block[deps_match.end() :]
        )
        text = text[: match.start()] + block + text[match.end() :]
    return text


def prepare_support_overlay(original, workspace, revision, manifest_path):
    """Keep packaged sources intact, copying timestamps and changing GN only."""
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    if (
        manifest.get('schema_version') != 1
        or manifest.get('revision') != revision
    ):
        raise ValueError(
            'Crubit support metadata must match the pinned frontend'
        )
    original = original.resolve()
    digest = hashlib.sha256(manifest_bytes).hexdigest()
    overlay = workspace / f'crubit-lion-support-{revision[:12]}-{digest[:12]}'
    expected = {}
    for name, config in manifest['files'].items():
        relative = Path(name)
        if (
            relative.is_absolute()
            or '..' in relative.parts
            or relative.name != 'BUILD.gn'
        ):
            raise ValueError(f'Unexpected support build file: {name}')
        source = original / relative
        if hashlib.sha256(source.read_bytes()).hexdigest() != config['sha256']:
            raise ValueError(f'Crubit package changed: {name}')
        expected[relative] = promote_public_dependencies(
            source.read_text(), config['public_dependencies']
        )
    marker_name = '.legacy-support-metadata'
    marker = (
        json.dumps(
            {
                'schema_version': 1,
                'original': str(original),
                'revision': revision,
                'manifest_sha256': digest,
            }
        )
        + '\n'
    )
    if overlay.exists():
        if (
            not (overlay / marker_name).is_file()
            or (overlay / marker_name).read_text() != marker
        ):
            raise ValueError(
                f'Preserving unexpected support overlay: {overlay}'
            )
        for relative, contents in expected.items():
            if (overlay / relative).read_text() != contents:
                raise ValueError(
                    f'Preserving changed support metadata: {relative}'
                )
    else:
        shutil.copytree(original, overlay, symlinks=True)
        for relative, contents in expected.items():
            (overlay / relative).write_text(contents)
        (overlay / marker_name).write_text(marker)
    # No support header, source or Rust file is patched. Preserve their timestamps
    # too, so updating metadata does not invalidate existing C++/Rust objects.
    for source in original.rglob('*'):
        if source.is_file() and source.relative_to(original) not in expected:
            copied = overlay / source.relative_to(original)
            if (
                copied.read_bytes() != source.read_bytes()
                or copied.stat().st_mtime_ns != source.stat().st_mtime_ns
            ):
                raise ValueError(
                    f'Support source differs from package: {source}'
                )
    return overlay


def install_support_link(original, overlay, destination):
    if destination.is_symlink() and destination.resolve() != overlay.resolve():
        previous = destination.resolve()
        owned = previous / '.legacy-support-metadata'
        known_overlay = False
        if owned.is_file() and previous.parent == overlay.parent:
            data = json.loads(owned.read_text())
            known_overlay = data.get('schema_version') == 1 and data.get(
                'original'
            ) == str(original.resolve())
        if previous != original.resolve() and not known_overlay:
            raise ValueError(
                f'Preserving unexpected support link: {destination}'
            )
        destination.unlink()
    symlink(overlay, destination)


def main():
    legacy = Path(__file__).resolve().parent
    root = legacy.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=root.parent)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or args.jobs < 1:
        raise ValueError(
            'Use a modern macOS build host and a positive job count'
        )
    workspace = args.workspace.resolve()
    package = root / 'third_party/rust-toolchain'
    tree = ast.parse((root / 'tools/rust/update_rust.py').read_text())
    revision = next(
        ast.literal_eval(node.value)
        for node in tree.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == 'CRUBIT_REVISION'
            for target in node.targets
        )
    )
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Expected a full pinned Crubit commit')
    source = workspace / 'crubit-lion-source'
    if not source.exists():
        source.mkdir(parents=True)
        run(['git', 'init', str(source)])
        run(
            [
                'git',
                '-C',
                str(source),
                'fetch',
                '--depth',
                '1',
                'https://chromium.googlesource.com/external/github.com/google/crubit',
                revision,
            ]
        )
        run(['git', '-C', str(source), 'checkout', '--detach', revision])
    actual = subprocess.check_output(
        ['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True
    ).strip()
    if actual != revision:
        raise ValueError(f'Crubit must remain at pinned revision {revision}')
    if subprocess.check_output(
        ['git', '-C', str(source), 'status', '--porcelain'], text=True
    ).strip():
        raise ValueError(
            'Preserving local changes in the Crubit source checkout'
        )
    information = subprocess.check_output(
        [str(package / 'bin/rustc'), '-vV'], text=True
    )
    host = next(
        line.removeprefix('host: ')
        for line in information.splitlines()
        if line.startswith('host: ')
    )
    sysroot = workspace / 'rust-lion/build' / host / 'stage1'
    compiler = sysroot / 'bin/rustc'
    private = sysroot / 'lib/rustlib' / host / 'lib'
    if len(list(private.glob('librustc_driver-*.rmeta'))) != 1:
        raise ValueError(
            'Complete the stage2 compiler build to install matching rustc-dev metadata'
        )
    llvm_bin = (
        (sysroot / 'lib/rustlib' / host / 'bin/rust-objcopy').resolve().parent
    )
    llvm_config = llvm_bin / 'llvm-config'
    llvm_lib = subprocess.check_output(
        [str(llvm_config), '--libdir'], text=True
    ).strip()
    build = workspace / 'crubit-lion-build'
    binary = build / 'release/cc_bindings_from_rs'
    if not args.verify_only:
        environment = os.environ.copy()
        environment.update(
            {
                'CARGO_HOME': str(workspace / 'crubit-lion-cargo'),
                'RUSTC': str(compiler),
                'RUSTC_WRAPPER': str(legacy / 'rust_snapshot_wrapper.py'),
                'CHROMIUM_LEGACY_RUST_SOURCE': str(workspace / 'rust-lion'),
                'CHROMIUM_LEGACY_RUST_REVISION': json.loads(
                    (legacy / 'rust_compiler_patches.json').read_text()
                )['patches'][0]['revision'],
                'RUSTC_BOOTSTRAP': '1',
                'MACOSX_DEPLOYMENT_TARGET': '13.0',
                'RUSTFLAGS': (
                    '-Zosx-rpath-install-name '
                    f'-Lnative={llvm_lib} '
                    f'-Clink-arg=-Wl,-rpath,{private} '
                    f'-Clink-arg=-Wl,-rpath,{sysroot / "lib"}'
                ),
            }
        )

        snapshot = (
            environment['CHROMIUM_LEGACY_RUST_REVISION']
            + '\n'
            + (legacy / 'rust_snapshot_wrapper.py').read_text()
        )
        stamp = build / '.legacy-snapshot-probe'
        if not stamp.exists() or stamp.read_text() != snapshot:
            if build.exists():
                # Cargo does not fingerprint RUSTC_WRAPPER for build scripts.
                # Invalidate only the cached version probe in our own output.
                run(
                    [
                        str(package / 'bin/cargo'),
                        'clean',
                        '--release',
                        '-p',
                        'rustversion',
                        '--manifest-path',
                        str(source / 'Cargo.toml'),
                        '--target-dir',
                        str(build),
                    ],
                    cwd=source,
                    env=environment,
                )
            build.mkdir(parents=True, exist_ok=True)
            stamp.write_text(snapshot)
        run(
            [
                str(package / 'bin/cargo'),
                'build',
                '--release',
                '--locked',
                '--manifest-path',
                str(source / 'Cargo.toml'),
                '--target-dir',
                str(build),
                '-p',
                'cc_bindings_from_rs',
                '--bin',
                'cc_bindings_from_rs',
                '--jobs',
                str(args.jobs),
            ],
            cwd=source,
            env=environment,
        )
    run([str(binary), '--help'], stdout=subprocess.DEVNULL)
    # Only the Rust frontend embeds rustc and needs rebuilding. Keep the
    # packaged tools/sources intact and correct public GN dependencies in an
    # owned metadata overlay for the exact pinned support package.
    output = workspace / 'crubit-lion-toolchain'
    symlink(binary, output / 'bin/cc_bindings_from_rs')
    symlink(
        package / 'bin/rs_bindings_from_cc', output / 'bin/rs_bindings_from_cc'
    )
    original_support = package / 'lib/third_party/crubit'
    support = prepare_support_overlay(
        original_support,
        workspace,
        revision,
        legacy / 'crubit_support_public_deps.json',
    )
    install_support_link(
        original_support, support, output / 'lib/third_party/crubit'
    )
    metadata = workspace / 'crubit-lion.gni'
    metadata_text = f'rust_crubit_root = {json.dumps(str(output))}\n'
    if not metadata.exists() or metadata.read_text() != metadata_text:
        metadata.write_text(metadata_text)
    print(f'Crubit frontend built from {revision}; GN arguments: {metadata}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
