#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Test the actual native location provider with its existing manager test seam.

No native position request, permission prompt or Wi-Fi query is performed.
Requires the geolocation_probe dependencies and retained archive response file.
"""
import argparse
import json
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
    parser.add_argument('--force-legacy', action='store_true')
    args = parser.parse_args()
    build = args.build_dir.resolve()
    ninja = shutil.which('ninja')
    if not ninja:
        raise ValueError('ninja must be available on PATH')

    def command(target):
        raw = subprocess.check_output(
            [ninja, '-C', str(build), '-t', 'commands', '-s', target], text=True).strip()
        if '\n' in raw:
            raise ValueError('Expected a direct command for ' + target)
        return shlex.split(raw)

    library = 'obj/services/device/public/cpp/geolocation/libgeolocation_service.a'
    archive_response = build / (library + '.rsp')
    if not archive_response.is_file():
        raise ValueError('Build geolocation_probe with ninja -d keeprsp first')
    with tempfile.TemporaryDirectory(prefix='chromium-legacy-geolocation-') as folder:
        temporary = Path(folder)
        replacements = {}
        targets = ['obj/legacy/geolocation_probe/geolocation_probe.o']
        if args.force_legacy:
            targets += ['obj/services/device/public/cpp/geolocation/geolocation/' + name + '.o'
                        for name in ['location_manager_delegate', 'system_geolocation_source_apple']]
        for index, target in enumerate(targets):
            cmd = command(target)
            if '--target=x86_64-apple-macos' not in cmd:
                raise ValueError('Use the Intel Lion integration build')
            obj = temporary / ('probe-' + str(index) + '.o')
            for flag, value in [('-o', str(obj)), ('-MF', str(obj) + '.d')]:
                cmd[cmd.index(flag) + 1] = value
            cmd += ['-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1' if args.force_legacy
                    else '-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS']
            result = subprocess.run(cmd, cwd=build)
            if result.returncode:
                return result.returncode
            replacements[target] = str(obj)
        if args.force_legacy:
            # -ObjC loads all native archive members, so replace the archive
            # rather than linking duplicate implementations beside it.
            members = shlex.split(archive_response.read_text())
            members = [replacements.get(member, member) for member in members]
            archive = temporary / 'geolocation.a'
            subprocess.run([str(root / 'third_party/llvm-build/Release+Asserts/bin/llvm-ar'),
                            'rcs', str(archive), *members], cwd=build, check=True)
            replacements[library] = str(archive)
        cmd = command('geolocation_probe')
        indices = [i for i, arg in enumerate(cmd)
                   if arg.startswith('@') and arg.endswith('geolocation_probe.rsp')]
        if len(indices) != 1:
            raise ValueError('Expected one link response file')
        index = indices[0]
        entries = json.loads(subprocess.check_output(
            [ninja, '-C', str(build), '-t', 'compdb-targets', '-x', 'geolocation_probe'], text=True))
        entries = [entry for entry in entries if Path(entry['output']).name == 'geolocation_probe']
        if len(entries) != 1:
            raise ValueError('Expected exactly one expanded link command')
        expanded = shlex.split(entries[0]['command'])
        suffix = cmd[index + 1:]
        if expanded[:index] != cmd[:index] or (suffix and expanded[-len(suffix):] != suffix):
            raise ValueError('Unexpected expanded response-file boundaries')
        inputs = expanded[index:len(expanded) - len(suffix) if suffix else len(expanded)]
        # Ninja compdb quotes the complete expanded response as one shell
        # argument. Parse that response content with its original boundaries.
        if len(inputs) != 1:
            raise ValueError('Expected one expanded response-file argument')
        inputs = shlex.split(inputs[0])
        response = temporary / 'probe.rsp'
        response.write_text(shlex.join([replacements.get(arg, arg) for arg in inputs]))
        cmd[index] = '@' + str(response)
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
