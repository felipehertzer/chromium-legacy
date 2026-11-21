#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Give rustversion the verified snapshot date of a custom dev compiler."""
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    compiler, *arguments = sys.argv[1:]
    # rustversion explicitly marks this probe for alternate compiler wrappers.
    # It treats an undated `-dev` build as newer than every nightly, which picks
    # incompatible rustc APIs. General version queries and compilations retain
    # the actual compiler version and metadata compatibility checks.
    if os.environ.get('RUSTVERSION') == '1' and arguments == ['--version']:
        version = subprocess.check_output([compiler, '--version'], text=True).strip()
        match = re.fullmatch(r'rustc (\d+\.\d+\.\d+)-dev', version)
        if match:
            source = Path(os.environ['CHROMIUM_LEGACY_RUST_SOURCE'])
            expected = os.environ['CHROMIUM_LEGACY_RUST_REVISION']
            actual, date = subprocess.check_output(
                ['git', '-C', str(source), 'show', '-s', '--format=%H %cs', 'HEAD'],
                text=True).split()
            if actual != expected or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', date):
                raise ValueError('Rust source snapshot does not match the verified compiler build')
            print(f'rustc {match[1]}-nightly ({actual[:9]} {date}) (Chromium Legacy source build)')
        else:
            print(version)
        return 0
    os.execv(compiler, [compiler, *arguments])


if __name__ == '__main__':
    raise SystemExit(main())
