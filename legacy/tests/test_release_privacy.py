# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import copy
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import struct
from unittest import mock
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_privacy import audit_tree, public_manifest, verify_hfs_no_xattrs


class ReleasePrivacyTests(unittest.TestCase):
    def setUp(self):
        self.version = '159.0.8154.13'
        self.framework = f'Contents/Frameworks/Chromium Framework.framework/Versions/{self.version}/Chromium Framework'
        self.manifest = {
            'version': self.version, 'source_commit': 'a' * 40,
            'architecture': 'x86_64', 'minimum_macos_target': '10.7',
            'binaries': [
                {'path': 'Contents/MacOS/Chromium', 'sha256': 'b' * 64},
                {'path': self.framework, 'sha256': 'c' * 64},
            ],
            'context_snapshot': {'size': 1, 'sha256': 'd' * 64},
            'missing_required': 0, 'incomplete_libraries': 0,
            'diagnostics': '/Users/build-person/private-work/signing.log',
        }
        self.report = {
            'passed': True, 'expected_version': self.version,
            'host_macos': '10.15.7', 'host_architecture': 'x86_64',
            'browser_returncode': 0,
            'bundle_sha256': {x['path']: x['sha256'] for x in self.manifest['binaries']},
            'checks': [{'name': 'renderer sandbox 12345', 'passed': True},
                       {'name': 'renderer sandbox 23456', 'passed': True}],
            'command': ['/Users/build-person/private-app', '--user-data-dir=/Users/build-person/PrivateProfile'],
        }

    def test_metadata_discards_local_diagnostics_and_process_ids(self):
        result = public_manifest(self.manifest, self.report)
        encoded = json.dumps(result)
        self.assertNotIn('build-person', encoded)
        self.assertNotIn('PrivateProfile', encoded)
        self.assertNotIn('12345', encoded)
        self.assertEqual(result['binaries'], [dict(x, architecture='x86_64', minimum_macos='10.7') for x in self.manifest['binaries']])
        self.assertEqual(result['runtime_validation']['checks'],
                         [{'name': 'renderer sandbox', 'passed': True, 'count': 2}])

    def test_build_without_runtime_evidence_does_not_claim_a_test_pass(self):
        result = public_manifest(self.manifest)
        self.assertEqual(result['runtime_validation']['status'], 'not performed by this packaging job')

    def test_changed_or_missing_runtime_identity_is_rejected(self):
        for hashes in [{}, {'Contents/MacOS/Chromium': 'e' * 64, self.framework: 'c' * 64}]:
            report = copy.deepcopy(self.report)
            report['bundle_sha256'] = hashes
            with self.assertRaises(ValueError):
                public_manifest(self.manifest, report)

    def test_failed_runtime_check_cannot_be_published_as_passed(self):
        report = copy.deepcopy(self.report)
        report['checks'][0]['passed'] = False
        with self.assertRaises(ValueError):
            public_manifest(self.manifest, report)

    def test_archive_scan_blocks_machine_data_without_echoing_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            secret = 'ghp_' + 'A' * 36
            (root / 'blob').write_text('/Users/private-person/projects/source.h\n' + secret)
            report = audit_tree(root, allow_local_provenance=True)
            self.assertFalse(report['passed'])
            issues = report['findings'][0]['issues']
            self.assertIn('local home directory', issues)
            self.assertIn('GitHub token', issues)
            self.assertNotIn(secret, json.dumps(report))
            self.assertNotIn('private-person', json.dumps(report))

    def test_profile_files_are_rejected_and_external_directories_not_followed(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            root = parent / 'image'
            root.mkdir()
            outside = parent / 'outside'
            outside.mkdir()
            (outside / 'History').write_text('private test data')
            (root / 'Applications').symlink_to(outside, target_is_directory=True)
            self.assertTrue(audit_tree(root, allow_local_provenance=True)['passed'])
            (root / 'History').write_text('private test data')
            self.assertFalse(audit_tree(root, allow_local_provenance=True)['passed'])

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS extended attributes')
    def test_download_origin_extended_attribute_is_not_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            file = root / 'file'
            file.write_text('ordinary content')
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.metadata:kMDItemWhereFroms',
                            'private origin', str(file)], check=True)
            report = audit_tree(root, allow_local_provenance=True)
            self.assertFalse(report['passed'])
            self.assertIn('machine-specific extended attributes', report['findings'][0]['issues'])


    def test_provenance_is_allowed_only_for_a_working_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch('release_privacy.file_xattrs', return_value=['com.apple.provenance']):
                self.assertFalse(audit_tree(root)['passed'])
                self.assertTrue(audit_tree(root, allow_local_provenance=True)['passed'])

    def test_serialized_hfs_attributes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'filesystem'
            data = bytearray(8192)
            data[1024:1028] = b'H+\x00\x04'
            struct.pack_into('>II', data, 1024 + 40, 512, 16)
            struct.pack_into('>Q', data, 1024 + 352, 512)
            struct.pack_into('>I', data, 1024 + 364, 1)
            path.write_bytes(data)
            with self.assertRaises(ValueError):
                verify_hfs_no_xattrs(path)

    def test_empty_hfs_attribute_fork_is_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'filesystem'
            data = bytearray(8192)
            data[1024:1028] = b'H+\x00\x04'
            struct.pack_into('>II', data, 1024 + 40, 512, 16)
            path.write_bytes(data)
            self.assertEqual(verify_hfs_no_xattrs(path)['serialized_extended_attributes'], 'absent')


if __name__ == '__main__':
    unittest.main()
