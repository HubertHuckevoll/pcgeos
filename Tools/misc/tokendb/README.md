# PC/GEOS token database ↔ PNG (Perl)

`tokendb.pl` exports a GEOS 2.x Token Database (`token.000`) as editable
PNGs and a JSON manifest, and builds a new database from that directory.
It runs on the host without a GEOS runtime or a GEOS build.

Implemented with ChatGPT Codex, prompted by MeyerK.

## Usage

Requires Perl 5.14+ with `JSON::PP`, `MIME::Base64`, `Digest::SHA`,
`File::Temp` and `Compress::Zlib`. The first four ship with Perl;
`Compress::Zlib` may need to be installed separately on your host.
There is no Python dependency.

```sh
perl Tools/misc/tokendb/tokendb.pl export /path/to/token.000 /path/to/icons
# Edit the PNG files, keeping manifest.json and the .bin files.
perl Tools/misc/tokendb/tokendb.pl build /path/to/icons /path/to/new-token.000 \
    --cvtpcx /path/to/cvtpcx
```

The PNG-capable **cvtpcx from the `cvtpcx2` branch** is needed to import
new/changed PNGs. It can also be selected through the `CVTPCX` environment
variable. Otherwise the script checks the repository's installed Linux/Windows
tool locations and `PATH`. Export and an unchanged roundtrip need no converter.

The export directory must not already exist. Build writes a temporary file and
renames it into place only after successful validation. Use a new output
filename when experimenting; on hosts where `rename` cannot replace an existing
file, choose a different target. Close GEOS before replacing its database, and
keep a backup of the original.

Example output:

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

Each token has a four-byte ID and manufacturer ID. The filename suffix is the
complete 16-bit moniker-list entry type (size, style, aspect ratio, display
class, and graphics/list flags). Different icon variants remain separate files.
The directory prefix preserves token order.

The manifest records those IDs, flags, release/protocol words, file paths and
hashes. Each `.bin` holds the entire original VisMoniker, including its GString
or text bytes. **Keep these files**: unchanged PNGs reuse the original bytes,
retaining compression, drawing operations and palettes. Text monikers and
unsupported graphics also survive unchanged. `text_hex` is informational;
the corresponding `.bin` remains authoritative.

A PNG and its raw moniker are reused together only if both still match their
exported file hashes. Otherwise the PNG is converted through cvtpcx; if the
rendered pixels still match the original moniker, the original is retained.
The previous manifest layout without file hashes is also accepted through this
conversion path. Deleting a hash does not delete a moniker.

The VM blocks, physical handles and free space are rebuilt. Thus a no-edit
roundtrip is **semantically lossless**, rather than a byte-identical copy of the
whole file: all TokenEntry metadata and original moniker bytes remain identical.
Unreferenced/deleted items and old allocation history are discarded. The
256-byte GEOS header and dummy first token-map entry are preserved.

## Editing and adding icons

Edit an existing PNG in place and run `build`. Its dimensions become the new
cached moniker dimensions. Only PNGs referenced by the manifest are imported.

For example, append this token to the manifest's `tokens` array:

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

This uses token `TEST` and type `0x13c6` (decimal 5062): a standard-size,
normal-aspect, 16-color graphic icon. Use your own manufacturer ID. New PNG-only
entries need no `.bin`; copy a suitable type from an existing variant.
Token/manufacturer pairs must be unique and each token needs at least one
moniker. Remove or reorder entries to remove or reorder tokens. An entirely
empty database is also supported.

New/changed PNGs are passed to cvtpcx with `-G -2 -g -u`, their actual width and
height, and a depth selected from the manifest's display class:

- Monochrome: `-b` (black pixels become set bits).
- Display classes through 4-bit: `-c4` (nearest GEOS system color).
- Higher display classes: `-c8` (indexed PNGs retain palette/indices; RGB PNGs
  are mapped to the GEOS 256-color palette).

Alpha below 128 is transparent. Converted bitmaps are uncompressed; cvtpcx
supports indexed, RGB, alpha, 16-bit and interlaced PNG input. See its own PNG
limits and mapping rules in `Tools/misc/cvtpcx/cvtpcx.c`.

