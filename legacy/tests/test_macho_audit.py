# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'macho_audit', Path(__file__).resolve().parents[1] / 'audit_macho.py'
)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


def image(exports=(), imports=(), libraries=(), private_exports=()):
    commands = []
    for library, command in libraries:
        name = library.encode() + b'\0'
        size = (24 + len(name) + 7) & ~7
        commands.append(
            struct.pack('<6I', command, size, 24, 0, 0, 0)
            + name.ljust(size - 24, b'\0')
        )
    strings = bytearray(b'\0')
    symbols = bytearray()
    for name in exports:
        symbols.extend(struct.pack('<IBBHQ', len(strings), 0x0F, 1, 0, 1))
        strings.extend(name.encode() + b'\0')
    for name in private_exports:
        symbols.extend(struct.pack('<IBBHQ', len(strings), 0x1F, 1, 0, 1))
        strings.extend(name.encode() + b'\0')
    for name, ordinal, weak in imports:
        symbols.extend(
            struct.pack(
                '<IBBHQ',
                len(strings),
                1,
                0,
                (ordinal << 8) | (0x40 if weak else 0),
                0,
            )
        )
        strings.extend(name.encode() + b'\0')
    count = len(exports) + len(private_exports) + len(imports)
    command_size = sum(map(len, commands)) + 24
    symbol_offset = 32 + command_size
    commands.append(
        struct.pack(
            '<6I',
            2,
            24,
            symbol_offset,
            count,
            symbol_offset + len(symbols),
            len(strings),
        )
    )
    header = struct.pack(
        '<8I',
        0xFEEDFACF,
        AUDIT.CPU_X86_64,
        3,
        6,
        len(commands),
        command_size,
        0,
        0,
    )
    return header + b''.join(commands) + symbols + strings


class MachOAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binary = self.root / 'probe'

    def library(self, name, content):
        path = self.root / name.lstrip('/')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def test_reexports_satisfy_imports(self):
        self.library('/usr/lib/child.dylib', image(exports=['_available']))
        self.library(
            '/usr/lib/main.dylib',
            image(libraries=[('/usr/lib/child.dylib', AUDIT.REEXPORT)]),
        )
        self.binary.write_bytes(
            image(
                imports=[('_available', 1, False)],
                libraries=[('/usr/lib/main.dylib', AUDIT.LOAD)],
            )
        )
        result = AUDIT.audit(self.binary, self.root)
        self.assertEqual(result['missing_required'], [])
        self.assertEqual(result['incomplete_libraries'], [])

    def test_weak_and_required_symbols_stay_distinct(self):
        self.library('/usr/lib/main.dylib', image(exports=['_other']))
        self.binary.write_bytes(
            image(
                imports=[('_required', 1, False), ('_optional', 1, True)],
                libraries=[('/usr/lib/main.dylib', AUDIT.LOAD)],
            )
        )
        result = AUDIT.audit(self.binary, self.root)
        self.assertEqual(result['missing_required'][0]['symbol'], '_required')
        self.assertEqual(result['missing_weak'][0]['symbol'], '_optional')

    def test_absent_weak_framework_is_optional(self):
        self.binary.write_bytes(
            image(
                imports=[('_optional', 1, True)],
                libraries=[('/absent.framework/absent', AUDIT.WEAK_LOAD)],
            )
        )
        result = AUDIT.audit(self.binary, self.root)
        self.assertEqual(result['missing_required'], [])
        self.assertEqual(result['incomplete_libraries'], [])
        self.assertEqual(len(result['missing_weak']), 1)

    def test_missing_reexport_is_incomplete(self):
        self.library(
            '/usr/lib/main.dylib',
            image(libraries=[('/usr/lib/absent.dylib', AUDIT.REEXPORT)]),
        )
        self.binary.write_bytes(
            image(libraries=[('/usr/lib/main.dylib', AUDIT.LOAD)])
        )
        self.assertEqual(
            len(AUDIT.audit(self.binary, self.root)['incomplete_libraries']), 1
        )

    def test_absolute_symlink_uses_guest_root(self):
        self.library('/usr/lib/actual.dylib', image(exports=['_guest']))
        (self.root / 'usr/lib/link.dylib').symlink_to('/usr/lib/actual.dylib')
        self.binary.write_bytes(
            image(
                imports=[('_guest', 1, False)],
                libraries=[('/usr/lib/link.dylib', AUDIT.LOAD)],
            )
        )
        self.assertEqual(
            AUDIT.audit(self.binary, self.root)['missing_required'], []
        )

    def test_supplemental_installer_library_fills_missing_framework(self):
        supplemental = self.root / 'supplemental'
        path = supplemental / 'usr/lib/extra.dylib'
        path.parent.mkdir(parents=True)
        path.write_bytes(image(exports=['_extra']))
        self.binary.write_bytes(
            image(
                imports=[('_extra', 1, False)],
                libraries=[('/usr/lib/extra.dylib', AUDIT.LOAD)],
            )
        )
        result = AUDIT.audit(self.binary, self.root, [supplemental])
        self.assertEqual(result['missing_required'], [])
        self.assertEqual(result['incomplete_libraries'], [])
        self.assertEqual(result['supplemental_roots'], [str(supplemental)])

    def test_supplemental_root_does_not_replace_primary_exports(self):
        self.library('/usr/lib/extra.dylib', image(exports=['_primary']))
        supplemental = self.root / 'supplemental'
        path = supplemental / 'usr/lib/extra.dylib'
        path.parent.mkdir(parents=True)
        path.write_bytes(image(exports=['_secondary']))
        self.binary.write_bytes(
            image(
                imports=[('_secondary', 1, False)],
                libraries=[('/usr/lib/extra.dylib', AUDIT.LOAD)],
            )
        )
        result = AUDIT.audit(self.binary, self.root, [supplemental])
        self.assertEqual(result['missing_required'][0]['symbol'], '_secondary')

    def test_supplemental_root_cannot_hide_malformed_primary_library(self):
        self.library('/usr/lib/extra.dylib', b'malformed')
        supplemental = self.root / 'supplemental'
        path = supplemental / 'usr/lib/extra.dylib'
        path.parent.mkdir(parents=True)
        path.write_bytes(image(exports=['_secondary']))
        self.binary.write_bytes(
            image(libraries=[('/usr/lib/extra.dylib', AUDIT.LOAD)])
        )
        result = AUDIT.audit(self.binary, self.root, [supplemental])
        self.assertEqual(len(result['incomplete_libraries']), 1)

    def test_universal_slice_and_truncation(self):
        thin = image(exports=['_guest'])
        fat = (
            struct.pack(
                '>7I', 0xCAFEBABE, 1, AUDIT.CPU_X86_64, 3, 4096, len(thin), 12
            ).ljust(4096, b'\0')
            + thin
        )
        self.assertEqual(AUDIT.read_image(fat).exports, {'_guest'})
        for malformed in (fat[:-1], thin[:31], thin[:-1]):
            with self.assertRaises(ValueError):
                AUDIT.read_image(malformed)


class ApplicationAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'Chromium.app'
        self.executable = self.app / 'Contents/MacOS/Chromium'
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(image())
        self.binary = self.executable

    def audit_app(self):
        return AUDIT.audit(
            self.binary,
            self.root,
            application_root=self.app,
            executable_path=self.executable,
        )

    def app_library(self, relative, content):
        path = self.app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_hidden_symbol_cannot_satisfy_a_dylib_import(self):
        self.app_library(
            'Contents/Frameworks/Framework', image(private_exports=['_hidden'])
        )
        self.binary.write_bytes(
            image(
                imports=[('_hidden', 1, False)],
                libraries=[
                    ('@executable_path/../Frameworks/Framework', AUDIT.LOAD)
                ],
            )
        )
        self.assertEqual(
            self.audit_app()['missing_required'][0]['symbol'], '_hidden'
        )

    def test_real_executable_relative_library(self):
        name = '@executable_path/../Frameworks/Framework'
        self.app_library(
            'Contents/Frameworks/Framework', image(exports=['_entry'])
        )
        self.binary.write_bytes(
            image(
                imports=[('_entry', 1, False)], libraries=[(name, AUDIT.LOAD)]
            )
        )
        result = self.audit_app()
        self.assertEqual(result['missing_required'], [])
        self.assertEqual(result['incomplete_libraries'], [])

    def test_reexport_uses_its_own_loader_directory(self):
        name = '@executable_path/../Frameworks/Framework'
        self.app_library(
            'Contents/Frameworks/Framework',
            image(
                libraries=[
                    ('@loader_path/Libraries/child.dylib', AUDIT.REEXPORT)
                ]
            ),
        )
        self.app_library(
            'Contents/Frameworks/Libraries/child.dylib',
            image(exports=['_entry']),
        )
        self.binary.write_bytes(
            image(
                imports=[('_entry', 1, False)], libraries=[(name, AUDIT.LOAD)]
            )
        )
        self.assertEqual(self.audit_app()['missing_required'], [])
        self.assertEqual(self.audit_app()['incomplete_libraries'], [])

    def test_unused_required_local_library_must_exist(self):
        self.binary.write_bytes(
            image(libraries=[('@executable_path/absent.dylib', AUDIT.LOAD)])
        )
        self.assertTrue(self.audit_app()['incomplete_libraries'])

    def test_absent_weak_local_library_stays_optional(self):
        self.binary.write_bytes(
            image(
                imports=[('_optional', 1, True)],
                libraries=[('@executable_path/absent.dylib', AUDIT.WEAK_LOAD)],
            )
        )
        result = self.audit_app()
        self.assertEqual(result['missing_required'], [])
        self.assertEqual(result['incomplete_libraries'], [])
        self.assertEqual(result['missing_weak'][0]['symbol'], '_optional')

    def test_local_symlink_cannot_escape_bundle(self):
        outside = self.root / 'host-library'
        outside.write_bytes(image(exports=['_entry']))
        (self.executable.parent / 'escape.dylib').symlink_to(outside)
        self.binary.write_bytes(
            image(
                imports=[('_entry', 1, False)],
                libraries=[('@executable_path/escape.dylib', AUDIT.LOAD)],
            )
        )
        result = self.audit_app()
        self.assertEqual(result['missing_required'][0]['symbol'], '_entry')
        self.assertTrue(
            any('escapes' in e for e in result['incomplete_libraries'])
        )

    def test_unknown_runpaths_are_not_satisfied_by_matching_basename(self):
        self.app_library(
            'Contents/MacOS/present.dylib', image(exports=['_entry'])
        )
        self.binary.write_bytes(
            image(
                imports=[('_entry', 1, False)],
                libraries=[('@rpath/present.dylib', AUDIT.LOAD)],
            )
        )
        self.assertEqual(
            self.audit_app()['missing_required'][0]['symbol'], '_entry'
        )
        self.assertTrue(self.audit_app()['incomplete_libraries'])

    def test_context_requires_both_paths(self):
        with self.assertRaises(ValueError):
            AUDIT.audit(self.binary, self.root, application_root=self.app)
        with self.assertRaises(ValueError):
            AUDIT.audit(self.binary, self.root, executable_path=self.executable)


if __name__ == '__main__':
    unittest.main()
