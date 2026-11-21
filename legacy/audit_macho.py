#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Check x86_64 Mach-O imports against an extracted, unmodified macOS root.

This checks linker-level availability, including reexports and weak imports.
It does not prove guarded weak-symbol use, Objective-C selector availability,
sandbox compatibility, or execution on the target OS.
"""
import argparse
from collections import deque
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import struct

CPU_X86_64 = 0x01000007
LOAD = 0xC
WEAK_LOAD = 0x80000018
REEXPORT = 0x8000001F
UPWARD_LOAD = 0x80000023


def unpack(fmt, data, offset):
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > len(data):
        raise ValueError('Truncated Mach-O structure')
    return struct.unpack_from(fmt, data, offset)


def cstring(data, offset, end):
    if not 0 <= offset < end <= len(data):
        raise ValueError('Invalid Mach-O string offset')
    stop = data.find(b'\0', offset, end)
    if stop < 0:
        raise ValueError('Unterminated Mach-O string')
    return data[offset:stop].decode('utf-8')


@dataclass
class Image:
    libraries: list
    exports: set
    imports: list


def read_image(data):
    if data[:4] == b'\xca\xfe\xba\xbe':
        count, = unpack('>I', data, 4)
        for index in range(count):
            cpu, _, offset, size, _ = unpack('>5I', data, 8 + index * 20)
            if cpu == CPU_X86_64:
                if offset + size > len(data):
                    raise ValueError('Truncated universal Mach-O slice')
                return read_image(data[offset:offset + size])
        raise ValueError('Universal Mach-O has no x86_64 slice')
    magic, cpu, _, _, count, command_bytes, _, _ = unpack('<8I', data, 0)
    if magic != 0xFEEDFACF or cpu != CPU_X86_64:
        raise ValueError('Expected a little-endian x86_64 Mach-O image')
    end_commands = 32 + command_bytes
    if end_commands > len(data):
        raise ValueError('Truncated Mach-O commands')
    libraries = []
    symbols = None
    offset = 32
    for _ in range(count):
        command, size = unpack('<2I', data, offset)
        if size < 8 or offset + size > end_commands:
            raise ValueError('Invalid Mach-O command size')
        if command in (LOAD, WEAK_LOAD, REEXPORT, UPWARD_LOAD):
            name_offset, = unpack('<I', data, offset + 8)
            if size < 24 or name_offset < 24:
                raise ValueError('Invalid dylib command')
            libraries.append((cstring(data, offset + name_offset, offset + size),
                              command))
        elif command == 2:  # LC_SYMTAB
            if size < 24:
                raise ValueError('Invalid symbol-table command')
            symbols = unpack('<4I', data, offset + 8)
        offset += size
    if offset != end_commands or symbols is None:
        raise ValueError('Missing or malformed Mach-O symbol table')
    symbol_offset, symbol_count, string_offset, string_size = symbols
    if (symbol_offset + symbol_count * 16 > len(data) or
            string_offset + string_size > len(data)):
        raise ValueError('Truncated Mach-O symbol table')
    exports, imports = set(), []
    for index in range(symbol_count):
        name_index, kind, _, description, _ = unpack(
            '<IBBHQ', data, symbol_offset + index * 16)
        if kind & 0xE0 or not kind & 1 or name_index == 0:
            continue
        name = cstring(data, string_offset + name_index,
                       string_offset + string_size)
        if kind & 0x0E:
            exports.add(name)
        else:
            ordinal = description >> 8
            weak = bool(description & 0x40)  # N_WEAK_REF
            imports.append((name, ordinal, weak))
    return Image(libraries, exports, imports)


def resolve_in_root(root, path):
    """Resolve absolute OS symlinks inside the supplied root, never the host."""
    remaining = deque(PurePosixPath(path).parts)
    parts, links = [], 0
    while remaining:
        part = remaining.popleft()
        if part == '/':
            parts.clear()
        elif part == '..':
            if parts:
                parts.pop()
        elif part not in ('', '.'):
            candidate = root.joinpath(*parts, part)
            if candidate.is_symlink():
                links += 1
                if links > 40:
                    raise ValueError('Too many OS-root symlinks')
                remaining.extendleft(reversed(PurePosixPath(
                    os.readlink(candidate)).parts))
            else:
                parts.append(part)
    return root.joinpath(*parts)


class SystemExports:
    def __init__(self, root):
        self.root = root
        self.cache = {}
        self.incomplete = set()

    def get(self, path, visiting=None, optional=False):
        visiting = visiting or set()
        if path in visiting:
            return set()
        if path in self.cache:
            return self.cache[path]
        if not path.startswith('/'):
            self.incomplete.add(path)
            return set()
        try:
            image = read_image(resolve_in_root(self.root, path).read_bytes())
        except OSError as error:
            if not optional:
                self.incomplete.add(f'{path}: {error}')
            return set()
        except ValueError as error:
            self.incomplete.add(f'{path}: {error}')
            return set()
        exports = set(image.exports)
        for library, command in image.libraries:
            if command == REEXPORT:
                if library.startswith('@loader_path/'):
                    library = str(PurePosixPath(path).parent /
                                  library.removeprefix('@loader_path/'))
                exports.update(self.get(library, visiting | {path}))
        self.cache[path] = exports
        return exports


def audit(binary, system_root):
    image = read_image(binary.read_bytes())
    system = SystemExports(system_root)
    missing, weak_missing, unknown = [], [], []
    for name, ordinal, weak in image.imports:
        if not 1 <= ordinal <= len(image.libraries):
            unknown.append({'symbol': name, 'ordinal': ordinal})
            continue
        library, command = image.libraries[ordinal - 1]
        target = weak_missing if weak or command == WEAK_LOAD else missing
        if name not in system.get(library, optional=command == WEAK_LOAD):
            target.append({'symbol': name, 'library': library})
    # Required dylibs must exist even if they have no imported symbols.
    for library, command in image.libraries:
        if command != WEAK_LOAD:
            system.get(library)
    return {
        'schema_version': 1,
        'binary': str(binary),
        'system_root': str(system_root),
        'checked_imports': len(image.imports),
        'missing_required': missing,
        'missing_weak': weak_missing,
        'unknown_ordinals': unknown,
        'incomplete_libraries': sorted(system.incomplete),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--system-root', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = audit(args.binary, args.system_root)
    text = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
        print(f"{report['checked_imports']} imports; "
              f"{len(report['missing_required'])} required symbols missing; "
              f"{len(report['missing_weak'])} optional symbols missing; "
              f"{len(report['incomplete_libraries'])} incomplete libraries")
    else:
        print(text, end='')
    return bool(report['missing_required'] or report['unknown_ordinals'] or
                report['incomplete_libraries'])


if __name__ == '__main__':
    raise SystemExit(main())
