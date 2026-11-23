#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Run the current FakeKeychainV2 tests with Lion production objects.

Requires base_probe and crubit_probe built with -d keeprsp. The unchanged
upstream test fixtures use a 10.15 test deployment; production Keychain objects
retain the Intel 10.7 build flags. Tests use the in-memory fake and temporary,
nonpermanent software keys, not the user's credential store.
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
        prefix='chromium-fake-keychain-test-'
    ) as folder:
        temp = pathlib.Path(folder)
        logs = temp
        output_binary = temp / 'fake-keychain-tests'
        main = temp / 'main.mm'
        main.write_text('''#import <Foundation/Foundation.h>
    #include "base/at_exit.h"
    #include "base/command_line.h"
    #include "testing/gtest/include/gtest/gtest.h"
    int main(int argc, char** argv) {
      base::AtExitManager exit_manager;
      base::CommandLine::Init(argc, argv);
      @autoreleasepool {
        testing::InitGoogleTest(&argc, argv);
        return RUN_ALL_TESTS();
      }
    }
    ''')
        test = command(
            'obj/crypto/crypto_unittests/fake_keychain_v2_unittest.o'
        )
        # Only the existing upstream test fixtures need the newer test deployment.
        # The mock and real Keychain production implementations still compile for 10.7.
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
        for name, target in [
            ('fake', 'obj/crypto/mock_apple_keychain/fake_keychain_v2.o'),
            (
                'scoped',
                'obj/crypto/mock_apple_keychain/scoped_fake_keychain_v2.o',
            ),
            ('real', 'obj/crypto/crypto/keychain_v2.o'),
        ]:
            production = command(target)
            if (
                '--target=x86_64-apple-macos' not in production
                or '-mmacos-version-min=10.7' not in production
            ):
                raise ValueError('Use the Intel Lion integration build')
            tasks.append((name, production))

        def compile(task):
            name, cmd = task
            cmd[cmd.index('-o') + 1] = str(temp / (name + '.o'))
            cmd[cmd.index('-MF') + 1] = str(temp / (name + '.d'))
            with (logs / ('fake-keychain-' + name + '-compile.log')).open(
                'w'
            ) as f:
                rc = subprocess.run(
                    cmd, cwd=build, stdout=f, stderr=subprocess.STDOUT
                ).returncode
            if rc:
                print(
                    (
                        logs / ('fake-keychain-' + name + '-compile.log')
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
        snapshot = temp / 'inputs'
        snapshot.mkdir()
        for i, a in enumerate(rsp):
            if a.endswith(('.a', '.o')):
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
        with (logs / 'fake-keychain-link.log').open('w') as f:
            rc = subprocess.run(
                link,
                cwd=build,
                env=link_env,
                stdout=f,
                stderr=subprocess.STDOUT,
            ).returncode
        if rc:
            print((logs / 'fake-keychain-link.log').read_text(), flush=True)
        if rc:
            raise SystemExit(rc)
        with (logs / 'host-fake-keychain-tests.log').open('w') as f:
            rc = subprocess.run(
                [str(output_binary), '--gtest_color=no'],
                stdout=f,
                stderr=subprocess.STDOUT,
                timeout=60,
            ).returncode
        print((logs / 'host-fake-keychain-tests.log').read_text(), end='')
        if rc == 0 and args.output:
            shutil.copy2(output_binary, args.output)
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
