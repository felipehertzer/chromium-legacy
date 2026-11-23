#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Exercise the production attributed-text converters and their borrowed lifetime contract.

Requires the Intel integration objects and a retained accessibility_probe.rsp.
No compiler or linker diagnostics are disabled.
"""
import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=root / 'out/Lion')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    ninja = shutil.which('ninja')
    if not ninja:
        raise ValueError('ninja must be available on PATH')
    response = build / 'accessibility_probe.rsp'
    if not response.is_file():
        raise ValueError('Build accessibility_probe with ninja -d keeprsp first')

    def command(target):
        raw = subprocess.check_output(
            [ninja, '-C', str(build), '-t', 'commands', '-s', target], text=True).strip()
        if '\n' in raw:
            raise ValueError('Expected a direct command for ' + target)
        return shlex.split(raw)

    with tempfile.TemporaryDirectory(prefix='chromium-legacy-attributed-') as folder:
        temporary = Path(folder)
        obj = temporary / 'probe.o'
        cmd = command('obj/content/common/common/attributed_string_type_converters.o')
        if '--target=x86_64-apple-macos' not in cmd:
            raise ValueError('Use the Intel Lion integration build')
        for flag, value in [('-o', str(obj)), ('-MF', str(obj) + '.d'),
                            ('-c', os.path.relpath(root / 'legacy/tests/attributed_string_probe.mm', build))]:
            cmd[cmd.index(flag) + 1] = value
        result = subprocess.run(cmd, cwd=build)
        if result.returncode:
            return result.returncode
        rsp = response.read_text()
        original = 'obj/legacy/accessibility_probe/accessibility_probe.o'
        if original not in rsp:
            raise ValueError('Unexpected base probe response file')
        rsp_path = temporary / 'probe.rsp'
        rsp_path.write_text(rsp.replace(original, shlex.quote(str(obj)), 1))
        cmd = command('accessibility_probe')
        rsp_args = [i for i, arg in enumerate(cmd)
                    if arg.startswith('@') and arg.endswith('accessibility_probe.rsp')]
        if len(rsp_args) != 1:
            raise ValueError('Expected one response file')
        cmd[rsp_args[0]] = '@' + str(rsp_path)
        env = dict(os.environ)
        while re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', cmd[0]):
            key, value = cmd.pop(0).split('=', 1)
            env[key] = value
        binary = temporary / 'probe'
        cmd[cmd.index('-o') + 1] = str(binary)
        result = subprocess.run(cmd, cwd=build, env=env)
        if result.returncode:
            return result.returncode
        result = subprocess.run([str(binary)])
        if result.returncode:
            return result.returncode
        if args.output:
            shutil.copy2(binary, args.output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
