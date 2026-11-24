#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Check real menu callback ownership using Intel/10.7 production code.

Requires the integration objects and a retained base_probe.rsp. Runs only on
AppKit's main thread and never opens a visible menu. Build inputs must remain
unchanged during linking; the script checks their timestamps, including members
of thin archives, to detect concurrent writes.
"""

import argparse
import os
from pathlib import Path
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
    target = 'obj/content/browser/browser/web_menu_runner_mac.o'
    lines = (
        subprocess.check_output(
            [
                ninja,
                '-C',
                str(build),
                '-t',
                'commands',
                '-s',
                target,
                'base_probe',
            ],
            text=True,
        )
        .strip()
        .splitlines()
    )
    if len(lines) != 2:
        raise ValueError('Expected one compiler and one linker command')
    template, link = map(shlex.split, lines)
    if (
        '--target=x86_64-apple-macos' not in template
        or '-mmacos-version-min=10.7' not in template
    ):
        raise ValueError('Use the Intel Lion integration build')
    with tempfile.TemporaryDirectory(
        prefix='chromium-menu-callback-'
    ) as folder:
        temp = Path(folder)

        def run(cmd, name):
            log = temp / (name + '.log')
            with log.open('w') as f:
                result = subprocess.run(
                    cmd,
                    cwd=build,
                    env=environment,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                )
            if result.returncode:
                print(
                    '\n'.join(
                        line[:350]
                        for line in log.read_text().splitlines()[-40:]
                    )
                )
                raise RuntimeError(name + ' failed')

        environment = dict(os.environ)
        for name, source in [
            (
                'production',
                root / 'content/app_shim_remote_cocoa/web_menu_runner_mac.mm',
            ),
            ('probe', root / 'legacy/tests/menu_callback_probe.mm'),
        ]:
            cmd = list(template)
            cmd[cmd.index('-c') + 1] = str(source)
            cmd[cmd.index('-o') + 1] = str(temp / (name + '.o'))
            cmd[cmd.index('-MF') + 1] = str(temp / (name + '.d'))
            run(cmd, name)
        inputs = shlex.split((build / 'base_probe.rsp').read_text())
        if inputs.pop(0) != 'obj/legacy/base_probe/base_probe.o':
            raise ValueError('Unexpected Base probe response file')
        inputs += [
            'obj/third_party/blink/public/mojom/mojom_platform/popup_menu.mojom.o'
        ]
        llvm_ar = root / 'third_party/llvm-build/Release+Asserts/bin/llvm-ar'
        if link[0].startswith('TOOL_VERSION='):
            environment['TOOL_VERSION'] = link.pop(0).split('=', 1)[1]
        paths = set()
        for arg in inputs + link:
            if arg.endswith(('.a', '.o', '.rlib')):
                path = (build / arg).resolve()
                paths.add(path)
                if (
                    path.suffix == '.a'
                    and path.open('rb').read(8) == b'!<thin>\n'
                ):
                    paths.update(
                        Path(member).resolve()
                        for member in subprocess.check_output(
                            [str(llvm_ar), 't', str(path)], text=True
                        ).splitlines()
                    )
        before = {p: (p.stat().st_size, p.stat().st_mtime_ns) for p in paths}
        response = temp / 'inputs.rsp'
        response.write_text(
            shlex.join(
                [
                    str(temp / 'probe.o'),
                    str(temp / 'production.o'),
                    *inputs,
                    '-framework',
                    'AppKit',
                    '-framework',
                    'CoreText',
                    '-framework',
                    'CoreGraphics',
                ]
            )
        )
        binary = temp / 'probe'
        link[link.index('-o') + 1] = str(binary)
        at = [i for i, arg in enumerate(link) if arg.startswith('@')]
        if len(at) != 1:
            raise ValueError('Expected one response file')
        link[at[0]] = '@' + str(response)
        run(link, 'link')
        after = {p: (p.stat().st_size, p.stat().st_mtime_ns) for p in paths}
        if before != after:
            raise RuntimeError(
                'Build inputs changed; rerun after Ninja finishes'
            )
        subprocess.run([str(binary)], check=True, timeout=30)
        if args.output:
            shutil.copy2(binary, args.output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
