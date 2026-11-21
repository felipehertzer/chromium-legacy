#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Exercise the actual clipboard implementation on an isolated pasteboard."""
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

    def command(target):
        raw = subprocess.check_output([ninja, '-C', str(build), '-t',
                                       'commands', '-s', target], text=True).strip()
        if '\n' in raw:
            raise ValueError('Expected a direct command')
        return shlex.split(raw)

    targets = ['obj/ui/base/clipboard/clipboard/clipboard_util_mac.o',
               'obj/ui/base/clipboard/clipboard_types/clipboard_format_type_mac.o']
    templates = [command(target) for target in targets]
    link_template = command('base_probe')
    link_env = os.environ.copy()
    while '=' in link_template[0] and not link_template[0].startswith('-'):
        key, value = link_template.pop(0).split('=', 1)
        link_env[key] = value
    response = next(arg for arg in link_template if arg.startswith('@'))
    # base_probe must have been linked with `ninja -d keeprsp` first.
    response_args = shlex.split((build / response[1:]).read_text())
    response_args.remove('obj/legacy/base_probe/base_probe.o')
    with tempfile.TemporaryDirectory(prefix='chromium-legacy-clipboard-') as folder:
        temporary = Path(folder)
        for forced in (False, True):
            objects = []
            define = ('-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1' if forced else
                      '-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS')
            for index, template in enumerate(templates + [templates[0]]):
                cmd = list(template)
                obj = temporary / f'part-{index}.o'
                cmd[cmd.index('-o') + 1] = str(obj)
                cmd[cmd.index('-MF') + 1] = str(obj) + '.d'
                if index == 2:
                    cmd[cmd.index('-c') + 1] = str(root / 'legacy/tests/clipboard_probe.mm')
                subprocess.run(cmd + [define], cwd=build, check=True)
                objects.append(str(obj))
            extra = [
                'obj/ui/base/clipboard/clipboard_types/clipboard_constants_mac.o',
                'obj/ui/base/clipboard/url_file_parser/url_file_parser.o',
                'obj/ui/base/clipboard/libui_base_file_info.a',
                'obj/ui/base/libui_base_features.a',
                'obj/url/liburl.a',
                'obj/third_party/icu/libicuuc.a',
            ]
            rsp = temporary / 'probe.rsp'
            rsp.write_text(shlex.join(objects + extra + response_args + [
                '-framework', 'AppKit', '-framework', 'CoreServices',
                '-weak_framework', 'UniformTypeIdentifiers', '-lobjc']))
            binary = temporary / 'probe'
            cmd = list(link_template)
            cmd[cmd.index(response)] = '@' + str(rsp)
            cmd[cmd.index('-o') + 1] = str(binary)
            subprocess.run(cmd, cwd=build, env=link_env, check=True)
            subprocess.run([str(binary)], check=True)
            if args.output:
                destination = Path(str(args.output) + ('.fallback' if forced else ''))
                shutil.copy2(binary, destination)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
