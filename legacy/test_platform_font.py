#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Run the original PlatformFontMac tests with Intel/10.7 production code.

Requires base_probe, crubit_probe and the graphics libraries from the integration
build. Existing upstream fixtures and the test runner target Catalina/10.15;
the production font object keeps its Intel/10.7 compiler flags. All outputs are
private temporary files. --force-legacy exercises family-based font derivation
without the newer private system-font classifier. The exported test executable
needs the build's icudtl.dat in its working directory.
"""

import argparse
import concurrent.futures
import os
import pathlib
import shlex
import shutil
import subprocess
import tempfile


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--build-dir', type=pathlib.Path, default=root / 'out/Lion'
    )
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--force-legacy', action='store_true')
    args = parser.parse_args()
    build = args.build_dir.resolve()
    for name in ['base_probe.rsp', 'crubit_probe.rsp']:
        if not (build / name).is_file():
            raise ValueError(
                'Build ' + name.removesuffix('.rsp') + ' with -d keeprsp first'
            )
    ninja = shutil.which('ninja')
    if not ninja:
        raise ValueError('ninja must be available on PATH')

    def command(target):
        return shlex.split(
            subprocess.check_output(
                [ninja, '-C', str(build), '-t', 'commands', '-s', target],
                text=True,
            )
        )

    with tempfile.TemporaryDirectory(
        prefix='chromium-platform-font-test-'
    ) as folder:
        temp = pathlib.Path(folder)
        logs = temp
        output_binary = temp / 'platform-font-tests'
        main = temp / 'main.mm'
        main.write_text('''#import <AppKit/AppKit.h>
    #include "base/at_exit.h"
    #include "base/command_line.h"
    #include "base/i18n/icu_util.h"
    #include <fcntl.h>
    #include "testing/gtest/include/gtest/gtest.h"
    int main(int argc, char** argv) {
      base::AtExitManager exit_manager;
      base::CommandLine::Init(argc, argv);
      int icu_data = open("icudtl.dat", O_RDONLY);
      if (icu_data < 0 || !base::i18n::InitializeICUWithFileDescriptor(
          icu_data, base::MemoryMappedFile::Region::kWholeFile)) return 2;
      @autoreleasepool {
        [NSApplication sharedApplication];
        testing::InitGoogleTest(&argc, argv);
        return RUN_ALL_TESTS();
      }
    }
    ''')
        test = command('obj/ui/gfx/gfx_unittests/platform_font_mac_unittest.o')
        # Only the existing upstream test fixtures need the newer test deployment.
        # The production font implementation still compiles for 10.7.
        test = [
            a.replace('-mmacos-version-min=10.7', '-mmacos-version-min=10.15')
            for a in test
        ]
        filtered = []
        i = 0
        while i < len(test):
            a = test[i]
            if a in [
                '-fmodule-file-home-is-cwd',
                '-fmodules-cache-path=/not_exist_dummy_dir',
            ]:
                if filtered and filtered[-1] == '-Xclang':
                    filtered.pop()
                i += 1
                continue
            if a.startswith('-fmodule-file=') or a.startswith(
                '-fmodule-map-file='
            ):
                i += 1
                continue
            filtered.append(a)
            i += 1
        test = filtered
        tasks = [('tests', test), ('main', list(test))]
        tasks[1][1][tasks[1][1].index('-c') + 1] = str(main)
        for name, target in [('font', 'obj/ui/gfx/gfx/platform_font_mac.o')]:
            production = command(target)
            if (
                '--target=x86_64-apple-macos' not in production
                or '-mmacos-version-min=10.7' not in production
            ):
                raise ValueError('Use the Intel Lion integration build')

            if args.force_legacy:
                production.append(
                    '-DCHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS=1'
                )
            tasks.append((name, production))

        def compile(task):
            name, cmd = task
            cmd[cmd.index('-o') + 1] = str(temp / (name + '.o'))
            cmd[cmd.index('-MF') + 1] = str(temp / (name + '.d'))
            with (logs / ('platform-font-' + name + '-compile.log')).open(
                'w'
            ) as f:
                rc = subprocess.run(
                    cmd, cwd=build, stdout=f, stderr=subprocess.STDOUT
                ).returncode
            if rc:
                print(
                    (
                        logs / ('platform-font-' + name + '-compile.log')
                    ).read_text(),
                    flush=True,
                )
            return rc

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(compile, tasks))
        if any(codes):
            raise SystemExit(1)
        rsp = shlex.split((build / 'base_probe.rsp').read_text())
        assert rsp[0] == 'obj/legacy/base_probe/base_probe.o'
        gtest_inputs = [
            a
            for a in shlex.split((build / 'crubit_probe.rsp').read_text())
            if '/googletest/' in a and a.endswith('.o')
        ]
        assert gtest_inputs
        rsp = rsp[1:] + gtest_inputs + ['obj/testing/gtest/libgtest.a']
        # Reuse existing production archives without compiling other UI tests.
        gn = (build / 'obj/ui/gfx/gfx_unittests.ninja').read_text()
        for line in gn.splitlines():
            if line.startswith('build ') and ': link ' in line:
                candidates = (
                    line.split(': link ', 1)[1].split(' |', 1)[0].split()
                )
                skia_objects = [
                    build / a
                    for a in candidates
                    if a.startswith('obj/skia/')
                    and a.endswith('.o')
                    and (build / a).is_file()
                ]
                assert skia_objects
                skia_archive = temp / 'skia-source-sets.a'
                llvm_ar = (
                    root / 'third_party/llvm-build/Release+Asserts/bin/llvm-ar'
                )
                # Archive source-set inputs so the linker loads only needed font
                # and core objects instead of every graphics initializer.
                mri = 'CREATE ' + str(skia_archive) + '\n'
                for obj in skia_objects:
                    stable = temp / ('skia-' + str(len(mri)) + '-' + obj.name)
                    for attempt in range(3):
                        before = obj.stat()
                        shutil.copy2(obj, stable)
                        after = obj.stat()
                        if (
                            before.st_size == after.st_size
                            and before.st_mtime_ns == after.st_mtime_ns
                        ):
                            break
                    else:
                        raise RuntimeError('Changing Skia input ' + str(obj))
                    mri += 'ADDMOD ' + str(stable) + '\n'
                mri += 'SAVE\nEND\n'
                subprocess.run(
                    [str(llvm_ar), '-M'], input=mri, text=True, check=True
                )
                rsp.append(str(skia_archive))
                for arg in candidates:
                    if (
                        arg.endswith(('.a', '.rlib'))
                        and (build / arg).is_file()
                        and arg not in rsp
                    ):
                        rsp.append(arg)
        rsp += ['obj/base/i18n/icubridge/icubridge/default_icu_locale.o']
        rsp += [
            '-framework',
            'Carbon',
            '-Wl,-weak_framework,UniformTypeIdentifiers',
            '-framework',
            'CoreText',
            '-framework',
            'CoreGraphics',
            '-framework',
            'AppKit',
            '-framework',
            'QuartzCore',
            '-framework',
            'IOSurface',
            '-framework',
            'Accelerate',
        ]
        snapshot = temp / 'inputs'
        snapshot.mkdir()
        for i, a in enumerate(rsp):
            if a.endswith(('.a', '.o', '.rlib')):
                p = build / a
                dest = snapshot / (str(i) + '-' + p.name)
                for attempt in range(3):
                    before = p.stat()
                    if (
                        a.endswith('.a')
                        and p.open('rb').read(8) == b'!<thin>\n'
                    ):
                        ar = (
                            root
                            / 'third_party/llvm-build/Release+Asserts/bin/llvm-ar'
                        )
                        subprocess.run(
                            [str(ar), '-M'],
                            input=f'CREATE {dest}\nADDLIB {p}\nSAVE\nEND\n',
                            text=True,
                            check=True,
                        )
                    else:
                        shutil.copy2(p, dest)
                    after = p.stat()
                    if (
                        before.st_mtime_ns == after.st_mtime_ns
                        and before.st_size == after.st_size
                    ):
                        break
                else:
                    raise RuntimeError('Changing input ' + a)
                rsp[i] = str(dest)
        rsp = [str(temp / (name + '.o')) for name, _ in tasks] + rsp
        response = temp / 'test.rsp'
        response.write_text(shlex.join(rsp))
        link = command('base_probe')
        link_env = dict(os.environ)
        if link[0].startswith('TOOL_VERSION='):
            link_env['TOOL_VERSION'] = link.pop(0).split('=', 1)[1]
        link = [
            a.replace('-mmacos-version-min=10.7', '-mmacos-version-min=10.15')
            for a in link
        ]
        link[link.index('-o') + 1] = str(output_binary)
        at = [i for i, a in enumerate(link) if a.startswith('@')]
        assert len(at) == 1
        link[at[0]] = '@' + str(response)
        with (logs / 'platform-font-link.log').open('w') as f:
            rc = subprocess.run(
                link,
                cwd=build,
                env=link_env,
                stdout=f,
                stderr=subprocess.STDOUT,
            ).returncode
        if rc:
            print((logs / 'platform-font-link.log').read_text(), flush=True)
        if rc:
            raise SystemExit(rc)
        with (logs / 'host-platform-font-tests.log').open('w') as f:
            rc = subprocess.run(
                [str(output_binary), '--gtest_color=no'],
                stdout=f,
                stderr=subprocess.STDOUT,
                timeout=60,
                cwd=build,
            ).returncode
        print((logs / 'host-platform-font-tests.log').read_text(), end='')
        if rc == 0 and args.output:
            shutil.copy2(output_binary, args.output)
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
