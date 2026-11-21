from pathlib import Path
import sys
import tempfile
import unittest

LEGACY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LEGACY))
from build_rust_compiler import host_stdlib_libraries


class HostStdlibManifestTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name)
        self.host = 'aarch64-apple-darwin'
        self.sysroot = self.source / 'build' / self.host / 'stage1'
        self.installed = self.sysroot / 'lib/rustlib' / self.host / 'lib'
        self.installed.mkdir(parents=True)
        self.stamp = self.source / 'build' / self.host / 'stage1-std' / self.host / 'dist/.libstd-stamp'
        self.stamp.parent.mkdir(parents=True)
        self.names = ['core', 'alloc', 'std', 'proc_macro', 'test']
        self.entries = []
        for name in self.names:
            artifact = self.installed / f'lib{name}-1234.rlib'
            artifact.touch()
            self.entries.append(b't' + bytes(artifact) + b'\0')
        self.write_stamp()

    def write_stamp(self):
        self.stamp.write_bytes(b''.join(self.entries))

    def test_compiler_development_crates_do_not_become_host_stdlib(self):
        (self.installed / 'librustc_driver-5678.rlib').touch()
        (self.installed / 'libstd-old.rlib').touch()
        self.assertEqual(sorted(self.names), host_stdlib_libraries(self.source, self.sysroot, self.host))

    def test_missing_recorded_artifact_is_rejected(self):
        (self.installed / 'libproc_macro-1234.rlib').unlink()
        with self.assertRaisesRegex(ValueError, 'artifact is missing'):
            host_stdlib_libraries(self.source, self.sysroot, self.host)

    def test_duplicate_stdlib_versions_are_rejected(self):
        other = self.installed / 'libcore-5678.rlib'
        other.touch()
        self.entries.append(b't' + bytes(other) + b'\0')
        self.write_stamp()
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            host_stdlib_libraries(self.source, self.sysroot, self.host)


if __name__ == '__main__':
    unittest.main()
