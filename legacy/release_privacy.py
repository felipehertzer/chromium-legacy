#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Publish only selected build facts and reject machine data in release files."""

from collections import Counter
import ctypes
import errno
import json
import mmap
import os
from pathlib import Path
import re
import sys
import struct
import stat

PATTERNS = {
    'local home directory': re.compile(rb'/Users/[^/\x00\s"\x27<>]{1,128}/'),
    'local test directory': re.compile(rb'/(?:private/)?tmp/chromium[^\x00\s"\x27<>]+'),
    'GitHub token': re.compile(rb'(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{25,}'),
    'AWS access key': re.compile(rb'AKIA[0-9A-Z]{16}'),
    'private key material': re.compile(
        rb'-----BEGIN ([A-Z ]*PRIVATE KEY)-----\s+'
        rb'[A-Za-z0-9+/=\r\n]{80,}-----END \1-----'
    ),
}
PRIVATE_NAMES = {
    '.git', '.ssh', '.aws', '.codex', '.env', '.DS_Store',
    'id_rsa', 'id_ecdsa', 'id_ed25519', 'id_dsa',
    'History', 'Cookies', 'Login Data', 'Login Data For Account',
    'Local State', 'Preferences', 'Secure Preferences', 'Web Data',
    'Bookmarks', 'Network Persistent State', 'TransportSecurity',
}
# Finder flags and filesystem compression describe the payload, not its origin.
ALLOWED_XATTRS = {'com.apple.FinderInfo', 'com.apple.decmpfs'}


def public_manifest(manifest, browser_report=None):
    """Keep reproducible public facts; never copy arbitrary diagnostic fields."""
    version = manifest['version']
    source = manifest['source_commit']
    if not re.fullmatch(r'\d+(?:\.\d+){3}', version):
        raise ValueError('Invalid browser version')
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Invalid source revision')
    if manifest['architecture'] != 'x86_64' or manifest['minimum_macos_target'] != '10.7':
        raise ValueError('Expected an Intel/10.7 build')
    binaries = []
    for entry in manifest['binaries']:
        path = Path(entry['path'])
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('Binary names must be relative to the application')
        digest = entry['sha256']
        if not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('Invalid binary hash')
        binaries.append({'path': str(path), 'sha256': digest,
                         'architecture': 'x86_64', 'minimum_macos': '10.7'})
    snapshot = manifest['context_snapshot']
    if not re.fullmatch(r'[0-9a-f]{64}', snapshot['sha256']):
        raise ValueError('Invalid snapshot hash')
    result = {
        'version': version, 'channel': 'Mac Beta', 'source_commit': source,
        'architecture': 'x86_64', 'minimum_macos_target': '10.7',
        'macho_count': len(binaries), 'binaries': binaries,
        'context_snapshot': {'size': int(snapshot['size']), 'sha256': snapshot['sha256']},
        'signing': 'Ad-hoc development SHA1/SHA256 with upstream role entitlements',
        'runtime_validation': {'status': 'not performed by this packaging job'},
    }
    if manifest.get('missing_required') == 0 and manifest.get('incomplete_libraries') == 0:
        result.update(missing_required=0, incomplete_libraries=0)
    if browser_report is not None:
        if browser_report.get('passed') is not True or browser_report['expected_version'] != version:
            raise ValueError('Runtime report does not establish this browser version')
        hashes = {item['path']: item['sha256'] for item in binaries}
        required = {'Contents/MacOS/Chromium',
                    f'Contents/Frameworks/Chromium Framework.framework/Versions/{version}/Chromium Framework'}
        if not required.issubset(browser_report['bundle_sha256']):
            raise ValueError('Runtime report lacks application identity hashes')
        if browser_report.get('host_architecture') != 'x86_64' or browser_report.get('browser_returncode') != 0:
            raise ValueError('Runtime report did not finish normally on Intel')
        for path, digest in browser_report['bundle_sha256'].items():
            if hashes.get(path) != digest:
                raise ValueError('Runtime report was produced by different application bytes')
        checks = browser_report['checks']
        if not checks or not all(item['passed'] is True for item in checks):
            raise ValueError('Runtime report contains failed checks')
        system = browser_report['host_macos']
        if not re.fullmatch(r'\d+(?:\.\d+){1,2}', system):
            raise ValueError('Invalid tested OS version')
        names = Counter(re.sub(r'\s+\d+$', '', item['name']) for item in checks)
        result['runtime_validation'] = {
            'status': 'passed', 'macos': system, 'architecture': 'x86_64',
            'checks_passed': len(checks),
            'checks': [{'name': name, 'passed': True, 'count': count}
                       for name, count in names.items()],
        }
    # Even public-field values must not carry paths or credential-shaped data.
    encoded = json.dumps(result).encode()
    if any(pattern.search(encoded) for pattern in PATTERNS.values()):
        raise ValueError('Private data in selected public metadata')
    return result


def public_readme(manifest):
    return (
        f'Chromium Legacy {manifest["version"]} Beta — experimental Intel build.\n\n'
        'Open the DMG and drag Chromium.app to Applications.\n\n'
        'Minimum compilation target: macOS 10.7. Runtime evidence in '
        'Validation/build-info.json covers only the OS actually tested. '
        'Compilation and an ABI audit do not prove runtime support on every OS.\n\n'
        'Development signed, not Apple notarized. No automatic update channel '
        'or maintained legacy security-release channel is configured.\n'
    )


