# PC/GEOS token database ↔ PNG

`tokendb.py` extracts a GEOS 2.x Token Database (`token.000`) into editable
PNGs plus a JSON manifest, and builds a new database from that directory.
It runs on the host; neither a GEOS build nor a GEOS runtime is required.

Implemented with ChatGPT Codex, prompted by MeyerK.

## Usage

Requires Python 3.10+ and Pillow:

```sh
python3 -m pip install Pillow
python3 Tools/misc/tokendb/tokendb.py export /path/to/token.000 /path/to/icons
# Edit the PNG files, keeping manifest.json and the .bin files.
python3 Tools/misc/tokendb/tokendb.py build /path/to/icons /path/to/new-token.000
```

The export directory must not already exist. Build writes its output atomically;
use a separate output filename when experimenting. To install the result, close
GEOS before replacing its database, and keep a backup of the original.

Example directory:

```text
icons/
  manifest.json
  0000_DESK_0000/
    00_23c6.png
    00_23c6.bin
    01_23c1.png
    01_23c1.bin
  ...
```

The directory prefix preserves token order. Each token has a four-byte ID and a
manufacturer ID; the filename suffix is the full 16-bit moniker-list entry type
(size, style, aspect ratio, display class, and graphics/list flags). Icons with
different size, aspect ratio or color depth remain separate files.

The manifest records these IDs, token flags, release/protocol words, paths and
pixel hashes. A `.bin` file holds the complete original VisMoniker, including
its GString or text bytes. **Keep these files**: unchanged PNGs reuse the original
moniker bytes, preserving compression, drawing operations and palettes. Text
monikers and unsupported graphics also survive unchanged. `text_hex` and
`pixel_sha256` are informational; the importer compares PNG pixels with a fresh
render of the `.bin` file rather than trusting the saved hash.

The VM blocks, handles and free space are rebuilt, so a no-edit roundtrip is
**semantically lossless**, not a byte-identical copy of the entire database.
All TokenEntry metadata and all original moniker bytes remain identical.
Unreferenced/deleted items and original VM allocation history are discarded.
The 256-byte GEOS file header and dummy first token-map entry are retained.

## Editing and adding icons

Edit an existing PNG in place and run `build`. PNG dimensions become the new
cached moniker dimensions. Only PNGs referenced by the manifest are imported.

A new token can be appended to the manifest's `tokens` array, for example:

```json
{
  "token_hex": "54455354",
  "manufacturer": 16431,
  "flags": 0,
  "release": [0, 0, 0, 0],
  "protocol": [0, 0],
  "monikers": [
    {"type": 5062, "png": "my-icon.png"}
  ]
}
```

This example uses token `TEST` and type `0x13c6` (decimal 5062), a standard-size,
normal-aspect, 16-color graphic icon. Use your own manufacturer ID. New PNG-only
entries need no `.bin`; copy the appropriate type from an existing variant.
Token/manufacturer pairs must be unique. Remove or reorder entries to remove or
reorder tokens; moniker order is likewise preserved.

Changed/new images use uncompressed GEOS bitmaps, with binary alpha (below 128
is transparent), retaining the display class from the manifest:

- Monochrome: black/white at a weighted luminance threshold of 128.
- Up to 4-bit: nearest of the 16 GEOS system colors.
- 8-bit: nearest of the 256 GEOS system colors.
- RGB: 24-bit RGB triples.

Color matching uses the same palette and Manhattan RGB distance as `cvtpcx`.
Arbitrary custom palette colors in an edited 4/8-bit PNG are reduced to the
system palette; unchanged custom-palette monikers retain their original bytes.
No dithering or automatic generation of other variants is performed.

The tool implements the binary codec directly: `cvtpcx` produces compiler source,
not complete binary VM/DB files, and does not decode existing monikers to PNG.
The tests cross-check this branch's PNG-capable `cvtpcx` as an independent encoder.

## Supported export graphics

- Simple and full-height complex bitmaps: mono, packed 4-bit, 8-bit, RGB24.
- Uncompressed and GEOS PackBits data, binary masks, custom palettes.
- GStrings containing DrawBitmap/FillBitmap, at coordinates or current position;
  integer MoveTo/RelMoveTo, area RGB/index color, copy mix mode, NullOp, EndGString.
- FillBitmap's zero bits are transparent; DrawBitmap's mono zero bits are white.

Unknown GString operations (including vector drawing), fractional positioning,
huge/sliced bitmaps, CMYK and LZG compression are reported and retained as raw
`.bin` files. They receive no misleading partial PNG. Arbitrary GStrings may
depend on external GState settings; supported icons are rendered at initial
current position `(0,0)` with black area color onto a transparent canvas.
No GEOS font/text rendering is attempted. The file must use the GEOS 2.x GEAS
signature; GEOS 1.x and DBCS text interpretation are outside the PNG codec.

The encoder limits each bitmap to 64,000 uncompressed raster bytes and each
DB item/VM block to 16-bit size limits. Ordinary item blocks are grouped around
8 KiB, with larger individual items allowed. The token-map item itself must fit
in a single DB item. Input parsing checks bounds, handles, lengths and manifest
paths. These checks do not constitute a general-purpose hostile-file sandbox.

## Format references in this repository

- `Include/token.def`: TokenEntry (24 bytes), TokenDBItem, MonikerGroupEntry.
- `Library/User/Token/token.asm`: InitializeLocalTokenDB, AddMonikers, GetGroup.
- `Tools/utils/vmInt.h`: VMFileHeader2, VMHeader, 12-byte VM block descriptors.
- `Include/Internal/dbaseInt.def`: DBMapBlock, DBGroupHeader, DBItemInfo,
  DBItemBlockInfo, DBItemBlockHeader.
- `Include/lmem.def` and `Library/Kernel/LMem/lmemErrorCheck.asm`: chunk heaps.
- `Include/Objects/visC.def`: VisMoniker and 6-byte VisMonikerListEntry.
- `Include/graphics.def`, `CInclude/graphics.h`, `Include/gstring.def`: bitmap
  headers, display formats and GString opcodes.
- `Library/Kernel/Graphics/graphicsRasterDraw.asm`: GEOS PackBits decoding
  (notably `0x80` means a 129-byte repeat, not a Macintosh no-op).
- `Tools/misc/cvtpcx/cvtpcx.c`: system palette, bitmap headers and PNG mapping.

All words are little-endian. VM block handles are byte offsets into the VM
header. Block file positions are relative to byte 256. The VM map holds the
moniker-type → current DB-group index; the separate DB map points to the token
array. Its first record is a dummy. A token points to a list of `(type, group,
item)` records. A DB item is an offset into its group containing an item-block
info offset and LMem chunk handle; dereferencing that handle locates the moniker.

## Verification

```sh
python3 -m unittest discover -s Tools/misc/tokendb -v
CVTPCX=/path/to/cvtpcx python3 -m unittest discover -s Tools/misc/tokendb -v
```

The two real repository fixtures contain 90 tokens / 395 graphics / 77 text
monikers, and 29 tokens / 87 graphics. Tests compare all metadata and moniker
bytes after rebuilding, check edited and new PNGs, deletion/reordering, empty
databases, unknown GStrings, malformed input, atomic failure, mask/mono semantics,
complex palettes, RGB24, and independent physical VM/LMem heap invariants.
The optional cvtpcx check exercises actual generated 4/8-bit bitmap data.

**A runtime smoke test in GEOS remains necessary before using the generated
database as a production replacement.** Host-side tests do not execute the
GEOS VM/DB loader or prove that subsequent GEOS writes are safe.
