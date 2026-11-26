#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Check real SharedImage IPC serialization and malformed-target rejection.

Requires the normal Intel chrome and base_probe builds with retained response
files. Uses only the production Mojo/core/format objects. No browser or GPU
context is created and no user files are read.
"""

from pathlib import Path
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, default=root / 'out/Lion')
parser.add_argument(
    '--output',
    type=Path,
    required=True,
    help='New directory for the signed probe and report',
)
args = parser.parse_args()
build = args.build_dir.resolve()
stage = args.output.resolve()
stage.mkdir(exist_ok=False)
ninja = shutil.which('ninja')
if not ninja:
    raise ValueError('ninja is required')


def command(target):
    return shlex.split(
        subprocess.check_output(
            [ninja, '-C', str(build), '-t', 'commands', '-s', target], text=True
        ).strip()
    )


cmd = command(
    'obj/gpu/ipc/common/interfaces_cpp_sources/shared_image_capabilities_mojom_traits.o'
)
assert (
    '--target=x86_64-apple-macos' in cmd and '-mmacos-version-min=10.7' in cmd
)
for flag, value in [
    ('-c', str(root / 'legacy/tests/shared_image_caps_probe.cc')),
    ('-o', str(stage / 'probe.o')),
    ('-MF', str(stage / 'probe.d')),
]:
    cmd[cmd.index(flag) + 1] = value
subprocess.run(cmd, cwd=build, check=True)
rsp = shlex.split((build / 'base_probe.rsp').read_text())
assert rsp[0] == 'obj/legacy/base_probe/base_probe.o'
rsp[0] = str(stage / 'probe.o')
framework = shlex.split(
    (
        build
        / 'obj/chrome/chrome_framework_shared_library/Chromium Framework.rsp'
    ).read_text()
)
for arg in framework:
    keep_archive = arg.endswith('.a') and (
        arg.startswith('obj/mojo/')
        and '/rust/' not in arg
        and 'blink' not in arg
        and 'wtf' not in arg
        or 'ipcz' in arg
        or 'libviz_shared_image_format.a' in arg
    )
    keep_object = (
        arg.endswith('.o')
        and 'blink' not in arg
        and (
            arg.startswith('obj/mojo/core/')
            or 'ipcz' in arg
            or 'shared_image_capabilities' in arg
            or 'shared_image_format' in arg
        )
    )
    if (keep_archive or keep_object) and arg not in rsp:
        rsp.append(arg)
(stage / 'probe.rsp').write_text(shlex.join(rsp))
cmd = command('base_probe')
cmd = [
    ('@' + str(stage / 'probe.rsp'))
    if a.startswith('@') and a.endswith('base_probe.rsp')
    else a
    for a in cmd
]
cmd[cmd.index('-o') + 1] = str(stage / 'probe')
cmd = [
    ('-Wcrl,tocname,' + str(stage / 'probe.TOC'))
    if a.startswith('-Wcrl,tocname,')
    else a
    for a in cmd
]
env = os.environ.copy()
while re.fullmatch('[A-Za-z_][A-Za-z0-9_]*=.*', cmd[0]):
    key, value = cmd.pop(0).split('=', 1)
    env[key] = value
subprocess.run(cmd, cwd=build, env=env, check=True)
subprocess.run(
    [
        'codesign',
        '--force',
        '--sign',
        '-',
        '--digest-algorithm=sha1,sha256',
        '--timestamp=none',
        str(stage / 'probe'),
    ],
    check=True,
    capture_output=True,
)
r = subprocess.run(
    [str(stage / 'probe')], capture_output=True, text=True, timeout=30
)
(stage / 'result.json').write_text(
    json.dumps(
        {'returncode': r.returncode, 'stdout': r.stdout, 'stderr': r.stderr},
        indent=2,
    )
    + '\n'
)
print(r.stdout + r.stderr)
raise SystemExit(r.returncode)
