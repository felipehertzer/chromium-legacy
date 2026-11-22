# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'legacy_sdk', ROOT / 'build/toolchain/apple/legacy_sdk.py')
SDK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDK)


class SDKOverlayTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sdk = self.root / 'sdk'
        self.stubs = {}
        for name, version in [('Foundation', 'C'), ('CoreText', 'A')]:
            path = (self.sdk / 'System/Library/Frameworks' /
                    (name + '.framework') / 'Versions' / version /
                    (name + '.tbd'))
            path.parent.mkdir(parents=True)
            data = ("--- !tapi-tbd\n"
                    "tbd-version: 4\n"
                    "targets: [ x86_64-macos ]\n"
                    f"install-name: '/System/Library/Frameworks/{name}.framework/Versions/{version}/{name}'\n"
                    "exports:\n"
                    "  - targets: [ x86_64-macos ]\n"
                    "    symbols: [ _ExistingExport ]\n...\n").encode()
            path.write_bytes(data)
            self.stubs[name] = (path, data)
        self.args = ['--target=x86_64-apple-macos',
                     '-mmacos-version-min=10.7', '-isysroot', str(self.sdk)]

    def test_restores_metadata_and_preserves_installed_sdk(self):
        arguments = SDK.add_legacy_sdk_overlay(self.args, self.root / 'out')
        overlay = Path(arguments[0][2:])
        foundation = (overlay / 'Foundation.framework/Foundation.tbd').read_text()
        coretext = (overlay / 'CoreText.framework/CoreText.tbd').read_text()
        self.assertIn('objc-classes: [ NSObject ]', foundation)
        self.assertIn('_ExistingExport', foundation)
        self.assertIn('ApplicationServices.framework/Versions/A/Frameworks/CoreText', coretext)
        self.assertEqual(arguments[1:], ['-Wl,-no_implicit_dylibs'] + self.args)
        for path, data in self.stubs.values():
            self.assertEqual(path.read_bytes(), data)
        self.assertEqual(SDK.add_legacy_sdk_overlay(self.args, self.root / 'out'),
                         arguments)

    def test_coretext_precedes_umbrella_frameworks(self):
        args = self.args + ['-framework', 'AppKit', '-framework', 'CoreText']
        result = SDK.add_legacy_sdk_overlay(args, self.root / 'out')
        self.assertEqual(result[1], '-Wl,-no_implicit_dylibs')
        self.assertEqual(result[2:4], ['-framework', 'CoreText'])
        self.assertEqual(result[4:], args)

    def test_foundation_precedes_corefoundation_and_coretext(self):
        args = self.args + ['-framework', 'CoreFoundation',
                            '-framework', 'Foundation', '-framework', 'CoreText']
        result = SDK.add_legacy_sdk_overlay(args, self.root / 'out')
        self.assertEqual(result[2:6], ['-framework', 'Foundation',
                                       '-framework', 'CoreText'])
        self.assertEqual(result[6:], args)

    def test_detects_coretext_in_response_files(self):
        nested = self.root / 'nested.rsp'
        nested.write_text('-framework CoreText')
        response = self.root / 'input.rsp'
        response.write_text('-framework AppKit @' + str(nested))
        args = self.args + ['@' + str(response)]
        result = SDK.add_legacy_sdk_overlay(args, self.root / 'out')
        self.assertEqual(result[1], '-Wl,-no_implicit_dylibs')
        self.assertEqual(result[2:4], ['-framework', 'CoreText'])
        self.assertEqual(nested.read_text(), '-framework CoreText')

    def test_modern_target_uses_sdk_unchanged(self):
        args = ['--target=arm64-apple-macos', '-mmacos-version-min=13.0']
        self.assertIs(SDK.add_legacy_sdk_overlay(args, self.root), args)
        self.assertFalse((self.root / '.legacy-sdk').exists())

    def test_rejects_wrong_architecture(self):
        with self.assertRaisesRegex(ValueError, 'x86_64'):
            SDK.add_legacy_sdk_overlay(['-mmacos-version-min=10.7'], self.root)

    def test_rejects_unexpected_sdk_stub(self):
        for data in [b'not a stub',
                     self.stubs['CoreText'][1].replace(b'tbd-version: 4', b'tbd-version: 5'),
                     self.stubs['CoreText'][1].replace(b'/Versions/A/CoreText', b'/Other/CoreText')]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                SDK._legacy_stub('CoreText', data)

    def test_sdk_changes_select_different_cache(self):
        before = SDK.add_legacy_sdk_overlay(self.args, self.root / 'out')
        path, data = self.stubs['Foundation']
        path.write_bytes(data.replace(b'_ExistingExport', b'_ChangedExport'))
        after = SDK.add_legacy_sdk_overlay(self.args, self.root / 'out')
        self.assertNotEqual(before[0], after[0])


if __name__ == '__main__':
    unittest.main()
