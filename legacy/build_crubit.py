#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Build the pinned Crubit Rust frontend with the Lion-capable Rust toolchain."""
import argparse
import ast
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
    destination.symlink_to(source.resolve(), target_is_directory=source.is_dir())


def main():
    legacy = Path(__file__).resolve().parent
    root = legacy.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=root.parent)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or args.jobs < 1:
        raise ValueError('Use a modern macOS build host and a positive job count')
    workspace = args.workspace.resolve()
    package = root / 'third_party/rust-toolchain'
    tree = ast.parse((root / 'tools/rust/update_rust.py').read_text())
    revision = next(ast.literal_eval(node.value) for node in tree.body
                    if isinstance(node, ast.Assign) and
                    any(isinstance(target, ast.Name) and target.id == 'CRUBIT_REVISION'
                        for target in node.targets))
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Expected a full pinned Crubit commit')
    source = workspace / 'crubit-lion-source'
    if not source.exists():
        source.mkdir(parents=True)
        run(['git', 'init', str(source)])
        run(['git', '-C', str(source), 'fetch', '--depth', '1',
             'https://chromium.googlesource.com/external/github.com/google/crubit', revision])
        run(['git', '-C', str(source), 'checkout', '--detach', revision])
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != revision:
        raise ValueError(f'Crubit must remain at pinned revision {revision}')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip():
        raise ValueError('Preserving local changes in the Crubit source checkout')
    information = subprocess.check_output([str(package / 'bin/rustc'), '-vV'], text=True)
    host = next(line.removeprefix('host: ') for line in information.splitlines()
                if line.startswith('host: '))
    sysroot = workspace / 'rust-lion/build' / host / 'stage1'
    compiler = sysroot / 'bin/rustc'
    private = sysroot / 'lib/rustlib' / host / 'lib'
    if len(list(private.glob('librustc_driver-*.rmeta'))) != 1:
        raise ValueError('Complete the stage2 compiler build to install matching rustc-dev metadata')
    llvm_bin = (sysroot / 'lib/rustlib' / host / 'bin/rust-objcopy').resolve().parent
    llvm_config = llvm_bin / 'llvm-config'
    llvm_lib = subprocess.check_output([str(llvm_config), '--libdir'], text=True).strip()
    build = workspace / 'crubit-lion-build'
    binary = build / 'release/cc_bindings_from_rs'
    if not args.verify_only:
        environment = os.environ.copy()
        environment.update({
            'CARGO_HOME': str(workspace / 'crubit-lion-cargo'),
            'RUSTC': str(compiler),
            'RUSTC_WRAPPER': str(legacy / 'rust_snapshot_wrapper.py'),
            'CHROMIUM_LEGACY_RUST_SOURCE': str(workspace / 'rust-lion'),
            'CHROMIUM_LEGACY_RUST_REVISION': json.loads(
                (legacy / 'rust_compiler_patches.json').read_text())['patches'][0]['revision'],
            'RUSTC_BOOTSTRAP': '1',
            'MACOSX_DEPLOYMENT_TARGET': '13.0',
            'RUSTFLAGS': ('-Zosx-rpath-install-name '
                          f'-Lnative={llvm_lib} '
                          f'-Clink-arg=-Wl,-rpath,{private} '
                          f'-Clink-arg=-Wl,-rpath,{sysroot / "lib"}'),
        })

        snapshot = environment['CHROMIUM_LEGACY_RUST_REVISION'] + '\n' + (
            legacy / 'rust_snapshot_wrapper.py').read_text()
        stamp = build / '.legacy-snapshot-probe'
        if not stamp.exists() or stamp.read_text() != snapshot:
            if build.exists():
                # Cargo does not fingerprint RUSTC_WRAPPER for build scripts.
                # Invalidate only the cached version probe in our own output.
                run([str(package / 'bin/cargo'), 'clean', '--release', '-p', 'rustversion',
                     '--manifest-path', str(source / 'Cargo.toml'), '--target-dir', str(build)],
                    cwd=source, env=environment)
            build.mkdir(parents=True, exist_ok=True)
            stamp.write_text(snapshot)
        run([str(package / 'bin/cargo'), 'build', '--release', '--locked',
             '--manifest-path', str(source / 'Cargo.toml'), '--target-dir', str(build),
             '-p', 'cc_bindings_from_rs', '--bin', 'cc_bindings_from_rs',
             '--jobs', str(args.jobs)], cwd=source, env=environment)
    run([str(binary), '--help'], stdout=subprocess.DEVNULL)
    # Keep the original packaged tools and support sources unchanged. Only the
    # Rust-to-C++ frontend embeds rustc and needs rebuilding for this port.
    output = workspace / 'crubit-lion-toolchain'
    symlink(binary, output / 'bin/cc_bindings_from_rs')
    symlink(package / 'bin/rs_bindings_from_cc', output / 'bin/rs_bindings_from_cc')
    symlink(package / 'lib/third_party/crubit', output / 'lib/third_party/crubit')
    metadata = workspace / 'crubit-lion.gni'
    metadata.write_text(f'rust_crubit_root = {json.dumps(str(output))}\n')
    print(f'Crubit frontend built from {revision}; GN arguments: {metadata}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
