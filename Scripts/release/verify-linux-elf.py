#!/usr/bin/env python3
"""Reject shell mocks, interpreters and dynamic runtime dependencies in release binaries."""
import struct
import sys
from pathlib import Path


def verify(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01':
        raise ValueError('Release binary must be a real little-endian ELF64 executable')
    elf_type, machine = struct.unpack_from('<HH', data, 16)
    if elf_type not in (2, 3) or machine != 62:
        raise ValueError('Release binary must target Linux x86_64')
    phoff = struct.unpack_from('<Q', data, 32)[0]
    phsize, phcount = struct.unpack_from('<HH', data, 54)
    if phsize < 56 or phcount == 0 or phoff + phcount * phsize > len(data):
        raise ValueError('Invalid ELF program header table')
    for index in range(phcount):
        header = phoff + index * phsize
        kind = struct.unpack_from('<I', data, header)[0]
        if kind == 3:
            raise ValueError('PT_INTERP is forbidden: the release requires a runtime loader')
        if kind == 2:
            offset = struct.unpack_from('<Q', data, header + 8)[0]
            size = struct.unpack_from('<Q', data, header + 32)[0]
            if offset + size > len(data) or size % 16:
                raise ValueError('Invalid ELF dynamic table')
            for entry in range(offset, offset + size, 16):
                tag = struct.unpack_from('<Q', data, entry)[0]
                if tag == 1:
                    raise ValueError('DT_NEEDED is forbidden: the release requires shared libraries')
                if tag == 0:
                    break
    print('ELF64 x86_64 verified: no PT_INTERP or DT_NEEDED runtime dependencies.')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]))
    except (ValueError, OSError, IndexError, struct.error) as error:
        print(f'Linux release verification failed: {error}', file=sys.stderr)
        sys.exit(1)
