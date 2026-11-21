import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'dependency_patches', Path(__file__).parents[1] / 'apply_dependency_patches.py')
PATCHES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCHES)


class DependencyPatchesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'third_party' / 'fixture'
        self.repo.mkdir(parents=True)
        self.legacy = self.root / 'legacy'
        self.legacy.mkdir()
        self.run_git('init', '-q')
        (self.repo / 'source.txt').write_text('old\n')
        self.run_git('add', 'source.txt')
        self.run_git('-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                     'commit', '-qm', 'base')
        revision = self.run_git('rev-parse', 'HEAD').strip()
        (self.repo / 'source.txt').write_text('new\n')
        (self.legacy / 'fix.patch').write_text(self.run_git('diff'))
        self.run_git('checkout', '--', 'source.txt')
        self.manifest = self.legacy / 'manifest.json'
        self.entries = [{'path': 'third_party/fixture', 'revision': revision,
                         'patch': 'fix.patch'}]
        self.save_manifest()

    def run_git(self, *args):
        return subprocess.check_output(
            ['git', '-C', str(self.repo), *args], text=True)

    def save_manifest(self):
        self.manifest.write_text(json.dumps({'schema_version': 1,
                                             'patches': self.entries}))

    def test_check_then_apply_and_repeat_preserves_other_files(self):
        other = self.repo / 'user-work.txt'
        other.write_text('keep me\n')
        PATCHES.apply_patches(self.root, self.manifest, check_only=True)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'old\n')
        PATCHES.apply_patches(self.root, self.manifest)
        PATCHES.apply_patches(self.root, self.manifest)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'new\n')
        self.assertEqual(other.read_text(), 'keep me\n')

    def test_wrong_revision_refuses_to_modify_source(self):
        self.entries[0]['revision'] = '0' * 40
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'expected pinned revision'):
            PATCHES.apply_patches(self.root, self.manifest)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'old\n')

    def test_conflicting_changes_are_preserved(self):
        (self.repo / 'source.txt').write_text('user work\n')
        with self.assertRaisesRegex(ValueError, 'patch does not apply'):
            PATCHES.apply_patches(self.root, self.manifest)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'user work\n')

    def test_preflight_failure_leaves_earlier_patches_unapplied(self):
        self.entries.append({'path': '../outside', 'revision': '0' * 40,
                             'patch': 'fix.patch'})
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'stay inside'):
            PATCHES.apply_patches(self.root, self.manifest)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'old\n')


if __name__ == '__main__':
    unittest.main()
