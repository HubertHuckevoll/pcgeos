#!/usr/bin/env python3
"""Check PNG chunk integrity and require a complete zlib stream."""

import binascii
import struct
import sys
import zlib


def check_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("bad PNG signature")

    offset = 8
    idat = []
    saw_iend = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("truncated chunk")
        chunk_data = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[end - 4:end])[0]
        actual_crc = binascii.crc32(chunk_type + chunk_data) & 0xffffffff
        if actual_crc != expected_crc:
            raise ValueError("bad %s CRC" % chunk_type.decode("ascii"))
        if chunk_type == b"IDAT":
            idat.append(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
        offset = end

    stream = zlib.decompressobj()
    stream.decompress(b"".join(idat))
    if not stream.eof:
        raise ValueError("unfinished zlib stream")
    if not saw_iend or offset != len(data):
        raise ValueError("missing or malformed IEND")


if len(sys.argv) < 2:
    raise SystemExit("usage: check_png.py FILE...")

for filename in sys.argv[1:]:
    try:
        check_png(filename)
    except (OSError, ValueError, zlib.error) as error:
        raise SystemExit("%s: %s" % (filename, error))
    print("%s: OK" % filename)
