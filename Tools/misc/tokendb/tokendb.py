#!/usr/bin/env python3
"""Export and build PC/GEOS 2.x token databases. Requires Pillow.

Implemented with ChatGPT Codex, prompted by MeyerK.
See README.md for format references, editing rules and supported GStrings.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile

from PIL import Image


class FormatError(ValueError):
    pass


def take(data, offset, size):
    if offset < 0 or size < 0 or offset + size > len(data):
        raise FormatError(f'out-of-bounds data: offset {offset}, size {size}')
    return data[offset:offset + size]


def words(data, offset, count=1):
    return struct.unpack('<' + 'H' * count, take(data, offset, count * 2))


def word(data, offset):
    return words(data, offset)[0]


def pack(*values):
    return struct.pack('<' + 'H' * len(values), *values)


def align4(n):
    return (n + 3) & ~3


def b64(data):
    return base64.b64encode(data).decode('ascii')


def unb64(value):
    return base64.b64decode(value, validate=True)


# Exact system palette shared with cvtpcx (not Pillow's default palette).
PALETTE = bytes.fromhex(
    '0000000000aa00aa0000aaaaaa0000aa00aaaa5500aaaaaa5555555555ff55ff5555ffffff5555ff55ffffff55ffffff'
    '000000111111222222333333444444555555666666777777888888999999aaaaaabbbbbbccccccddddddeeeeeeffffff'
    '0000000000000000000000000000000000000000000000000000000000330000660000990000cc0000ff003300003333'
    '0033660033990033cc0033ff0066000066330066660066990066cc0066ff0099000099330099660099990099cc0099ff'
    '00cc0000cc3300cc6600cc9900cccc00ccff00ff0000ff3300ff6600ff9900ffcc00ffff330000330033330066330099'
    '3300cc3300ff3333003333333333663333993333cc3333ff3366003366333366663366993366cc3366ff339900339933'
    '3399663399993399cc3399ff33cc0033cc3333cc6633cc9933cccc33ccff33ff0033ff3333ff6633ff9933ffcc33ffff'
    '6600006600336600666600996600cc6600ff6633006633336633666633996633cc6633ff666600666633666666666699'
    '6666cc6666ff6699006699336699666699996699cc6699ff66cc0066cc3366cc6666cc9966cccc66ccff66ff0066ff33'
    '66ff6666ff9966ffcc66ffff9900009900339900669900999900cc9900ff9933009933339933669933999933cc9933ff'
    '9966009966339966669966999966cc9966ff9999009999339999669999999999cc9999ff99cc0099cc3399cc6699cc99'
    '99cccc99ccff99ff0099ff3399ff6699ff9999ffcc99ffffcc0000cc0033cc0066cc0099cc00cccc00ffcc3300cc3333'
    'cc3366cc3399cc33cccc33ffcc6600cc6633cc6666cc6699cc66cccc66ffcc9900cc9933cc9966cc9999cc99cccc99ff'
    'cccc00cccc33cccc66cccc99ccccccccccffccff00ccff33ccff66ccff99ccffccccffffff0000ff0033ff0066ff0099'
    'ff00ccff00ffff3300ff3333ff3366ff3399ff33ccff33ffff6600ff6633ff6666ff6699ff66ccff66ffff9900ff9933'
    'ff9966ff9999ff99ccff99ffffcc00ffcc33ffcc66ffcc99ffccccffccffffff00ffff33ffff66ffff99ffffccffffff'
)


class Database:
    def __init__(self, data):
        self.data = data
        if take(data, 0, 4) != b'\xc7E\xc1S':
            raise FormatError('expected a GEOS 2.x file (GEAS signature)')
        if word(data, 256) != 0xadeb:
            raise FormatError('not a VM file')
        hsize = word(data, 258)
        pos = struct.unpack('<I', take(data, 260, 4))[0] + 256
        header = take(data, pos, hsize)
        if word(header, 0) != 0xfb:
            raise FormatError('invalid VM header signature')
        limit = word(header, 8)
        if limit > hsize or limit < 44 or (limit - 32) % 12:
            raise FormatError('invalid VM handle table')
        self.blocks = {}
        for handle in range(32, limit, 12):
            if header[handle + 2] == 255:
                size = word(header, handle + 6)
                offset = struct.unpack('<I', take(header, handle + 8, 4))[0] + 256
                self.blocks[handle] = take(data, offset, size)
        dbmap = self.block(word(header, 30))
        self.map = self.item(*words(dbmap, 4, 2))
        if not self.map or len(self.map) % 24:
            raise FormatError('token map must contain 24-byte TokenEntry records')
        self.file_header = take(data, 0, 256)

    def block(self, handle):
        try:
            return self.blocks[handle]
        except KeyError:
            raise FormatError(f'invalid VM block handle {handle:#x}') from None

    def item(self, group, item):
        group_data = self.block(group)
        info, chunk = words(group_data, item, 2)
        block = self.block(word(group_data, info + 2))
        table, count = word(block, 2), word(block, 10)
        if chunk < table or chunk >= table + count * 2 or (chunk - table) % 2:
            raise FormatError('invalid LMem chunk handle')
        offset = word(block, chunk)
        size = word(block, offset - 2) - 2
        return take(block, offset, size)

    def tokens(self):
        for off in range(24, len(self.map), 24):
            entry = self.map[off:off + 24]
            monikers = self.item(*words(entry, 6, 2))
            if len(monikers) % 6:
                raise FormatError('invalid moniker list length')
            yield entry, [(typ, self.item(group, item)) for typ, group, item in
                          struct.iter_unpack('<HHH', monikers)]


def unpackbits(data, expected):
    out = bytearray()
    pos = 0
    while len(out) < expected:
        control = take(data, pos, 1)[0]
        pos += 1
        if control < 128:
            size = control + 1
            out.extend(take(data, pos, size))
            pos += size
        else:
            out.extend(take(data, pos, 1) * (257 - control))
            pos += 1
        # GEOS treats 0x80 as a run of 129, unlike standard Mac PackBits.
        if len(out) > expected:
            raise FormatError('PackBits data exceeds bitmap size')
    if pos != len(data):
        raise FormatError('trailing PackBits data')
    return bytes(out)


def bitmap_image(data, fill_color=(0, 0, 0), fill=False):
    width, height = words(data, 0, 2)
    compact, typ = take(data, 4, 2)
    fmt = typ & 7
    if not width or not height or width * height > 16_000_000:
        raise FormatError('invalid or excessive bitmap dimensions')
    if fmt > 3 or typ & 0x20:
        raise FormatError(f'unsupported bitmap type {typ:#x}')
    palette = PALETTE
    start = 6
    if typ & 8:
        if words(data, 6, 2) != (0, height):
            raise FormatError('sliced complex bitmap is not supported')
        start = word(data, 12)
        if start < 20:
            raise FormatError('complex bitmap data overlaps its header')
        if typ & 0x40:
            offset = word(data, 14)
            count = word(data, offset)
            if not 1 <= count <= 256:
                raise FormatError('invalid palette size')
            palette = take(data, offset + 2, count * 3)
    bpp = (1, 4, 8, 24)[fmt]
    stride = (width * bpp + 7) // 8
    mask_stride = (width + 7) // 8 if typ & 0x10 else 0
    expected = (stride + mask_stride) * height
    pixels = data[start:]
    if compact == 1:
        pixels = unpackbits(pixels, expected)
    elif compact != 0:
        raise FormatError(f'unsupported bitmap compression {compact}')
    if len(pixels) != expected:
        raise FormatError('bitmap byte count does not match dimensions')
    rgba = bytearray()
    for y in range(height):
        row = pixels[y * (stride + mask_stride):(y + 1) * (stride + mask_stride)]
        mask, row = row[:mask_stride], row[mask_stride:]
        for x in range(width):
            if fmt == 0:
                color = (fill_color if fill else (0, 0, 0)) if row[x // 8] & (128 >> (x % 8)) else (255, 255, 255)
            elif fmt in (1, 2):
                index = (row[x // 2] >> (4 if x % 2 == 0 else 0)) & 15 if fmt == 1 else row[x]
                color = take(palette, index * 3, 3)
            else:
                # GEOS BMF_24BIT stores red, green, blue triples.
                color = take(row, x * 3, 3)
            alpha = 255 if not mask_stride or mask[x // 8] & (128 >> (x % 8)) else 0
            if fill and fmt == 0 and not row[x // 8] & (128 >> (x % 8)):
                alpha = 0  # GrFillBitmap treats mono pixels as an area mask.
            rgba.extend((*color, alpha))
    return Image.frombytes('RGBA', (width, height), bytes(rgba))


def render_moniker(raw):
    """Play bitmap-only GStrings; reject unknown operations instead of guessing."""
    if not take(raw, 0, 1)[0] & 0x40:
        return None
    width, height = words(raw, 1, 2)
    if not width or not height or width * height > 16_000_000:
        raise FormatError('invalid moniker dimensions')
    canvas = Image.new('RGBA', (width, height))
    pos, seen = 5, False
    fill_color = (0, 0, 0)
    current = (0, 0)
    while True:
        op = take(raw, pos, 1)[0]
        pos += 1
        if op == 0:
            if pos != len(raw) or not seen:
                raise FormatError('invalid end of bitmap GString')
            return canvas
        if op == 2:  # GR_NULL_OP
            continue
        if op == 0x62:  # GR_SET_MIX_MODE: only MM_COPY
            if take(raw, pos, 1) != b'\1':
                raise FormatError('unsupported mix mode')
            pos += 1
            continue
        if op == 0x79:  # GR_SET_AREA_COLOR_INDEX
            fill_color = tuple(take(PALETTE, take(raw, pos, 1)[0] * 3, 3))
            pos += 1
            continue
        if op == 0x75:  # GR_SET_AREA_COLOR (RGB triple)
            fill_color = tuple(take(raw, pos, 3))
            pos += 3
            continue
        if op == 0x63:  # GR_MOVE_TO
            current = struct.unpack('<hh', take(raw, pos, 4))
            pos += 4
            continue
        if op == 0x64:  # GR_REL_MOVE_TO (two signed 16.16 values)
            dx, dy = struct.unpack('<ii', take(raw, pos, 8))
            if dx % 65536 or dy % 65536:
                raise FormatError('fractional current position is not supported')
            current = (current[0] + dx // 65536, current[1] + dy // 65536)
            pos += 8
            continue
        if op in (0x4c, 0x50):
            x, y = struct.unpack('<hh', take(raw, pos, 4))
            current = (x, y)
            pos += 4
        elif op in (0x4d, 0x51):
            x, y = current
        else:
            raise FormatError(f'unsupported GString opcode {op:#x} at {pos - 1}')
        size = word(raw, pos)
        pos += 2
        image = bitmap_image(take(raw, pos, size), fill_color, op in (0x4c, 0x4d))
        pos += size
        canvas.alpha_composite(image, (x, y))
        seen = True


def image_hash(image):
    return hashlib.sha256(pack(*image.size) + image.convert('RGBA').tobytes()).hexdigest()


def safe_file(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise FormatError('manifest path escapes the export directory')
    return path


def export_db(source, directory):
    db = Database(source.read_bytes())
    # Refuse an existing output directory so stale PNGs cannot be reimported.
    directory.mkdir(parents=True, exist_ok=False)
    manifest = {'format': 'pcgeos-token-db', 'version': 1,
                'file_header': b64(db.file_header), 'dummy_entry': b64(db.map[:24]),
                'tokens': []}
    count = 0
    unsupported = []
    for index, (entry, monikers) in enumerate(db.tokens()):
        chars = entry[:4]
        manufacturer, flags = word(entry, 4), word(entry, 10)
        label = ''.join(chr(c) if chr(c).isascii() and chr(c).isalnum() else '_' for c in chars)
        folder = f'{index:04d}_{label}_{manufacturer:04x}'
        (directory / folder).mkdir()
        token = {'token_hex': chars.hex(), 'manufacturer': manufacturer,
                 'flags': flags, 'release': list(words(entry, 12, 4)),
                 'protocol': list(words(entry, 20, 2)), 'monikers': []}
        for number, (typ, raw) in enumerate(monikers):
            name = f'{folder}/{number:02d}_{typ:04x}'
            safe_file(directory, name + '.bin').write_bytes(raw)
            moniker = {'type': typ, 'raw': name + '.bin'}
            try:
                image = render_moniker(raw)
                if image is not None:
                    image.save(safe_file(directory, name + '.png'))
                    moniker.update(png=name + '.png', pixel_sha256=image_hash(image))
                    count += 1
                else:
                    moniker['text_hex'] = raw[4:].hex()  # informational, raw is authoritative
            except FormatError as error:
                moniker['unsupported'] = str(error)
                unsupported.append(name + ': ' + str(error))
            token['monikers'].append(moniker)
        manifest['tokens'].append(token)
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Exported {len(manifest["tokens"])} tokens, {count} PNGs; '
          f'{len(unsupported)} unsupported graphics preserved as raw data.')
    for message in unsupported:
        print('  ' + message, file=sys.stderr)


def encode_moniker(image, typ):
    """Create a simple uncompressed GEOS bitmap GString from an RGBA PNG.

    Retain mono/4-bit/8-bit variants using the system palette;
    truecolor remains 24-bit. Alpha is binary (<128).
    """
    if typ & 0xc0 != 0xc0:
        raise FormatError('PNG moniker type must have the graphics and moniker-list bits set')
    image = image.convert('RGBA')
    width, height = image.size
    if not 1 <= width <= 32767 or not 1 <= height <= 32767:
        raise FormatError('PNG dimensions must be in 1..32767')
    display_class = typ & 15
    fmt = 0 if display_class <= 1 else (1 if display_class <= 6 else (2 if display_class == 7 else 3))
    colors = image.tobytes()
    masked = any(a < 128 for a in colors[3::4])
    mask_stride = (width + 7) // 8 if masked else 0
    bpp = (1, 4, 8, 24)[fmt]
    stride = (width * bpp + 7) // 8
    if (mask_stride + stride) * height > 64000:
        raise FormatError('PNG exceeds the single-block GEOS bitmap limit')
    palette = PALETTE[:48] if fmt == 1 else PALETTE
    indexes = {}
    out = bytearray()
    for y in range(height):
        row = bytearray(mask_stride + stride)
        for x in range(width):
            offset = (y * width + x) * 4
            r, g, b, a = colors[offset:offset + 4]
            if masked and a >= 128:
                row[x // 8] |= 128 >> (x % 8)
            if fmt == 0:
                if (r * 299 + g * 587 + b * 114) < 128000:
                    row[mask_stride + x // 8] |= 128 >> (x % 8)
            elif fmt in (1, 2):
                rgb = (r, g, b)
                if rgb not in indexes:
                    indexes[rgb] = min(range(len(palette) // 3), key=lambda i:
                        sum(abs(rgb[c] - palette[3 * i + c]) for c in range(3)))
                index = indexes[rgb]
                if fmt == 1:
                    row[mask_stride + x // 2] |= index << (4 if x % 2 == 0 else 0)
                else:
                    row[mask_stride + x] = index
            else:
                row[mask_stride + x * 3:mask_stride + x * 3 + 3] = bytes((r, g, b))
        out.extend(row)
    bitmap = pack(width, height) + bytes((0, fmt | (0x10 if masked else 0))) + out
    if len(bitmap) > 65535:
        raise FormatError('bitmap is too large')
    return bytes(((typ & 0x7f) | 0x40,)) + pack(width, height) + b'\x51' + pack(len(bitmap)) + bitmap + b'\0'


class Builder:
    """Build compact VM/DB blocks, keeping each ordinary item block below 8K."""
    def __init__(self):
        self.blocks = [(0xadeb, 0, b'')]  # VM header, handle 0x20
        self.groups = {}
        self.group_order = []

    def alloc(self, uid, flags=0, data=b''):
        handle = 32 + len(self.blocks) * 12
        if handle + 12 > 65535:
            raise FormatError('VM handle table exceeds 64K')
        self.blocks.append((uid, flags, data))
        return handle

    def put(self, handle, data):
        index = (handle - 32) // 12
        uid, flags, _ = self.blocks[index]
        if len(data) > 65535:
            raise FormatError('VM block exceeds 64K')
        self.blocks[index] = (uid, flags, data)

    def add(self, typ, data):
        if len(data) > 65000:
            raise FormatError('DB item exceeds 65000 bytes')
        group = self.groups.get(typ)
        if group is None or (group['items'] and group['size'] + align4(len(data) + 2) + 2 > 8192):
            group = {'handle': self.alloc(0xff01), 'block': self.alloc(0xff02, 1),
                     'items': [], 'size': 20}
            self.groups[typ] = group
            self.group_order.append(group)
        item = 16 + 4 * len(group['items'])
        if item + 10 > 65535:
            raise FormatError('DB group exceeds 64K')
        group['items'].append(data)
        group['size'] += align4(len(data) + 2) + 2
        return group['handle'], item

    def finish_groups(self):
        for group in self.group_order:
            items = group['items']
            handle, block_handle = group['handle'], group['block']
            info = 16 + len(items) * 4
            grp = pack(handle, 0, 0, info, 0, 0, info + 6, 0)
            grp += b''.join(pack(info, 20 + i * 2) for i in range(len(items)))
            grp += pack(0, block_handle, len(items))
            self.put(handle, grp)
            # Keep the handle table a multiple of four bytes, then place
            # each size word at 4n and chunk data at 4n+2 (LMValidateChunks).
            nhandles = (len(items) + 1) & ~1
            start = 20 + nhandles * 2
            body = bytearray(start)
            for i, data in enumerate(items):
                struct.pack_into('<H', body, 20 + i * 2, len(body) + 2)
                body.extend(pack(len(data) + 2) + data)
                body.extend(b'\0' * ((-len(body)) % 4))
            struct.pack_into('<10H', body, 0, 0, 20, 0x100, 0, len(body), nhandles,
                             0, 0, block_handle, info)
            self.put(block_handle, bytes(body))

    def write(self, header, map_handle, dbmap_handle):
        self.finish_groups()
        hsize = 32 + len(self.blocks) * 12
        vmheader = bytearray(hsize)
        # No assigned/unassigned handles or free disk extents in a compact file.
        struct.pack_into('<12H', vmheader, 0, 0xfb, 0, 0, 0, hsize, 0, 0,
                         len(self.blocks), 0, 0, map_handle, 70)
        struct.pack_into('<I', vmheader, 24, hsize + sum(len(b[2]) for b in self.blocks))
        struct.pack_into('<H', vmheader, 30, dbmap_handle)
        # VM block positions are relative to the end of the 256-byte GEOS header.
        pos = 24 + hsize
        for i, (uid, flags, data) in enumerate(self.blocks):
            size, offset = (hsize, 24) if i == 0 else (len(data), pos)
            struct.pack_into('<HBBHHI', vmheader, 32 + 12 * i, 0, 255, flags, uid, size, offset)
            if i:
                pos += size
        return header + pack(0xadeb, hsize) + struct.pack('<I', 24) + bytes(16) + vmheader + b''.join(b[2] for b in self.blocks[1:])


def build_db(directory, target):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest.get('format') != 'pcgeos-token-db' or manifest.get('version') != 1:
        raise FormatError('unsupported manifest format/version')
    builder = Builder()
    entries = bytearray(unb64(manifest.get('dummy_entry', b64(bytes(24)))))
    if len(entries) != 24:
        raise FormatError('dummy entry must be 24 bytes')
    seen = set()
    for token in manifest['tokens']:
        chars = bytes.fromhex(token['token_hex'])
        manufacturer = token['manufacturer']
        key = (chars, manufacturer)
        if len(chars) != 4 or key in seen:
            raise FormatError('token must have four bytes and a unique manufacturer/token pair')
        seen.add(key)
        if not token['monikers']:
            raise FormatError('each token needs at least one moniker')
        monikers = bytearray()
        for moniker in token['monikers']:
            typ = moniker['type']
            raw = safe_file(directory, moniker['raw']).read_bytes() if moniker.get('raw') else None
            if moniker.get('png'):
                with Image.open(safe_file(directory, moniker['png'])) as source:
                    if source.format != 'PNG':
                        raise FormatError('expected PNG image')
                    if source.width * source.height > 16_000_000:
                        raise FormatError('PNG exceeds 16 million pixels')
                    image = source.convert('RGBA')
                # Compare with the actual raw moniker, not an editable hash alone.
                original = None
                if raw is not None:
                    try:
                        original = render_moniker(raw)
                    except FormatError:
                        pass
                if original is None or image_hash(image) != image_hash(original):
                    raw = encode_moniker(image, typ)
            if raw is None:
                raise FormatError('each moniker needs a raw file or PNG')
            monikers.extend(pack(typ, *builder.add(typ, raw)))
        group, item = builder.add(0xffff, bytes(monikers))
        release, protocol = token.get('release', [0] * 4), token.get('protocol', [0] * 2)
        if len(release) != 4 or len(protocol) != 2:
            raise FormatError('release/protocol need four/two words')
        entries.extend(chars + pack(manufacturer, group, item, token.get('flags', 0), *release, *protocol))
    map_group, map_item = builder.add('token-map', bytes(entries))
    map_handle = builder.alloc(0)
    mapping = [(typ, group['handle']) for typ, group in builder.groups.items() if isinstance(typ, int)]
    # Keep the moniker-list group first, as InitializeLocalTokenDB does.
    mapping.sort(key=lambda pair: (pair[0] != 0xffff, pair[0]))
    map_size = 4 + 4 * len(mapping)
    builder.put(map_handle, pack(map_size, map_size) + b''.join(pack(*p) for p in mapping))
    dbmap_handle = builder.alloc(0xff00)
    builder.put(dbmap_handle, pack(dbmap_handle, 0, map_group, map_item, 0, 0))
    header = unb64(manifest['file_header'])
    if len(header) != 256 or header[:4] != b'\xc7E\xc1S':
        raise FormatError('invalid GEOS file header')
    result = builder.write(header, map_handle, dbmap_handle)
    # Verify all DB references before writing and use atomic replacement.
    rebuilt = Database(result)
    if len(list(rebuilt.tokens())) != len(manifest['tokens']):
        raise FormatError('internal error rebuilding token map')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix=target.name + '.')
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(result)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'Built {len(seen)} tokens: {target} ({len(result)} bytes)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    export = sub.add_parser('export', help='extract monikers, PNGs and manifest.json')
    export.add_argument('database', type=Path)
    export.add_argument('directory', type=Path)
    build = sub.add_parser('build', help='build a GEOS token database from an export directory')
    build.add_argument('directory', type=Path)
    build.add_argument('database', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'export':
            export_db(args.database, args.directory)
        else:
            build_db(args.directory, args.database)
    except (ValueError, OSError, KeyError, IndexError, struct.error) as error:
        parser.exit(1, f'tokendb: {error}\n')


if __name__ == '__main__':
    main()
