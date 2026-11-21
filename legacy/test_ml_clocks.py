#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Test the actual TFLite/XLA clock objects using their configured GN flags."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=root / 'out/Lion')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output_dir = args.build_dir.resolve()
    ninja = shutil.which('ninja')
    if not ninja:
        raise ValueError('ninja must be available on PATH')
    targets = ['obj/third_party/tflite/tflite_framework_core/time.o',
               'obj/third_party/tflite/tflite_op_shim/env_time.o']
    commands = []
    for target in targets:
        raw = subprocess.check_output([ninja, '-C', str(output_dir), '-t',
                                       'commands', '-s', target], text=True).strip()
        if '\n' in raw:
            raise ValueError('Expected one direct compiler invocation')
        command = shlex.split(raw)
        if not command[0].endswith('clang++'):
            raise ValueError('Expected the configured Clang C++ compiler')
        commands.append(command)
    compiler = (output_dir / commands[0][0]).resolve()
    sdk = (output_dir / commands[0][commands[0].index('-isysroot') + 1]).resolve()
    with tempfile.TemporaryDirectory(prefix='chromium-legacy-ml-clock-') as folder:
        temporary = Path(folder)
        for forced in (False, True):
            define = ('-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1' if forced else
                      '-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS')
            objects = []
            for index, template in enumerate(commands + [commands[-1]]):
                command = list(template)
                obj = temporary / f'part-{index}.o'
                command[command.index('-o') + 1] = str(obj)
                command[command.index('-MF') + 1] = str(obj) + '.d'
                if index == 2:
                    command[command.index('-c') + 1] = str(root / 'legacy/tests/ml_clock_probe.cc')
                subprocess.run(command + [define], cwd=output_dir, check=True)
                objects.append(str(obj))
            binary = temporary / 'probe'
            subprocess.run([sys.executable, str(root / 'build/toolchain/apple/linker_driver.py'),
                            '-Wcrl,driver,' + str(compiler), '--target=x86_64-apple-macos',
                            '-isysroot', str(sdk), '-mmacos-version-min=10.7',
                            '-fuse-ld=lld', '-Wl,-fatal_warnings', '-nostdlib++',
                            *objects, '-o', str(binary)], cwd=output_dir, check=True)
            subprocess.run([str(binary)], check=True)
            if args.output:
                destination = Path(str(args.output) + ('.fallback' if forced else ''))
                shutil.copy2(binary, destination)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
