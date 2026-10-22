#!/usr/bin/env python3
"""Structural verification of PC/GEOS BSWF bitmap font files."""
import argparse
from pathlib import Path
import struct


def u16(data, off):
    return struct.unpack_from('<H', data, off)[0]


def u32(data, off):
    return struct.unpack_from('<I', data, off)[0]


def verify(path):
    data = path.read_bytes()
    if len(data) < 41 or data[:4] != b'BSWF' or u16(data, 4) != 0x100:
        raise ValueError('not a version 1 BSWF font')
    start = u16(data, 33) + 6
    end = u16(data, 35) + 6
    if start != 41 or end < start or (end - start) % 10 or end > len(data):
        raise ValueError('invalid point-size table')
    if u16(data, 6) + 8 != end:
        raise ValueError('header size mismatch')
    count = (end - start) // 10
    if count == 0:
        raise ValueError('no bitmap strikes')
    positions = []
    for i in range(count):
        item = start + 10 * i
        point_size = u16(data, item + 2)
        size = u16(data, item + 4)
        position = u32(data, item + 6)
        if position < end or size < 71 or position + size > len(data):
            raise ValueError('invalid strike offset or size: %d' % i)
        positions.append((position, position + size))
        s = data[position:position + size]
        if u16(s, 0) != size or u16(s, 2) != 0:
            raise ValueError('invalid bitmap strike header: %d' % i)
        first, last = s[40], s[41]
        if first > last or not (first <= s[42] <= last):
            raise ValueError('invalid character range: %d' % i)
        table_end = 71 + (last - first + 1) * 8
        if table_end > size:
            raise ValueError('character table too long: %d' % i)
        present = 0
        for c in range(first, last + 1):
            entry = 71 + 8 * (c - first)
            offset = u16(s, entry)
            flags = s[entry + 5]
            if flags & 8:
                if offset != 0:
                    raise ValueError('invalid missing-glyph sentinel: 0x%02x' % c)
                continue
            if offset < table_end or offset + 4 > size:
                raise ValueError('glyph header out of bounds: %d' % c)
            width = s[offset]
            rows = s[offset + 1]
            if offset + 4 + (width + 7) // 8 * rows > size:
                raise ValueError('glyph bitmap out of bounds: %d' % c)
            present += 1
        default_entry = 71 + 8 * (s[42] - first)
        if s[default_entry + 5] & 8:
            raise ValueError('default glyph is missing: %d' % i)
        print('%2d pt: %3d/%3d glyphs, %5d bytes' %
              (point_size, present, last - first + 1, size))
    if sorted(positions) != positions:
        raise ValueError('strikes out of order')
    for a, b in zip(positions, positions[1:]):
        if a[1] > b[0]:
            raise ValueError('overlapping strikes')
    if positions[-1][1] != len(data):
        raise ValueError('unexpected bytes after final strike')
    print('OK: %d BSWF strikes in %s' % (count, path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('font', type=Path)
    args = parser.parse_args()
    verify(args.font)


if __name__ == '__main__':
    main()