def file_xattrs(path):
    if hasattr(os, 'listxattr'):
        return os.listxattr(path, follow_symlinks=False)
    if sys.platform != 'darwin':
        return []
    # Python exposes these wrappers on Linux, but not on macOS.
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    listing = library.listxattr
    listing.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    listing.restype = ctypes.c_ssize_t
    encoded = os.fsencode(path)
    for _ in range(3):
        size = listing(encoded, None, 0, 1)  # XATTR_NOFOLLOW
        if size < 0:
            raise OSError(ctypes.get_errno(), 'Cannot inspect release file attributes')
        if size == 0:
            return []
        if size > 1024 * 1024:
            raise ValueError('Unexpected extended-attribute name list size')
        buffer = ctypes.create_string_buffer(size)
        actual = listing(encoded, buffer, size, 1)
        if actual >= 0:
            return [os.fsdecode(name) for name in buffer.raw[:actual].split(b'\0') if name]
        if ctypes.get_errno() != errno.ERANGE:
            raise OSError(ctypes.get_errno(), 'Cannot inspect release file attributes')
    raise ValueError('Extended attributes changed repeatedly during release inspection')


def audit_tree(root, *, allow_local_provenance=False):
    """Return file names and issue categories, never the matched secret values."""
    root = Path(root)
    findings = []
    scanned = 0
    for path in [root, *root.rglob('*')]:
        relative = str(path.relative_to(root))
        issues = []
        if path.name in PRIVATE_NAMES or path.name.endswith(('.keychain', '.keychain-db')):
            issues.append('profile or machine metadata file')
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            issues += [name for name, pattern in PATTERNS.items() if pattern.search(data)]
        elif path.is_file():
            scanned += 1
            if path.stat().st_size:
                with path.open('rb') as source:
                    with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
                        issues += [name for name, pattern in PATTERNS.items() if pattern.search(data)]
        attrs = file_xattrs(path)
        allowed = ALLOWED_XATTRS | ({'com.apple.provenance'} if allow_local_provenance else set())
        if set(attrs) - allowed:
            issues.append('machine-specific extended attributes')
        if issues:
            findings.append({'path': relative, 'issues': sorted(set(issues))})
    return {'passed': not findings, 'scanned_files': scanned, 'findings': findings,
            'scope': 'Selected metadata, profile-file, credential-pattern and build-path checks; not an exhaustive secret detector.'}


def require_public_tree(root, *, allow_local_provenance=False):
    report = audit_tree(root, allow_local_provenance=allow_local_provenance)
    if not report['passed']:
        raise ValueError('Release privacy check failed: ' + json.dumps(report['findings']))
    return report


def verify_hfs_no_xattrs(path):
    """Check the on-disk HFS+ attribute fork, independent of host-added xattrs."""
    headers = []
    with Path(path).open('rb') as source:
        with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
            offset = data.find(b'H+\x00\x04')
            while offset >= 0:
                if offset >= 1024 and offset % 512 == 0 and offset + 512 <= len(data):
                    block_size, total_blocks = struct.unpack_from('>II', data, offset + 40)
                    start = offset - 1024
                    if (512 <= block_size <= 65536 and block_size & (block_size - 1) == 0
                            and total_blocks > 0 and start + block_size * total_blocks <= len(data)):
                        logical_size = struct.unpack_from('>Q', data, offset + 352)[0]
                        blocks = struct.unpack_from('>I', data, offset + 364)[0]
                        if logical_size or blocks:
                            raise ValueError('HFS+ image contains an extended-attribute fork')
                        headers.append(offset)
                offset = data.find(b'H+\x00\x04', offset + 1)
    if not headers:
        raise ValueError('No valid HFS+ volume header found')
    return {'filesystem': 'HFS+', 'volume_headers_checked': len(headers),
            'serialized_extended_attributes': 'absent'}


def clear_image_finder_info(root):
    """Normalize only FinderInfo in our newly mounted writable HFS+ image."""
    root = Path(root).resolve()
    if (sys.platform != 'darwin' or not root.is_mount()
            or not root.parent.name.startswith('chromium-dmg-')):
        raise ValueError('FinderInfo cleanup requires an owned temporary image mount')
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    remove = library.removexattr
    remove.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    remove.restype = ctypes.c_int
    cleared = 0
    for path in [root, *root.rglob('*')]:
        # HFS+ uses FinderInfo to represent symlinks. Do not follow or alter them.
        if path.is_symlink() or 'com.apple.FinderInfo' not in file_xattrs(path):
            continue
        mode = stat.S_IMODE(path.stat().st_mode)
        try:
            if not mode & stat.S_IWUSR:
                os.chmod(path, mode | stat.S_IWUSR)
            result = remove(os.fsencode(path), b'com.apple.FinderInfo', 1)
            if result == 0:
                cleared += 1
            elif ctypes.get_errno() != getattr(errno, 'ENOATTR', 93):
                raise OSError(ctypes.get_errno(), 'Cannot normalize image FinderInfo')
        finally:
            if not mode & stat.S_IWUSR:
                os.chmod(path, mode)
    return cleared
