#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Stage, development-sign and audit a normal Intel/10.7 Chromium build."""

import argparse
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
from types import SimpleNamespace

import audit_macho
from package_dmg import sha256


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--system-root', type=Path, required=True)
    parser.add_argument('--supplemental-root', type=Path, action='append', default=[])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip():
        raise ValueError('Commit or preserve source edits before release packaging')
    stage = args.output.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    app = stage / 'Chromium.app'
    run(['/usr/bin/ditto', str(args.app.resolve(strict=True)), str(app)])
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['LSMinimumSystemVersion'] != '10.7':
        raise ValueError('Unexpected minimum OS version')
    for path in app.rglob('*'):
        if path.is_symlink():
            path.resolve(strict=True).relative_to(app)
    sys.path.insert(0, str(root / 'chrome/installer/mac'))
    from signing import parts
    config = SimpleNamespace(
        app_product='Chromium', product='Chromium',
        framework_dir='Chromium.app/Contents/Frameworks/Chromium Framework.framework',
        base_bundle_id='org.chromium.Chromium', codesign_requirements_outer_app='',
        enable_updater=False, use_static_angle=True, is_chrome_branded=lambda: False,
    )
    products = parts.get_parts(config)
    signatures = []
    for key in [k for k in products if k not in ('app', 'framework')] + ['framework', 'app']:
        product = products[key]
        target = stage / product.path
        command = ['/usr/bin/codesign', '--force', '--sign', '-',
                   '--digest-algorithm=sha1,sha256', '--timestamp=none']
        if product.sign_with_identifier:
            command += ['--identifier', product.identifier]
        expected = {}
        if product.entitlements:
            template = root / 'chrome/app' / product.entitlements
            expected = plistlib.loads(template.read_bytes())
            command += ['--entitlements', str(template)]
        run(command + [str(target)], capture_output=True)
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(target)])
        details = run(['/usr/bin/codesign', '--display', '--verbose=4', str(target)],
                      capture_output=True, text=True).stderr
        if 'Hash choices=sha1,sha256' not in details:
            raise ValueError(f'Missing Lion-compatible signature: {key}')
        result = run(['/usr/bin/codesign', '--display', '--entitlements', '-',
                      '--xml', str(target)], capture_output=True)
        actual = plistlib.loads(result.stdout) if result.stdout else {}
        if actual != expected:
            raise ValueError(f'Unexpected entitlements: {key}')
        signatures.append({'part': key, 'target': product.path,
                           'entitlements': actual, 'metadata': details})
    reports, binaries = [], []
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as source:
            header = source.read(32)
        if header[:4] != b'\xcf\xfa\xed\xfe':
            continue
        data = path.read_bytes()
        _, cpu, _, filetype, count, _, _, _ = struct.unpack('<8I', header)
        offset, minimum, commands = 32, None, []
        for _ in range(count):
            command, size = struct.unpack_from('<2I', data, offset)
            commands.append(command)
            if command == 0x24:
                minimum = struct.unpack_from('<I', data, offset + 8)[0]
            offset += size
        if cpu != audit_macho.CPU_X86_64 or minimum != 0xA0700 or 0x80000034 in commands:
            raise ValueError(f'Not an Intel/10.7 loadable Mach-O: {path}')
        executable = path if filetype == 2 else app / 'Contents/MacOS/Chromium'
        report = audit_macho.audit(path, args.system_root.resolve(),
                                   [p.resolve() for p in args.supplemental_root],
                                   application_root=app, executable_path=executable)
        if report['missing_required'] or report['unknown_ordinals'] or report['incomplete_libraries']:
            raise ValueError(f'Lion ABI audit failed: {path}')
        reports.append(report)
        binaries.append({'path': str(path.relative_to(app)), 'sha256': sha256(path),
                         'architecture': 'x86_64', 'minimum_macos': '10.7'})
    if len(binaries) != len(products):
        raise ValueError('Unexpected number of executable bundle parts')
    snapshot = app / 'Contents/Frameworks/Chromium Framework.framework/Resources/v8_context_snapshot.x86_64.bin'
    manifest = {
        'version': info['CFBundleShortVersionString'], 'channel': 'Mac Beta',
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'source_worktree_clean': True, 'architecture': 'x86_64',
        'minimum_macos_target': '10.7', 'macho_count': len(binaries),
        'upstream_target': json.loads((root / 'legacy/revisions.json').read_text())['target'],
        'binaries': binaries, 'missing_required': 0, 'incomplete_libraries': 0,
        'context_snapshot': {'size': snapshot.stat().st_size, 'sha256': sha256(snapshot)},
        'signing': 'Ad-hoc SHA1/SHA256 with unchanged upstream role entitlement templates',
        'runtime_validation': 'Not established by this build job. Run the browser harness on the target OS.',
    }
    for name, value in [('build-info.json', manifest), ('bundle-abi.json', reports),
                        ('signatures.json', signatures)]:
        (stage / name).write_text(json.dumps(value, indent=2) + '\n')
    (stage / 'README.txt').write_text(
        f'Chromium Legacy {manifest["version"]} Beta — experimental Intel/10.7 build.\n\n'
        'Build, Lion ABI audit and development signatures passed. This job does not '
        'establish browser runtime compatibility on Lion or Catalina. Run the target-OS '
        'browser tests before publishing a release. No automatic update channel is configured.\n'
    )
    print(stage, flush=True)


if __name__ == '__main__':
    main()
