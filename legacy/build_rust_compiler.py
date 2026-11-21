#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Build the pinned Lion-capable Rust compiler separately from Chromium's tools."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from apply_dependency_patches import apply_patches


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def host_stdlib_libraries(source, sysroot, host):
    # rustc-dev adds compiler crates to the same directory. Copy only the std
    # artifacts recorded by bootstrap, rather than globbing every installed rlib.
    stamp = source / 'build' / host / 'stage1-std' / host / 'dist/.libstd-stamp'
    libraries = []
    for entry in stamp.read_bytes().split(b'\0'):
        if not entry.startswith(b't') or not entry.endswith(b'.rlib'):
            continue
        name = Path(os.fsdecode(entry[1:])).name
        if not (sysroot / 'lib/rustlib' / host / 'lib' / name).is_file():
            raise ValueError(f'Host standard-library artifact is missing: {name}')
        libraries.append(name[3:].rsplit('-', 1)[0])
    if not {'core', 'alloc', 'std', 'proc_macro', 'test'}.issubset(libraries):
        raise ValueError('Expected a complete host standard-library build')
    if len(libraries) != len(set(libraries)):
        raise ValueError('Host standard-library artifacts are ambiguous')
    return sorted(libraries)


def main():
    legacy = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=legacy.parent.parent)
    parser.add_argument('--llvm-config', type=Path)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--verify-only', action='store_true',
                        help='Validate an existing completed build and emit GN arguments')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or args.jobs < 1:
        raise ValueError('Use a modern macOS build host and a positive job count')
    workspace = args.workspace.resolve()
    source = workspace / 'rust-lion'
    bootstrap = legacy.parent / 'third_party/rust-toolchain'
    manifest = json.loads((legacy / 'rust_compiler_patches.json').read_text())
    revision = manifest['patches'][0]['revision']
    if revision not in (bootstrap / 'VERSION').read_text():
        raise ValueError('Bootstrap compiler must match the pinned Rust revision')
    llvm_config = args.llvm_config
    if llvm_config is None:
        candidates = [shutil.which('llvm-config'),
                      '/opt/homebrew/opt/llvm/bin/llvm-config',
                      '/usr/local/opt/llvm/bin/llvm-config']
        llvm_config = next((Path(p) for p in candidates if p and Path(p).is_file()),
                           None)
    if llvm_config is None:
        raise ValueError('LLVM 23 development files are required; pass --llvm-config')
    llvm_config = llvm_config.resolve()
    llvm_version = subprocess.check_output([str(llvm_config), '--version'],
                                           text=True).strip()
    if not llvm_version.startswith('23.'):
        raise ValueError('This pinned compiler build requires LLVM 23')
    workspace.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        source.mkdir()
        run(['git', 'init', str(source)])
        run(['git', '-C', str(source), 'fetch', '--depth', '1',
             'https://chromium.googlesource.com/external/github.com/rust-lang/rust',
             revision])
        run(['git', '-C', str(source), 'checkout', '--detach', revision])
    # The existing patch tool verifies exact revision, repository boundaries,
    # clean applicability, and already-applied state. Never reset user changes.
    apply_patches(workspace, legacy / 'rust_compiler_patches.json')
    run(['git', '-C', str(source), 'submodule', 'update', '--init', '--depth', '1',
         'library/backtrace'])
    rustc = bootstrap / 'bin/rustc'
    information = subprocess.check_output([str(rustc), '-vV'], text=True)
    host = next(line.removeprefix('host: ') for line in information.splitlines()
                if line.startswith('host: '))
    if host not in ('aarch64-apple-darwin', 'x86_64-apple-darwin'):
        raise ValueError('Expected an Apple host bootstrap compiler')
    llvm_bin = llvm_config.parent
    config = source / 'legacy-bootstrap.toml'
    q = lambda value: json.dumps(str(value))
    config.write_text(f'''profile = "dist"
change-id = "ignore"
[build]
build = {q(host)}
host = [{q(host)}]
target = [{q(host)}]
build-dir = {q(source / 'build')}
jobs = {args.jobs}
docs = false
extended = false
submodules = false
locked-deps = true
rustc = {q(rustc)}
cargo = {q(bootstrap / 'bin/cargo')}
[rust]
download-rustc = false
channel = "dev"
optimize = true
debuginfo-level = 0
debug-assertions = false
lto = "off"
codegen-units = 16
incremental = false
llvm-tools = false
llvm-bitcode-linker = false
[llvm]
download-ci-llvm = false
link-shared = true
[target.{host}]
llvm-config = {q(llvm_config)}
llvm-has-rust-patches = false
cc = "/usr/bin/clang"
cxx = "/usr/bin/clang++"
ar = {q(llvm_bin / 'llvm-ar')}
''')
    environment = os.environ.copy()
    environment['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    environment['CARGO_HOME'] = str(workspace / 'rust-lion-cargo')
    if not args.verify_only:
        # The second compiler build installs matching rustc-dev metadata into
        # stage1, needed to build Crubit with this compiler's internal APIs.
        run([str(source / 'x'), '--config', str(config), 'build', '--stage', '2',
             'compiler/rustc', 'library'], cwd=source, env=environment)
    sysroot = source / 'build' / host / 'stage1'
    compiler = sysroot / 'bin/rustc'
    objcopy = llvm_bin / 'llvm-objcopy'
    if not objcopy.is_file():
        raise ValueError('The matching LLVM objcopy is required for Cargo release builds')
    tool = sysroot / 'lib/rustlib' / host / 'bin/rust-objcopy'
    tool.parent.mkdir(parents=True, exist_ok=True)
    if tool.exists() or tool.is_symlink():
        if tool.resolve() != objcopy.resolve():
            raise ValueError(f'Preserving unexpected objcopy: {tool}')
    else:
        tool.symlink_to(objcopy)
    environment['MACOSX_DEPLOYMENT_TARGET'] = '10.7'
    deployment = subprocess.check_output(
        [str(compiler), '--target', 'x86_64-apple-darwin', '--print',
         'deployment-target'], env=environment, text=True).strip()
    if deployment != 'MACOSX_DEPLOYMENT_TARGET=10.7':
        raise ValueError(f'Compiler still rejects Lion: {deployment}')
    specification = json.loads(subprocess.check_output(
        [str(compiler), '--target', 'x86_64-apple-darwin', '--print',
         'target-spec-json', '-Z', 'unstable-options'], env=environment, text=True))
    if specification['cpu'] != 'core2':
        raise ValueError('Compiler does not target the required Core 2 baseline')
    version = subprocess.check_output([str(compiler), '--version'], text=True).strip()
    host_libraries = host_stdlib_libraries(source, sysroot, host)
    output = workspace / 'rust-lion-compiler.gni'
    output.write_text(f'rust_sysroot_absolute = {q(sysroot)}\n'
                      f'rustc_version = {q(version)}\n'
                      'legacy_build_rust_stdlib = true\n'
                      f'legacy_rust_host_stdlib_libs = {json.dumps(host_libraries)}\n')
    print(f'Lion-capable compiler built; GN arguments: {output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
