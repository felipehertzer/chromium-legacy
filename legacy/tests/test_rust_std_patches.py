# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import difflib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'rust_std_patches', Path(__file__).resolve().parents[1] /
    'apply_rust_std_patches.py')
PATCHES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCHES)


class RustStdPatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.toolchain = root / 'toolchain'
        self.source = self.toolchain / 'lib/rustlib/src/rust'
        self.source.mkdir(parents=True)
        self.legacy = root / 'legacy'
        self.legacy.mkdir()
        self.manifest_path = self.legacy / 'manifest.json'
        version = ('rustc fixture ' + '1' * 40 + '\n').encode()
        (self.toolchain / 'VERSION').write_bytes(version)
        self.manifest = {'schema_version': 1, 'revision': '1' * 40,
                         'toolchain_version_sha256': PATCHES.digest(version),
                         'patch': 'fix.patch', 'files': []}
        patch = ''
        for name in ('first', 'second'):
            relative = f'library/{name}.rs'
            before, after = f'{name} before\n', f'{name} after\n'
            target = self.source / relative
            target.parent.mkdir(exist_ok=True)
            target.write_text(before)
            patch += ''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile='a/' + relative, tofile='b/' + relative))
            self.manifest['files'].append({
                'path': relative, 'before': PATCHES.digest(before.encode()),
                'after': PATCHES.digest(after.encode())})
        (self.legacy / 'fix.patch').write_text(patch)
        self.save()

    def save(self):
        self.manifest_path.write_text(json.dumps(self.manifest))

    def apply(self, check=False):
        PATCHES.apply_patches(self.toolchain, self.manifest_path, check)

    def test_check_is_read_only(self):
        self.apply(check=True)
        self.assertEqual((self.source / 'library/first.rs').read_text(),
                         'first before\n')

    def test_repeated_application_is_idempotent(self):
        self.apply()
        self.apply()
        self.assertEqual((self.source / 'library/second.rs').read_text(),
                         'second after\n')

    def test_partial_application_recovers(self):
        (self.source / 'library/first.rs').write_text('first after\n')
        self.apply()
        self.assertEqual((self.source / 'library/first.rs').read_text(),
                         'first after\n')
        self.assertEqual((self.source / 'library/second.rs').read_text(),
                         'second after\n')

    def test_conflict_preserves_every_file(self):
        (self.source / 'library/second.rs').write_text('user changes\n')
        with self.assertRaisesRegex(ValueError, 'source differs'):
            self.apply()
        self.assertEqual((self.source / 'library/first.rs').read_text(),
                         'first before\n')
        self.assertEqual((self.source / 'library/second.rs').read_text(),
                         'user changes\n')

    def test_wrong_toolchain_is_rejected(self):
        (self.toolchain / 'VERSION').write_text('different toolchain\n')
        with self.assertRaisesRegex(ValueError, 'exact pinned'):
            self.apply()

    def test_path_escape_is_rejected(self):
        self.manifest['files'][0]['path'] = '../outside'
        self.save()
        with self.assertRaisesRegex(ValueError, 'stay inside'):
            self.apply()

    def test_bad_output_hash_does_not_modify_source(self):
        self.manifest['files'][1]['after'] = '0' * 64
        self.save()
        with self.assertRaisesRegex(ValueError, 'patched hash'):
            self.apply()
        self.assertEqual((self.source / 'library/first.rs').read_text(),
                         'first before\n')


if __name__ == '__main__':
    unittest.main()
