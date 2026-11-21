# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Restore old framework link metadata without modifying the installed SDK.

The modern SDK omits NSObject's pre-10.8 Foundation export and uses the
post-10.9 CoreText install name. Headers and availability annotations remain
those of the selected SDK. Generated stubs stay inside the build directory.
"""
import hashlib
import os
from pathlib import Path
import re
import shlex
import tempfile


def _atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _legacy_stub(name, data):
    text = data.decode('utf-8')
    if (not text.startswith('--- !tapi-tbd\n') or
            len(re.findall(r'^---', text, re.M)) != 1 or
            not re.search(r'^tbd-version:\s+4$', text, re.M) or
            not text.endswith('...\n') or
            not re.search(r'^exports:\s*$', text, re.M)):
        raise ValueError(f'{name}: expected a single TAPI v4 SDK stub')
    if name == 'Foundation':
        # Lion exports both NSObject's class and metaclass from Foundation.
        # A class entry in a TBD represents both symbols. Do not add ivars
        # or claim exports which are absent from the actual old framework.
        text = text[:-4] + ("  - targets: [ x86_64-macos ]\n"
                           "    objc-classes: [ NSObject ]\n...\n")
    elif name == 'CoreText':
        current = '/System/Library/Frameworks/CoreText.framework/Versions/A/CoreText'
        legacy = ('/System/Library/Frameworks/ApplicationServices.framework/'
                  'Versions/A/Frameworks/CoreText.framework/Versions/A/CoreText')
        pattern = r"(?m)^(install-name:\s*)'" + re.escape(current) + r"'$"
        text, count = re.subn(pattern, lambda match: match[1] + "'" + legacy + "'", text)
        if count != 1:
            raise ValueError('CoreText: unexpected SDK install name')
    else:
        raise ValueError(f'Unexpected framework: {name}')
    return text.encode('utf-8')


def _has_coretext(args, seen=None):
    seen = set() if seen is None else seen
    for index, argument in enumerate(args):
        if (argument == '-framework' and index + 1 < len(args) and
                args[index + 1] == 'CoreText'):
            return True
        if argument == '-Wl,-framework,CoreText':
            return True
        if argument.startswith('@'):
            response = Path(argument[1:]).resolve()
            if response in seen or not response.is_file():
                continue
            seen.add(response)
            if _has_coretext(shlex.split(response.read_text(encoding='utf-8-sig')),
                             seen):
                return True
    return False


def add_legacy_sdk_overlay(args, build_dir=None):
    """Prepend a framework overlay only for the explicit Intel Lion target."""
    if '-mmacos-version-min=10.7' not in args:
        return args
    intel = any(arg.startswith(('--target=x86_64-apple-', '-target=x86_64-apple-'))
                for arg in args)
    intel = intel or any(args[i:i + 2] == ['-arch', 'x86_64']
                         for i in range(len(args) - 1))
    if not intel:
        raise ValueError('The Lion SDK overlay requires an x86_64 target')
    try:
        sdk = Path(args[args.index('-isysroot') + 1]).resolve(strict=True)
    except (ValueError, IndexError) as error:
        raise ValueError('The Lion SDK overlay requires an explicit SDK') from error
    frameworks = {}
    for name, version in [('Foundation', 'C'), ('CoreText', 'A')]:
        source = (sdk / 'System/Library/Frameworks' / (name + '.framework') /
                  'Versions' / version / (name + '.tbd'))
        frameworks[name] = _legacy_stub(name, source.read_bytes())
    fingerprint = hashlib.sha256()
    for name, data in sorted(frameworks.items()):
        fingerprint.update(name.encode('ascii'))
        fingerprint.update(data)
    overlay = (Path(build_dir or os.getcwd()) / '.legacy-sdk' /
               fingerprint.hexdigest())
    for name, data in frameworks.items():
        _atomic_write(overlay / (name + '.framework') / (name + '.tbd'), data)
    prefix = ['-F' + str(overlay.resolve())]
    # Umbrella frameworks can otherwise load the system CoreText stub before
    # an explicit -framework CoreText, bypassing our legacy install name.
    if _has_coretext(args):
        prefix += ['-framework', 'CoreText']
    return prefix + args
