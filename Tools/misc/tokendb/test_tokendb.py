"""Host-side integration tests, including real token databases and cvtpcx.

python -m unittest discover -s Tools/misc/tokendb -v
CVTPCX=/path/to/cvtpcx python -m unittest discover -s Tools/misc/tokendb -v
"""
import contextlib
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

from PIL import Image
import tokendb as t

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / 'Installed/ProductFiles/Build/bbxensem/Misc/token_da.000'


def quiet(function, *args):
    with contextlib.redirect_stdout(io.StringIO()):
        return function(*args)


def semantic(db):
    # Physical handles may change; all token metadata and moniker bytes must not.
    return [(entry[:6] + entry[10:], monikers) for entry, monikers in db.tokens()]


def validate_layout(data):
    """Independent checks matching VMCheckUsedBlks and LMValidateChunks.

    Deliberately walk the physical heaps, not just Database.item references:
    an invalid heap may still be readable by a permissive item extractor.
    """
    size, pos = struct.unpack_from('<HI', data, 258)
    header = data[256 + pos:256 + pos + size]
    used = 0
    extents = []
    for handle in range(32, len(header), 12):
        memory, sig, flags, uid, length, offset = struct.unpack_from('<HBBHHI', header, handle)
        if sig != 255:
            continue
        used += 1
        assert memory == 0
        extents.append((offset, offset + length))
        if uid != 0xff02:
            continue
        block = data[256 + offset:256 + offset + length]
        table, heap_size, count = struct.unpack_from('<H4xHH', block, 2)
        assert table == 20 and heap_size == len(block)
        assert struct.unpack_from('<H', block, 12)[0] == 0  # no free chunks
        refs = set(struct.unpack_from('<' + 'H' * count, block, table)) - {0}
        cursor = table + count * 2
        pointers = set()
        while cursor < heap_size:
            chunk_size = struct.unpack_from('<H', block, cursor)[0]
            assert chunk_size >= 2
            pointers.add(cursor + 2)
            cursor += (chunk_size + 3) & ~3
        assert cursor == heap_size
        assert refs == pointers
    assert used == struct.unpack_from('<H', header, 14)[0]
    extents.sort()
    assert extents[0][0] == 24
    assert all(a[1] == b[0] for a, b in zip(extents, extents[1:]))
    assert extents[-1][1] + 256 == len(data)
    assert sum(b - a for a, b in extents) == struct.unpack_from('<I', header, 24)[0]


class TokenDBTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.export = self.root / 'icons'
        quiet(t.export_db, FIXTURE, self.export)

    def manifest(self):
        return json.loads((self.export / 'manifest.json').read_text())

    def save_manifest(self, manifest):
        (self.export / 'manifest.json').write_text(json.dumps(manifest))

    def rebuild(self):
        target = self.root / 'token.000'
        quiet(t.build_db, self.export, target)
        validate_layout(target.read_bytes())
        return t.Database(target.read_bytes())

    def test_real_databases_lossless(self):
        fixtures = [FIXTURE, ROOT / 'Tools/build/product/bbxensem/Images/Windemo/token_da.000']
        for number, fixture in enumerate(fixtures):
            expected = (90, 395, 77) if number == 0 else (29, 87, 0)
            with self.subTest(fixture=str(fixture)):
                folder = self.root / f'fixture{number}'
                quiet(t.export_db, fixture, folder)
                manifest = json.loads((folder / 'manifest.json').read_text())
                self.assertEqual(len(manifest['tokens']), expected[0])
                monikers = [m for token in manifest['tokens'] for m in token['monikers']]
                self.assertEqual(sum('png' in m for m in monikers), expected[1])
                self.assertEqual(sum('text_hex' in m for m in monikers), expected[2])
                self.assertFalse(any('unsupported' in m for m in monikers))
                target = self.root / f'rebuilt{number}.000'
                quiet(t.build_db, folder, target)
                validate_layout(target.read_bytes())
                before, after = t.Database(fixture.read_bytes()), t.Database(target.read_bytes())
                self.assertEqual(semantic(before), semantic(after))
                self.assertEqual(before.file_header, after.file_header)

    def test_edit_png(self):
        manifest = self.manifest()
        png = self.export / manifest['tokens'][0]['monikers'][0]['png']
        with Image.open(png) as source:
            image = source.convert('RGBA')
        image.putpixel((0, 0), (170, 0, 0, 255))
        image.putpixel((1, 0), (0, 0, 0, 0))
        image.save(png)
        after = list(self.rebuild().tokens())
        rendered = t.render_moniker(after[0][1][0][1])
        self.assertEqual(rendered.getpixel((0, 0)), (170, 0, 0, 255))
        self.assertEqual(rendered.getpixel((1, 0))[3], 0)
        before = list(t.Database(FIXTURE.read_bytes()).tokens())
        self.assertEqual(after[0][1][1:], before[0][1][1:])
        self.assertEqual(semantic(t.Database(FIXTURE.read_bytes()))[1:], semantic(self.rebuild())[1:])

    def test_add_remove_reorder_tokens_and_png_only(self):
        manifest = self.manifest()
        image = Image.new('RGBA', (15, 15), (0, 0, 170, 255))
        image.save(self.export / 'new.png')
        manifest['tokens'] = list(reversed(manifest['tokens'][:-1]))
        manifest['tokens'].append({'token_hex': b'TEST'.hex(), 'manufacturer': 16431,
                                  'monikers': [{'type': 0x04c6, 'png': 'new.png'}]})
        self.save_manifest(manifest)
        after = list(self.rebuild().tokens())
        self.assertEqual(len(after), 90)
        self.assertEqual(after[-1][0][:6], b'TEST' + t.pack(16431))
        self.assertEqual(t.render_moniker(after[-1][1][0][1]).getpixel((0, 0)), (0, 0, 170, 255))

    def test_unknown_gstring_and_text_preserved(self):
        manifest = self.manifest()
        unknown = b'\x41' + t.pack(10, 10) + b'\x2c' + t.pack(0, 0, 9, 9) + b'\0'
        (self.export / 'unknown.bin').write_bytes(unknown)
        manifest['tokens'][0]['monikers'].append({'type': 0x04c1, 'raw': 'unknown.bin'})
        self.save_manifest(manifest)
        db = self.rebuild()
        self.assertEqual(list(db.tokens())[0][1][-1][1], unknown)
        target = self.root / 'token.000'
        with contextlib.redirect_stderr(io.StringIO()):
            quiet(t.export_db, target, self.root / 'unknown-export')
        result = json.loads((self.root / 'unknown-export/manifest.json').read_text())
        self.assertIn('unsupported', result['tokens'][0]['monikers'][-1])

    def test_manifest_validation_and_atomic_failure(self):
        manifest = self.manifest()
        manifest['tokens'].append(manifest['tokens'][0])
        self.save_manifest(manifest)
        target = self.root / 'token.000'
        target.write_bytes(b'keep me')
        with self.assertRaisesRegex(t.FormatError, 'unique'):
            t.build_db(self.export, target)
        self.assertEqual(target.read_bytes(), b'keep me')
        manifest['tokens'].pop()
        manifest['tokens'][0]['monikers'][0]['png'] = '../outside.png'
        self.save_manifest(manifest)
        with self.assertRaisesRegex(t.FormatError, 'escapes'):
            t.build_db(self.export, target)
        self.assertEqual(target.read_bytes(), b'keep me')

    def test_corrupt_input_bounds(self):
        data = FIXTURE.read_bytes()
        for damaged in (b'bad', data[:280], data[:1000]):
            with self.subTest(length=len(damaged)), self.assertRaises(t.FormatError):
                t.Database(damaged)
        with self.assertRaises(t.FormatError):
            t.unpackbits(b'\xff\0', 1)
        # GEOS-specific 0x80 behavior, verified in UncompactPackBits.
        self.assertEqual(t.unpackbits(b'\x80\xaa', 129), b'\xaa' * 129)

    def test_monochrome_fill_and_draw(self):
        bitmap = t.pack(2, 1) + b'\0\0\x80'
        base = b'\x41' + t.pack(2, 1)
        fill = t.render_moniker(base + b'\x79\x04\x4d' + t.pack(len(bitmap)) + bitmap + b'\0')
        draw = t.render_moniker(base + b'\x79\x04\x51' + t.pack(len(bitmap)) + bitmap + b'\0')
        self.assertEqual(list(struct.iter_unpack('4B', fill.tobytes())), [(170, 0, 0, 255), (0, 0, 0, 0)])
        self.assertEqual(list(struct.iter_unpack('4B', draw.tobytes())), [(0, 0, 0, 255), (255, 255, 255, 255)])

    def test_complex_palette_and_truecolor(self):
        # Same CBitmap layout emitted by cvtpcx -p, including palette word count.
        bitmap = t.pack(3, 1) + bytes((0, 0x59))
        bitmap += t.pack(0, 1, 0, 28, 20, 72, 72)
        bitmap += t.pack(2) + bytes((17, 33, 55, 77, 99, 111)) + bytes((0xa0, 0x01, 0x00))
        image = t.bitmap_image(bitmap)
        self.assertEqual(list(struct.iter_unpack('4B', image.tobytes())), [(17, 33, 55, 255), (77, 99, 111, 0), (17, 33, 55, 255)])
        source = Image.new('RGBA', (3, 2), (17, 59, 171, 255))
        self.assertEqual(t.render_moniker(t.encode_moniker(source, 0x13c8)).tobytes(), source.tobytes())

    def test_empty_database(self):
        manifest = self.manifest()
        manifest['tokens'] = []
        self.save_manifest(manifest)
        self.assertEqual(list(self.rebuild().tokens()), [])

    def test_bitmap_positioning_and_rejection(self):
        bitmap = t.pack(1, 1) + b'\0\x03\x11\x22\x33'
        raw = b'\x48' + t.pack(3, 3)
        raw += b'\x63' + t.pack(1, 1)  # MoveTo
        raw += b'\x64' + struct.pack('<ii', 65536, 0)  # RelMoveTo
        raw += b'\x51' + t.pack(len(bitmap)) + bitmap + b'\0'
        image = t.render_moniker(raw)
        self.assertEqual(image.getpixel((2, 1)), (17, 34, 51, 255))
        self.assertEqual(image.getpixel((0, 0))[3], 0)
        with self.assertRaisesRegex(t.FormatError, 'bits set'):
            t.encode_moniker(image, 0x80)  # text type cannot describe a PNG

    @unittest.skipUnless(os.environ.get('CVTPCX'), 'set CVTPCX to cross-check the branch tool')
    def test_cvtpcx_pixels_and_palette(self):
        # Exercise actual cvtpcx-generated bitmaps, independently of our encoder.
        for depth, fmt, typ in ((4, 1, 0x11), (8, 2, 0x1a)):
            with self.subTest(depth=depth):
                source = Image.new('RGBA', (7, 3))
                colors = [(0, 0, 170, 255), (255, 0, 0, 255), (0, 0, 0, 0)]
                source.putdata([colors[i % 3] for i in range(21)])
                path = self.root / 'input.png'
                source.save(path)
                output = self.root / 'output.goh'
                subprocess.run([os.environ['CVTPCX'], '-G', '-2', '-g', '-u', '-nTest',
                                '-w7', '-h3', f'-c{depth}', f'-o{output}', str(path)],
                               check=True, capture_output=True)
                text = output.read_text()
                # The macro expands to the six-byte simple bitmap header.
                # For 8-bit output the following literal bytes hold CBitmap.
                numeric = bytes(int(v, 16) for v in re.findall(r'0x([0-9a-fA-F]{2})', text))
                if depth == 8:
                    # CBitmap fields are printed as decimal byte pairs.
                    tail = text.split(')),', 1)[1].split('\n', 1)[0]
                    header_tail = bytes(int(v) for v in re.findall(r'\b\d+\b', tail))
                else:
                    header_tail = b''
                bitmap = t.pack(7, 3) + bytes((0, typ)) + header_tail + numeric
                decoded = t.bitmap_image(bitmap)
                native = t.render_moniker(t.encode_moniker(source, 0x13c6 if fmt == 1 else 0x13c7))
                self.assertEqual(decoded.tobytes(), native.tobytes())
                palette_source = (ROOT / 'Tools/misc/cvtpcx/cvtpcx.c').read_text()
                palette_text = palette_source.split('static const byte GeosColorTable[] = {', 1)[1].split('};', 1)[0]
                palette_text = re.sub(r'/\*.*?\*/', '', palette_text, flags=re.S)
                self.assertEqual(t.PALETTE, bytes(int(n, 16) for n in re.findall(r'0x[0-9a-fA-F]+', palette_text)))


if __name__ == '__main__':
    unittest.main()
