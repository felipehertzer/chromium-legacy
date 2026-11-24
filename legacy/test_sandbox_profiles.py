#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Compile and apply current sandbox profiles in separate short-lived processes.

OS_VERSION selects policy branches; it does not emulate an older sandbox
compiler or kernel. Run the Intel probe on each real supported system too.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
POLICIES = ROOT / 'sandbox/policy/mac'


def parameters(root, executable, version):
    values = {
        'BROWSER_PID': str(os.getpid()),
        'BUNDLE_ID': 'org.chromium.Chromium',
        'HELPER_BUNDLE_ID': 'org.chromium.Chromium.helper',
        'OS_VERSION': str(version),
        'DISABLE_SANDBOX_DENIAL_LOGGING': 'TRUE',
        'ENABLE_LOGGING': 'FALSE',
        'DISABLE_METAL_SHADER_CACHE': 'FALSE',
        'ALLOW_RENDERER_PIDINFO': 'FALSE',
        'WEBNN_COMPILER_PROCESS': 'FALSE',
        'SYSTEM_PROXY_NETWORK_ACCESS': 'FALSE',
        'ALLOW_NETWORK_SYMLINK_CREATION': 'FALSE',
        'NETWORK_SERVICE_STORAGE_PATHS_COUNT': '1',
        'EXECUTABLE_PATH': str(executable),
        'LOG_FILE_PATH': str(root / 'log'),
    }
    for name in (
        'BUNDLE_PATH',
        'COMPONENT_PATH',
        'USER_HOMEDIR_AS_LITERAL',
        'DARWIN_USER_CACHE_DIR',
        'DARWIN_USER_DIR',
        'DARWIN_USER_TEMP_DIR',
        'USER_DATA_DIR',
        'USER_CACHE_DIR',
        'NETWORK_SERVICE_STORAGE_PATH_0',
        'NETWORK_SERVICE_TEST_CERTS_DIR',
        'SCREEN_AI_COMPONENT_PATH',
        'TRANSLATEKIT_COMPONENT_PATH',
        'SODA_COMPONENT_PATH',
        'SODA_LANGUAGE_PACK_PATH',
    ):
        path = root / name
        path.mkdir(exist_ok=True)
        values[name] = str(path)
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    if platform.system() != 'Darwin':
        parser.error('The real macOS sandbox is required')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--architecture', choices=('x64', 'arm64'))
    parser.add_argument('--os-version', type=int, action='append')
    parser.add_argument(
        '--probe', type=Path, help='Run a prebuilt probe without an SDK'
    )
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if args.build_only and (not args.output or args.probe):
        parser.error('--build-only requires --output and cannot use --probe')
    host_architecture = 'arm64' if platform.machine() == 'arm64' else 'x64'
    architectures = [args.architecture or host_architecture]
    if args.probe:
        args.probe = args.probe.resolve(strict=True)
    host_version_parts = platform.mac_ver()[0].split('.')
    host_version = int(host_version_parts[0]) * 100 + int(host_version_parts[1])
    branch_versions = [
        1007,
        1008,
        1009,
        1010,
        1013,
        1015,
        1300,
        2600,
        2700,
    ]
    versions = args.os_version or [
        v for v in branch_versions if v <= host_version
    ]
    if not args.os_version and host_version not in versions:
        versions.append(host_version)
    sdk = None
    if not args.probe:
        sdk = (
            os.environ.get('SDKROOT')
            or subprocess.check_output(
                ['xcrun', '--show-sdk-path'], text=True
            ).strip()
        )
    compiler = os.environ.get(
        'CC', str(ROOT / 'third_party/llvm-build/Release+Asserts/bin/clang')
    )
    rows = []
    with tempfile.TemporaryDirectory(
        prefix='chromium-legacy-sandbox-'
    ) as temporary:
        directory = Path(temporary).resolve()
        (directory / 'forbidden-read').write_text('private test fixture\n')
        for architecture in architectures:
            executable = args.probe or directory / ('probe-' + architecture)
            if not args.probe:
                target = 'x86_64' if architecture == 'x64' else 'arm64'
                minimum = '10.7' if architecture == 'x64' else '13.0'
                target_arguments = [
                    '--target=' + target + '-apple-macos',
                    '-mmacos-version-min=' + minimum,
                    '-isysroot',
                    sdk,
                ]
                obj = directory / ('probe-' + architecture + '.o')
                command = [
                    compiler,
                    *target_arguments,
                    '-std=c11',
                    '-Wall',
                    '-Wextra',
                    '-Werror',
                    '-Wunguarded-availability',
                    str(ROOT / 'legacy/tests/sandbox_profile_probe.c'),
                    '-c',
                    '-o',
                    str(obj),
                ]
                subprocess.run(command, check=True)
                subprocess.run(
                    [
                        'python3',
                        str(ROOT / 'build/toolchain/apple/linker_driver.py'),
                        '-Wcrl,driver,' + compiler,
                        *target_arguments,
                        '-fuse-ld=lld',
                        '-Wl,-fatal_warnings',
                        str(obj),
                        '-lsandbox',
                        '-o',
                        str(executable),
                    ],
                    cwd=directory,
                    check=True,
                )
            for version in [] if args.build_only else versions:
                values = parameters(directory, executable, version)
                encoded = [item for pair in values.items() for item in pair]
                for policy in sorted(POLICIES.glob('*.sb')):
                    if policy.name == 'common.sb':
                        continue
                    profile = directory / 'policy.sb'
                    profile.write_text(
                        (POLICIES / 'common.sb').read_text()
                        + '\n'
                        + policy.read_text()
                    )
                    result = subprocess.run(
                        [
                            str(executable),
                            str(profile),
                            str(directory),
                            str(executable),
                            *encoded,
                        ],
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    row = {
                        'architecture': architecture,
                        'os_version_parameter': version,
                        'profile': policy.name,
                        'returncode': result.returncode,
                        'stdout': result.stdout.strip(),
                        'stderr': result.stderr.strip(),
                    }
                    rows.append(row)
                    if result.returncode:
                        print(json.dumps(row), flush=True)
            if args.output:
                destination = args.output.with_name(
                    args.output.name + '.' + architecture
                )
                destination.write_bytes(executable.read_bytes())
                destination.chmod(0o755)
    if args.output:
        args.output.write_text(
            json.dumps(
                {
                    'host_macos': platform.mac_ver()[0],
                    'mode': 'build-only'
                    if args.build_only
                    else 'compile-and-enforce',
                    'scope': 'Actual host sandbox compiler/kernel; OS_VERSION only selects profile branches.',
                    'results': rows,
                },
                indent=2,
            )
            + '\n'
        )
    failed = sum(bool(row['returncode']) for row in rows)
    if args.build_only:
        print('Probe built; no policy was executed')
    else:
        print(
            f'{len(rows) - failed}/{len(rows)} policy compilation and enforcement runs passed'
        )
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(main())
