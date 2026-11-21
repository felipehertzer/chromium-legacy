#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Exercise actual compositor clipping with native and forced legacy paths."""
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
            raise ValueError('Expected one direct command')
        return shlex.split(raw)

    template = command('obj/ui/accelerated_widget_mac/accelerated_widget_mac/'
                       'ca_renderer_layer_tree.o')
    link_template = command('base_probe')
    link_env = os.environ.copy()
    while '=' in link_template[0] and not link_template[0].startswith('-'):
        key, value = link_template.pop(0).split('=', 1)
        link_env[key] = value
    response = next(arg for arg in link_template if arg.startswith('@'))
    # Preserve the response file with `ninja -d keeprsp base_probe` first.
    response_args = shlex.split((build / response[1:]).read_text())
    response_args.remove('obj/legacy/base_probe/base_probe.o')
    # GN's Skia core target is a source_set; libskia.a omits these objects.
    core_objects = []
    for line in (build / 'obj/skia/skia_core_and_effects.ninja').read_text().splitlines():
        if line.startswith('build ') and '.o: cxx ' in line:
            obj = line.split(':', 1)[0][6:]
            if not (build / obj).is_file():
                raise ValueError(f'Build the Skia integration objects first: {obj}')
            core_objects.append(obj)
    if not core_objects:
        raise ValueError('No Skia core integration objects found')
    with tempfile.TemporaryDirectory(prefix='chromium-legacy-core-animation-') as folder:
        temporary = Path(folder)
        for forced in (False, True):
            cmd = list(template)
            obj = temporary / 'probe.o'
            cmd[cmd.index('-o') + 1] = str(obj)
            cmd[cmd.index('-MF') + 1] = str(obj) + '.d'
            cmd[cmd.index('-c') + 1] = os.path.relpath(
                root / 'legacy/tests/core_animation_probe.mm', build)
            define = ('-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1' if forced else
                      '-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS')
            subprocess.run(cmd + [define], cwd=build, check=True)
            rsp = temporary / 'probe.rsp'
            rsp.write_text(shlex.join([str(obj)] + response_args + [
                'obj/ui/gfx/geometry/libgeometry.a',
                'obj/ui/gfx/geometry/libgeometry_skia.a',
                'obj/skia/libskia.a', '-Wl,-dead_strip',
                '-framework', 'AppKit', '-framework', 'QuartzCore',
                '-framework', 'CoreVideo', '-framework', 'CoreMedia',
                '-framework', 'AVFoundation', '-framework', 'IOSurface',
                '-lobjc'] + core_objects))
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