Unchanged custom-palette and RGB24 monikers retain their original raw bytes.
Changed 4-bit PNGs use the system palette. New/changed high-color variants use
cvtpcx's 8-bit output, with possible color reduction; this tool does not add a
24-bit encoder to cvtpcx. No dithering or automatic generation of other variants
is performed.

Perl handles VM/DB/LMem structures, GString decoding and PNG export. PNG export
uses `Compress::Zlib` to write RGBA scanlines directly. For import, the script
parses cvtpcx's narrowly defined bitmap initializer into bytes; it never evaluates
the generated GOC source, invokes a compiler, or passes filenames through a shell.

## Supported export graphics

- Simple and full-height complex bitmaps: mono, packed 4-bit, 8-bit and RGB24.
- Uncompressed and GEOS PackBits data, binary masks and custom palettes.
- GStrings containing DrawBitmap/FillBitmap at coordinates or current position;
  integer MoveTo/RelMoveTo, area RGB/index color, copy mix mode, NullOp and EndGString.
- FillBitmap's zero bits are transparent; DrawBitmap's mono zero bits are white.

Unknown GString operations (including vector drawing), fractional positioning,
huge/sliced bitmaps, CMYK and LZG compression are reported and preserved as raw
`.bin` files. They receive no misleading partial PNG. Supported icons are
rendered from current position `(0,0)` with black area color onto a transparent
canvas; arbitrary GStrings can depend on other external GState settings.
No font/text rendering is attempted. The file must use the GEOS 2.x GEAS
signature. GEOS 1.x and interpretation of DBCS text are outside the PNG codec.

The builder limits each DB item to 65,000 bytes and keeps ordinary item blocks
around 8 KiB, allowing larger individual items. The token-map item must fit in
one DB item. Reads check lengths, handles and manifest paths. These checks are
not a general hostile-file sandbox.

## Format references

- `Include/token.def`: 24-byte TokenEntry, TokenDBItem, MonikerGroupEntry.
- `Library/User/Token/token.asm`: InitializeLocalTokenDB, AddMonikers, GetGroup.
- `Tools/utils/vmInt.h`: VMFileHeader2, VMHeader, 12-byte VM block descriptors.
- `Include/Internal/dbaseInt.def`: DBMapBlock, DBGroupHeader, DBItemInfo,
  DBItemBlockInfo and DBItemBlockHeader.
- `Include/lmem.def`, `Library/Kernel/LMem/lmemErrorCheck.asm`: chunk heaps.
- `Include/Objects/visC.def`: VisMoniker and 6-byte VisMonikerListEntry.
- `Include/graphics.def`, `CInclude/graphics.h`, `Include/gstring.def`:
  bitmap headers, display formats and GString opcodes.
- `Library/Kernel/Graphics/graphicsRasterDraw.asm`: GEOS PackBits decoding
  (`0x80` repeats 129 bytes, unlike the Macintosh no-op).
- `Tools/misc/cvtpcx/cvtpcx.c`: system palette, binary bitmap layout, PNG mapping.

Words are little-endian. VM handles are byte offsets into the VM header;
block file positions are relative to byte 256. The VM map holds the
moniker-type → current DB-group index. A separate DB map points to the token
array, whose first record is a dummy. Each token points to a list of
`(type, group, item)` records. A DB item is an offset into its group, containing
an item-block info offset and an LMem chunk handle. Dereferencing that handle
locates the moniker bytes.

## Tests

```sh
perl Tools/misc/tokendb/Tests/token.pl
CVTPCX=/path/to/cvtpcx perl Tools/misc/tokendb/Tests/token.pl
```

Tests cover both repository fixtures (90 tokens / 395 graphics / 77 text
monikers, and 29 tokens / 87 graphics), comparing all metadata and original
moniker bytes after rebuilding. Independent physical VM/LMem heap checks catch
invalid allocation layouts. Other checks cover PNG chunks/CRC/rows, mono masks,
complex palettes, RGB24, positioning, unknown GStrings, invalid files, path
traversal, atomic failure and empty databases. With `CVTPCX`, they also cover
edited PNGs, new tokens, deletion/reordering, spaces in paths and masked
mono/4-bit/8-bit import.

**A runtime smoke test in GEOS is still needed before treating the generated
file as a production replacement.** Host tests do not run its VM/DB loader or
prove subsequent GEOS writes safe.
