#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Exercise original sandbox logging without linking against libbase."""
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
    raw = subprocess.check_output(
        [ninja, '-C', str(build), '-t', 'commands', '-s',
         'obj/sandbox/mac/seatbelt/sandbox_logging.o'], text=True).strip()
    if '\n' in raw:
        raise ValueError('Expected the direct sandbox compiler command')
    template = shlex.split(raw)
    if not template[0].endswith('clang++'):
        raise ValueError('Expected Chromium clang++')
    sdk = template[template.index('-isysroot') + 1]
    aliases = []
    if any(arg.startswith('-fsanitize=') and
           'alloc-token' in arg.split('=', 1)[1].split(',') for arg in template):
        aliases = [
            'obj/build/config/sanitizers/alloc_token_aliases/alloc_token_aliases.o',
            'obj/build/config/sanitizers/alloc_token_aliases_cxx/alloc_token_aliases_cxx.o']
        for obj in aliases:
            if not (build / obj).is_file():
                raise ValueError(f'Build the integration allocator aliases first: {obj}')
    with tempfile.TemporaryDirectory(prefix='chromium-legacy-sandbox-log-') as folder:
        temporary = Path(folder)
        for forced in (False, True):
            objects = []
            define = ('-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1' if forced else
                      '-UCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS')
            for index, source in enumerate((
                    root / 'sandbox/mac/sandbox_logging.cc',
                    root / 'legacy/tests/sandbox_logging_probe.cc')):
                cmd = list(template)
                obj = temporary / f'part-{index}.o'
                cmd[cmd.index('-o') + 1] = str(obj)
                cmd[cmd.index('-MF') + 1] = str(obj) + '.d'
                cmd[cmd.index('-c') + 1] = os.path.relpath(source, build)
                subprocess.run(cmd + [define], cwd=build, check=True)
                objects.append(str(obj))
            binary = temporary / 'probe'
            command = [
                'python3', str(root / 'build/toolchain/apple/linker_driver.py'),
                '-Wcrl,driver,' + template[0], '--target=x86_64-apple-macos',
                '-mmacos-version-min=10.7', '-isysroot', sdk,
                '-fuse-ld=lld', '-Wl,-fatal_warnings', '-Wl,-dead_strip',
                '-nostdlib++', *objects, *aliases,
                'obj/buildtools/third_party/libc++/libc++.a',
                'obj/buildtools/third_party/libc++abi/libc++abi.a',
                '-lobjc', '-o', str(binary)]
            subprocess.run(command, cwd=build, check=True)
            subprocess.run([str(binary)], check=True)
            if args.output:
                destination = Path(str(args.output) + ('.fallback' if forced else ''))
                shutil.copy2(binary, destination)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
