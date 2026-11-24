#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Compile and apply current sandbox profiles in separate short-lived processes.

OS_VERSION selects policy branches; it does not emulate an older sandbox
compiler or kernel. Run the Intel probe on each real supported system too.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
POLICIES = ROOT / 'sandbox/policy/mac'

# Test-only masking exercises fallback rules using the current compiler/kernel.
# This is deliberately not part of any production policy or browser parameter.
LION_MISSING_CAPABILITIES = (
    'path',
    'prefix',
    'vnode-type',
    'sysctl-name',
    'sysctl-name-prefix',
    'sysctl-name-regex',
    'ipc-posix-shm-read*',
    'ipc-posix-shm-read-data',
    'ipc-posix-shm-write-data',
    'iokit-registry-entry-class',
    'process-info-pidinfo',
    'process-info-setcontrol',
    'process-info*',
    'iokit-get-properties',
    'nvram*',
    'distributed-notification-post',
    'user-preference-read',
    'xpc-service-name',
    'xpc-service-name-regex',
    'iokit-open-service',
    'iokit-open-user-client',
    'file-issue-extension',
    'file-map-executable',
)


def policy_text(policy, mask_capabilities=False):
    text = (POLICIES / 'common.sb').read_text() + '\n' + policy.read_text()
    if mask_capabilities:
        prelude = (
            '\n(define probe-host-defined? defined?)\n'
            '(define (defined? name)\n'
            "  (and (not (memq name '("
            + ' '.join(LION_MISSING_CAPABILITIES)
            + '))) (probe-host-defined? name)))\n'
        )
        text = text.replace('(version 1)', '(version 1)' + prelude, 1)
    return text


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
        '--compiler-library',
        type=Path,
        help='Compile only with an original Intel macOS libsandbox; never apply its result',
    )
    parser.add_argument(
        '--legacy-capabilities',
        action='store_true',
        help='Mask Lion-missing language hooks in the current compiler (not kernel emulation)',
    )
    parser.add_argument('--denial-logging', action='store_true')
    parser.add_argument('--allow-renderer-pidinfo', action='store_true')
    parser.add_argument(
        '--probe', type=Path, help='Run a prebuilt probe without an SDK'
    )
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if args.build_only and (not args.output or args.probe):
        parser.error('--build-only requires --output and cannot use --probe')
    if args.compiler_library and (args.build_only or args.legacy_capabilities):
        parser.error(
            '--compiler-library cannot use --build-only or --legacy-capabilities'
        )
    if args.compiler_library:
        args.compiler_library = args.compiler_library.resolve(strict=True)
        if args.architecture not in (None, 'x64'):
            parser.error(
                'The original compiler probe requires --architecture x64'
            )
        args.architecture = 'x64'
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
    if args.compiler_library or args.legacy_capabilities:
        versions = args.os_version or [1007, 1008]
    if args.legacy_capabilities and any(
        v not in (1007, 1008) for v in versions
    ):
        parser.error(
            '--legacy-capabilities is limited to the Lion/Mountain Lion branches'
        )
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
                    str(
                        ROOT
                        / 'legacy/tests'
                        / (
                            'sandbox_compiler_probe.c'
                            if args.compiler_library
                            else 'sandbox_profile_probe.c'
                        )
                    ),
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
                        *([] if args.compiler_library else ['-lsandbox']),
                        '-o',
                        str(executable),
                    ],
                    cwd=directory,
                    check=True,
                )
            if args.compiler_library:
                if not args.probe:
                    subprocess.run(
                        [
                            'codesign',
                            '--force',
                            '--sign',
                            '-',
                            '--digest-algorithm=sha1,sha256',
                            '--timestamp=none',
                            str(executable),
                        ],
                        check=True,
                        capture_output=True,
                    )
                subprocess.run(
                    [
                        'codesign',
                        '--verify',
                        '--strict',
                        str(executable),
                    ],
                    check=True,
                    capture_output=True,
                )
            for version in [] if args.build_only else versions:
                values = parameters(directory, executable, version)
                if args.denial_logging:
                    values['DISABLE_SANDBOX_DENIAL_LOGGING'] = 'FALSE'
                if args.allow_renderer_pidinfo:
                    values['ALLOW_RENDERER_PIDINFO'] = 'TRUE'
                encoded = [item for pair in values.items() for item in pair]
                for policy in sorted(POLICIES.glob('*.sb')):
                    if policy.name == 'common.sb':
                        continue
                    profile = directory / 'policy.sb'
                    profile.write_text(
                        policy_text(policy, args.legacy_capabilities)
                    )
                    inputs = (
                        [str(args.compiler_library), str(profile)]
                        if args.compiler_library
                        else [str(profile), str(directory), str(executable)]
                    )
                    result = subprocess.run(
                        [
                            str(executable),
                            *inputs,
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
                    else 'compile-only'
                    if args.compiler_library
                    else 'compile-and-enforce',
                    'scope': (
                        'Original userland compiler on the current host kernel; compile only.'
                        if args.compiler_library
                        else 'Actual host compiler/kernel; masked hooks exercise fallback rules, not an older kernel.'
                        if args.legacy_capabilities
                        else 'Actual host sandbox compiler/kernel; OS_VERSION only selects profile branches.'
                    ),
                    'compiler_library': str(args.compiler_library)
                    if args.compiler_library
                    else None,
                    'compiler_library_sha256': hashlib.sha256(
                        args.compiler_library.read_bytes()
                    ).hexdigest()
                    if args.compiler_library
                    else None,
                    'masked_capabilities': LION_MISSING_CAPABILITIES
                    if args.legacy_capabilities
                    else [],
                    'denial_logging': args.denial_logging,
                    'allow_renderer_pidinfo': args.allow_renderer_pidinfo,
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
        action = (
            'compilation'
            if args.compiler_library
            else 'compilation and enforcement'
        )
        print(f'{len(rows) - failed}/{len(rows)} policy {action} runs passed')
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(main())
