Add a new tool under `Tools/` that can unpack GEOS BSWF bitmap fonts into an editable folder and pack the folder back into a patched font.

Implement `fntpatch unpack <font.fnt> <fontdir>`:

1. Parse the BSWF header and point-size table using `Tools/geodump/nimbus.h` (`BSWFheader`, `my_PointSizeEntry`). Copy nimbus.h into the project and make a comment that it was lovingly stolen from geodump.

2. Copy the original input font into `<fontdir>/original.fnt`.

3. Write `<fontdir>/font.meta` with ASCII key/value fields: tool format version, source filename, font name, font file size, checksum, header values, and point-size entry count.

4. For each point-size entry, create a strike folder under `<fontdir>/strikes/`, using a stable name that includes entry index, style, and point size.

5. Read each strike as a `FontBuf` block. Use `Include/Internal/fontDr.def` as the layout reference for `FontBuf`, `CharTableEntry`, and `CharData`.

6. Write a strike metadata file containing the point-size entry index, style, point size, file offset, data size, `FB_firstChar`, `FB_lastChar`, and other relevant `FontBuf` metrics.

7. For each existing bitmap glyph, export one PBM file and record metadata: char code, `CharTableEntry` offset, `CTE_dataOffset`, `CTE_width`, `CTE_flags`, `CD_pictureWidth`, `CD_numRows`, `CD_xoff`, `CD_yoff`, row byte count, payload byte count, and absolute file offset of `CD_data`.

8. Skip or mark glyphs that are missing, have `CTF_NO_DATA`, use sentinel offsets such as `CHAR_NOT_EXIST` or `CHAR_NOT_BUILT`, or cannot be interpreted as bitmap `CharData`.



Implement `geosfnt pack <fontdir> <out.fnt>` as a conservative patcher:

1. Load `<fontdir>/original.fnt` and validate it against `font.meta` checksum and size.

2. For each glyph metadata entry with a PBM file, read the PBM and validate that its width and height match `CD_pictureWidth` and `CD_numRows`.

3. Repack PBM pixels to the original GEOS bitmap byte layout.

4. Validate that the packed byte count equals the recorded payload byte count.

5. Overwrite only the recorded `CD_data` byte range in memory.

6. Do not modify BSWF headers, point-size entries, `FontBuf` headers, `CharTableEntry` fields, `CharData` headers, offsets, sizes, or file length.

7. Write `<out.fnt>` only after all glyphs validate successfully.

8. Print a concise summary of changed glyphs.

Keep metadata ASCII-only and deterministic so unpacked font directories can be reviewed in version control.