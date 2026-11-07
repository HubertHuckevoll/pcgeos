<!--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Printer
FILE:       README.md

AUTHOR:     Codex/MeyerK, Nov 2026

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Document the streaming PDF driver architecture, ABI and tests.
    Record known limitations and integration decisions.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-->

# Native PDF printer, milestone 1 (issue #1160)

This is a separate `pdf.drvr` printer and `pdf.lib` translation backend. It
writes PDF 1.1 directly from GEOS GStrings through the spooler's existing file
stream. It does not invoke EPS, PostScript, ps2pdf, Ghostscript or host services.
The existing PostScript driver, EPS exporter and spooler are unchanged.

## Interface audit and architecture

The implementation follows these existing contracts:

* `Library/Spool/Process/processPDL.asm:PrintPDLPage` calls StartPage, supplies
  the orientation/tiling matrix via `DR_PRINT_ESC_SET_PAGE_TRANSFORM`, loads a
  `GST_STREAM` GString and calls `DR_PRINT_ESC_PRINT_GSTRING`, then EndPage.
  The normal fault path disposes of the loaded GString and reports conversion
  failure. Therefore PrintGString returns `GSRT_FAULT` with carry clear on
  translation failure; stream/page/job functions return carry set on error.
* `Driver/Printer/PScript/pscriptPDL.asm` and `pscriptPage.asm` establish the
  register ABI. Regular calls receive a locked PState segment in BP; escapes
  receive the PState handle in BX. The new driver uses the shared PrintCom
  entry/info tables, not a new spooler path.
* `Library/Trans/Graphics/Vector/EPS/Export/exportGString.asm` establishes the
  playback approach: the kernel maintains GState attributes and transforms;
  the translator emits output elements. The PDF adapter uses
  `GrGetGStringElement` and one-element kernel playback, checking errors rather
  than copying EPS's historical fault-to-complete conversion.
* `Library/Kernel/Graphics/graphicsString.asm` shows why extracting an element
  before `GrDrawGStringAtCP(GSC_ONE)` matters: extraction makes that element
  ready; playback executes it, then stops before the next element. A COMPLETE
  result after the final output element is legitimate and must stop translation
  immediately: kernel cleanup restores the transform and rewinds the source.
  A priming GSC_ONE call before extraction initializes playback at the origin
  without executing an element. A zero-size read is a fault. A new-page marker
  is consumed; a manually inspected end-of-string marker is retained.
* `Include/gstring.def` and `Include/text.def` define the on-disk wire layout.
  Text fields contain a **14-byte** GDF_saved followed by counted TFStyleRuns;
  native `TextAttr` is 24 bytes, including word-alignment padding, while the
  packed C declaration is 23 bytes. Each native TFStyleRun is therefore 26
  bytes before its characters. CInclude's OpDrawLine member names
  interchange x2/y1, so scalar operands are explicitly decoded little endian.
* The kernel C entry `GRGETTEXTPATTERN` returns packed PatternInfo in AX.
  The adapter declares that entry with a word result because Watcom's Pascal
  structure-return convention would treat AX as a pointer. Only the low byte
  selects the pattern type; PT_SOLID ignores the data byte. Custom-pattern
  snapshot handles are freed after inspection.
* `Driver/Printer/PrintCom/Stream/streamWrite.asm` defines `DR_STREAM_WRITE`:
  token in BX, blocking mode in AX, DS:SI buffer, CX byte count. The adapter
  checks both carry and short writes. The stream remains owned by the spooler.
* Installed Makefiles use the regular Watcom/ESP/Glue geode rules. The product
  filetree installs the backend in SYSTEM and the driver in SYSTEM/PRINTER.
  Their filenames are both pdf.geo, but their permanent names and directories
  differ. New exports have a dedicated protocol; existing exports/resources
  are untouched.

Ownership is explicit: PS_expansionInfo contains one backend memory handle.
StartJob allocates it; every backend call locks/unlocks it; EndJob frees it,
including after an error. No job state is held in shared globals. One temporary
heap block holds the current output element and is freed immediately after use.
Path painting additionally owns one native snapshot and one snapshot element;
only one snapshot is live at a time. An unfinished native path definition is
closed before destroying the playback state, including on conversion failure.
The assembly-to-C boundary uses Pascal stack arguments and preserves BX across
C calls before unlocking the PState.

## Modules

| File | Responsibility |
| --- | --- |
| `Driver/Printer/PDF/pdfManager.asm` | PrintCom strategy and dispatch |
| `Driver/Printer/PDF/pdfJob.asm` | Job/page lifetime and stream handoff |
| `Driver/Printer/PDF/pdfPDL.asm` | Page matrix and GString escapes |
| `Driver/Printer/PDF/pdfInfo.asm` | Margins, paper path, UI evaluation |
| `Driver/Printer/PDF/pdfDriverInfo.asm` | One file-only PDL device |
| `pdfGeos.c` | GEOS memory, graphics state, GString decoding/translation |
| `pdfStream.asm` | Stream strategy, fractional text-width and native dash adapters |
| `pdfWriter.c` | Portable PDF object and operator serialization |
| `pdfShape.c` | Independent vector primitives: ellipses and rounded rectangles |
| `pdfBitmap.c` / `pdfBitmap.h` | GEOS storage validation, DPI and source-row iterator |
| `pdfImage.c` / `pdfImage.h` | Canonical rows to PDF 1.1 ASCIIHex inline images |
| `Include/pdf.def` | Private printer/backend API and lifetime contract |

The writer buffers 512 bytes and tracks its own 32-bit byte position. Each page
is a content stream, an indirect length object and a page dictionary. Content
is written immediately, without seeking or retaining a complete page. The page
tree and classic xref table are written at EndJob. IDs are assigned
arithmetically, avoiding a separate page-reference allocation. The context is
under 4 KiB on GEOS; the offset table accounts for approximately 3 KiB of that.
It currently supports at most 256 physical pages and one output element of at
most 32,760 bytes. Limits produce errors instead of overflowing 16-bit blocks.

## Supported first milestone

* Multipage PDF 1.1, A4/Letter/custom media, normal spooler file output.
* Spooler orientation and tiling matrix; kernel-maintained per-object affine
  transforms; physical media clipping.
* Lines, line-to, horizontal/vertical lines, rectangles, filled rectangles,
  polylines, polygons (both fill rules), cubic Bezier curves, outlined/filled
  ellipses and rounded rectangles (including current-position variants).
  Points use area attributes and one physical 300 dpi pixel, independent of
  page/GString scaling. Brush polylines preserve the native rectangular nib,
  pixel DDA, line color/mask and packed byte dimensions; dashes, line width,
  caps and joins do not change that nib.
  Bounded elliptical arcs support open, chord and pie closure; filled arcs
  require chord/pie. GEOS radial angles, wraparound and native pen updates
  are preserved. Absolute, current-position and relative three-point circular
  arcs also support open/chord/pie geometry, with fractional source points and
  collinear fallback.
* RGB fill/stroke/text colors; solid masks, line width/caps/joins/miter limit.
  Built-in and custom dash arrays use native byte factors, phase and current
  line width, including save/restore. Hairline dash spacing uses the same
  1/16-point fallback as SvgLib; device-exact hairline spacing remains open.
* DrawText/DrawTextAtCP, DrawChar/DrawCharAtCP, plain counted text-field runs.
* Standard Helvetica, Times and Courier faces selected by GEOS font family,
  with bold/italic variants, plus Symbol and ZapfDingbats resources. Common
  mathematical GEOS characters use the existing EPS Symbol mappings rather
  than undefined PDF MacRoman codes. Unsupported characters fail explicitly.
  No embedded fonts are required.
* Text positions and run advances retain native 1/256-point fractions. Native
  single/pair width queries preserve pair/track kerning and space padding in
  linear work. Current-position text also retains the fractional pen position.
  Underline and strike-through use native font positions and thickness,
  preserve fractional coordinates and follow the text color/mask. Text-field
  decoration limits do not shorten run advances.
  Optional hyphens follow the native mode and counted-run boundary;
  nonbreaking hyphens retain native advances. Automatic field hyphens use
  the final run's attributes. Unused saved-field flag bits are ignored.
* Independent native line/area/text masks and paint-time text-pattern checking,
  including patterns supplied through text-field and standalone TextAttr.
* Balanced save/restore scopes (up to 31 nested saves). Retained native paths
  support lines, polygons, curves, points, all arc forms, ellipses and rounded rectangles, with fill,
  stroke, holes, transforms and balanced saved states inside path definitions.
  Captured attributes are replayed by the kernel; painting uses the final
  caller attributes. Relative lines/curves and splines also have
  native output handlers. Text, characters and text fields in painted or
  clipped paths use DR_FONT_GEN_PATH outlines from the selected GEOS font,
  with fractional placement and the same native width/kerning queries as
  ordinary text. Glyph counters remain path holes. One glyph is recorded
  and released at a time; the command buffer is 32 bytes. Bitmap-only fonts
  and unexpected larger glyph commands still fail explicitly, with
  PDF_TEXT_PATH_REQUIRED diagnostics.
* Application and window path/rectangle clipping supports intersection,
  replacement and null clips, including replacement inside saved scopes.
  Clips are rebuilt at painting from the current native state, so there is
  no second persistent PDF clip stack. Captured coordinates are transformed
  with native GEOS APIs before serialization: fills/clips use physical page
  coordinates, and strokes use the final painting state's coordinates. This
  preserves rotated/scaled page clips and affine stroke widths without
  changing the PDF CTM during path construction. Boolean union sections still fail
  explicitly; their native region conversion remains work to complete.
* Mono, indexed 4-/8-bit and RGB24 bitmaps, uncompacted or using native
  PackBits/LZG compression: simple headers and complex sliced headers,
  explicit DPI, DrawBitmap/DrawBitmapAtCP; FillBitmap/FillBitmapAtCP for mono.
  Empty introductory headers emitted by HugeBitmapToString are supported.
  Indexed images support default GEOS colors and explicit RGB palettes,
  including palette-only introductory slices and identical repeated palettes.
  Stored masks are supported for all these formats and codecs. Pixel rows
  remain packed; PDF indexed color spaces avoid a full RGB expansion buffer.

This is a **restricted SBCS vector/text milestone**, not general document
fidelity yet. Boolean path unions, patterned fills,
non-copy mixing, embedded graphics in text fields, super/subscript and DBCS
remain future work.
Font shape fidelity beyond the standard-family substitution, full character
coverage and application-level justified text verification need further work. Failed jobs may leave incomplete output; the spooler owns destination
cleanup. The backend does not publish a success trailer after a latched error. The
spooler records and reports EndJob failure even after the last page succeeds,
while preserving prior cancellation or an already reported error.

## Bitmap boundary and extension points

The bitmap pipeline separates **source storage**, **canonical rows**, and
**PDF encoding**. No GEOS bitmap flag is used as a PDF image-format constant.

| Layer | Current contract | Extension point |
| --- | --- | --- |
| `PdfBitmapParse` | Validate the 6-byte Bitmap or 20-byte CBitmap, dimensions, row count, data offset and DPI | Recognize additional storage headers/flags without changing PDF objects |
| `PdfBitmapReaderOpen` / `PdfBitmapNextRow` / `PdfBitmapNextChunk` | Borrow raw rows or decode compressed chunks from one source slice | Additional source codecs belong here |
| `PdfImageBegin` / `PdfImageRow` / `PdfImageEnd` | Canonical stencil1, RGB24 and packed indexed rows; exact byte/row counts; ASCIIHex inline image | Additional encodings remain independent of GEOS storage |

GEOS monochrome drawing is **not** an opaque black/white image: zero bits leave
existing content alone. DrawBitmap paints set bits black, whereas FillBitmap
paints them with the current area color (`graphicsRaster.asm` and the video
driver's PutBWScan/FillBWScan). The writer therefore uses an inline image mask
with `/IM true /D [1 0]`. A stored `BMT_MASK` prefixes each canonical row
with ceil(width/8) coverage bytes; a clear bit leaves the destination unchanged.
Mono pixels still act as a stencil inside this coverage. Masked output uses
small clipped inline-image tiles, keeping PDF 1.1 compatibility. Each tile holds
at most 128 color bytes (126 for RGB), with at most 1024 mask-run rectangles.
Empty coverage emits an empty clip. No background color is guessed.

`pdfGeos.c` owns playback, per-object transform, clipping, area/mix checks,
placement and the lifetime of each source slice. It explicitly consumes bitmap
records and continuation slices with GrSetGStringPos: ordinary kernel playback
would invoke callbacks and consume all the slices itself. For explicit-position
records GrMoveTo preserves the kernel's starting-pen semantics; CP variants retain
the existing pen. Other elements still use kernel playback. The test double now
models priming and COMPLETE's source rewind, so an accidental re-execution at
the end of a page cannot be hidden by a non-rewinding mock.

For each complex image, startScan/numScans must form a contiguous sequence from
row zero through image height. Dimensions, canonical format and DPI must remain
consistent. The first slice may contain only a header (zero rows); continuation
slices must make progress. Missing, overlapping, reordered, mismatched and orphan
slices fault. The GString slice-size word and the exact row-data length are
checked before use. Currently slices share the existing 32,760-byte element
limit; an entire image may exceed 64 KiB. Only one source slice is copied/locked
at a time, plus a 65-byte hex conversion buffer. Indexed/masked input uses one
owned block for its palette and one packed mask row: at most 8240 bytes combined,
including at most 8192 mask bytes. Compressed input uses a separate 128-byte
PackBits workspace or a 1152-byte LZG history/chunk workspace. Decoded chunks
are at most 128 bytes and never cross a row. There is no full-image or
full color-scanline allocation. Masked indexed images retain the palette until
image end; opaque images need it only during image begin. ASCIIHex output
approximately doubles data size. Repeating inline headers and indexed palettes
for masked tiles adds output overhead.

Physical dimensions are pixels*72/DPI, calculated with checked 32-bit integer
arithmetic. The local image matrix corrects PDF's top-row orientation within
GEOS's downward y axis, while retaining the caller's affine transform. The
classic page resources declare ImageB/ImageC/ImageI. Image lifetime is checked: a page
cannot end inside an image, and partial or extra rows do not produce a successful
trailer. No seek, external converter or new exported library function is needed.

Remaining bitmap work: changing palettes between slices, pointer/optr records
and colored FillBitmap semantics. Unsupported forms
fail explicitly. This boundary allows those converters to be developed with
source-row fixtures independently of the print driver and spooler.

## Hyphen and dash runtime check

Print the PDFPrint sample with the PDF printer. Its added text should read
"Soft: cooperate / end-" and "Nonbreaking: non-breaking". Two lines below
the bitmaps exercise built-in and custom dashes. For automatic hyphens,
print a GeoWrite paragraph with automatic hyphenation enabled and a narrow
text column; check the line ends in the GEOS PDF viewer. Runtime verification
is performed by the user; the automated checks do not start PC/GEOS.

## Point and bounded-arc runtime check

PDFPrint draws an open red elliptical arc and a filled blue pie near the top
right, plus a blue point below them. The point is independent of line width.
Bounded arcs use kernel fixed-point math and quadrant-sized cubic segments;
no floating-point library or new geode dependency is needed. Retained open
arcs keep their subpath start for later LineTo/CloseSubPath operations.
Below the outlined ellipse, PDFPrint draws a blue three-point circular cap
with a red outline. The fit uses bounded 16.16 chord arithmetic; circles or
non-collinear determinants beyond that precision fail with PDF_LIMIT_ERROR.
Kernel null-window playback omits pen setters for three-point To operations;
the adapter preserves the recording branch's pen behavior explicitly. Following
path To operations restart at that native pen if it differs from the curve end.
PDFPrint also draws a continuous red brushed zigzag next to the page title.
Its 8-by-3 pixel nib must stay continuous although the inherited line style is
dotted. Points and brushes use the driver's advertised 300 dpi grid. Their
positions include both the page and GString transforms; their pixel size stays
physical. Captured brush fill/clipping uses the centerline, as in GEOS, while
captured brush strokes retain the rectangular nib.

## Indexed bitmap runtime check

PDFPrint also draws a custom-palette 4-bit image and a default-palette 8-bit
image at the lower right. Check their colors and orientation in the GEOS PDF
viewer. Lookup tables are padded to the full sample range for that viewer;
visible source pixel indices must still fit the actual palette entry count.
PDFPrint also draws a masked PackBits RGB patch over cyan near the lower right:
expect red at the top left, yellow at the bottom right, and cyan elsewhere.

## Compressed bitmap runtime check

Below the indexed images, PDFPrint draws a PackBits mono pattern and an LZG
indexed image. Both stay inside the page clip. Source decompression validates
row sizes and input bounds; LZG additionally checks history distances and end
markers. No full scanline is needed, even for wide images. This changes input
storage support; PDF output still uses the existing ASCIIHex stream.

## Build and verification

With the normal PC/GEOS development environment, build the backend before the
driver (so `pdf.ldf` is available):

```
(cd Installed/Library/Trans/Graphics/Vector/PDF && pmake full)
(cd Installed/Driver/Printer/PDF && pmake full)
```

Alternatively `tests/build-native.sh /absolute/output/directory` builds the
backend, driver and `Appl/SDK_C/PDFPrint` smoke application in NC and EC
variants, without changing source revision files. Set WATCOM, put wcc/esp/glue/
goc on PATH, and set GEOS_LDF_DIR to the SDK's built Installed/Include folder.
The driver protocol is obtained from the print-driver definitions.

Portable regression checks (C and Perl; no Python):

```
Library/Trans/Graphics/Vector/PDF/tests/run.sh
PDF_TEST_CFLAGS='-fsanitize=address,undefined -g' \
    Library/Trans/Graphics/Vector/PDF/tests/run.sh
```

The tests use the production serializer and GEOS adapter. A separate Perl
check executes the small native text-mask and EndJob dispatch branches with
distinct input states; it does not execute the full kernel or spooler.
Ghostscript, when installed, also checks the emitted mathematical Symbol glyph.
The text tests check fractional multi-run layout, incoming pair kerning, track
kerning before the first glyph, hidden-run advances, font-family choice and
late finalization write failure. The kernel double
checks element dispatch, end/new-page handling, packed text-field layout,
rectangular clipping, allocation/write failures and handle cleanup. A separate
Perl checker validates every xref byte offset, indirect stream length and page
reference. Poppler parsing/rendering is checked when installed. These are
host-side development checks, not runtime dependencies.

Bitmap checks cover simple/complex headers, CP/fill variants, empty intro slices,
continuation validation, DPI, malformed payloads, every slice allocation failure,
and streaming an image larger than a 16-bit block. Compression checks cover
GEOS PackBits runs, LZG token forms, overlapping matches, history wrap, row
boundaries, truncation, trailing data and invalid back-references. The rendered
RGB fixture is LZG input; the rendered indexed fixture uses PackBits. Bitmap-only
playback uses two owned heap blocks (job context and
current element) for plain mono/RGB input. Indexed/compressed playback can
add one palette/mask block and one decoder workspace; path/clip playback can instead hold
one native snapshot and one snapshot element. A single additional null-window
GState is allocated lazily for the physical page transform, reused across the
job, and freed during PDFDESTROY, including failed jobs. Image tests inject
write failures and prevent premature page finalization. When Poppler is available,
an independent Perl pixel oracle verifies exact RGB channel/row order, mono
stencil polarity, transparent zero bits and non-byte-aligned widths. The GString
fixture itself also contains mono/RGB images and is parsed/rendered independently.

The shape module provides internal C functions `PdfEllipse`, `PdfRoundRect`, `PdfArc` and `PdfThreePointArc`;
the printer and exported library API are unchanged. GString cases select
stroke/area attributes and pass the bounds to them. Four cubic segments approximate an ellipse
using 16.16 arithmetic and no floating point, allocations or local CTM scaling.
Inherited stroke width is therefore preserved for noncircular ellipses. Reversed
corners are normalized as in the kernel; zero-area fills vanish and degenerate
outlines collapse to a line/point. This continuous PDF treatment does not promise
pixel-identical GEOS raster results for degenerate or very small ellipses.
Independent host tests sample the emitted curves against the ellipse equation
(normalized radial error below 0.0004), including odd dimensions, 1-point bounds,
the full signed-word range and extreme aspect ratios. Tests also cover inherited
area masks, malformed GString operands, sink failures, and transformed rendering.

Rounded rectangles reuse the same quarter-circle control factor for four cubic
corners joined by straight edges. Their unsigned word radius is limited to the
smaller **integer** half-extent, rounded down, matching `PrepRoundRectLow` in
`Library/Kernel/Graphics/graphicsRoundedRect.asm`. A zero/clamped-zero radius
emits an ordinary rectangle, including degenerate bounds. Coordinates are
normalized before radius calculation and promoted before arithmetic, supporting
the complete signed-word coordinate range without 16-bit subtraction overflow.
The four records are decoded explicitly from `Include/gstring.def`: a word
radius precedes either four signed coordinate words (11 bytes total) or two
coordinate words with the first corner taken from the current pen position
(7 bytes total). The kernel continues
to own pen state. Tests cover all four opcodes, radius 0xffff, line/area attribute
selection, truncated/oversized operands, edge/corner tangencies, sampled radial
accuracy, odd and tiny dimensions, coordinate limits, and transformed rendering.

Verified during implementation: Watcom 2020-12-01, ESP and Glue from this
repository, both native EC/NC library/driver/application builds; sanitizer host
tests; independent PDF structural validation; Poppler rendering of both pages.
**A live GEOS/spooler run and the legacy GEOS PDF Viewer remain unverified.**

## Normal Print to File smoke test

1. Install the matching backend `pdf.geo` in SYSTEM, printer `pdf.geo` in
   SYSTEM/PRINTER, and the `pdfprint.geo` test application in WORLD. For EC,
   use matching EC geodes throughout (the normal build names them pdfec.geo).
2. In Preferences/Printer, add **PDF 1.1 (Native, Print to File)** and select
   file output. Launch PDF Print Test and print to a filename ending in `.pdf`.
   No application's export command or external conversion is involved.
3. Expect two pages, each containing a red diagonal line, a blue rectangle,
   a red ellipse outline, a blue filled ellipse, a red rounded-rectangle outline,
   a blue filled rounded rectangle, a blue native-path triangle with a red
   outline, and the appropriate
   `Native PDF page 1` / `Native PDF page 2` text. Near the bottom are a
   red/green-over-blue/yellow RGB bitmap and a red mono stencil over green,
   whose unset pixels must retain the green background.
4. Use the matching rebuilt kernel as well as the backend: GrGetPath now
   retains the section fill/coordinate flags needed by clipping. Open in the GEOS PDF Viewer; also inspect with `pdfinfo`, `pdftotext` and
   `tests/check_pdf.pl output.pdf 2` on a development host. Check portrait,
   landscape, copies and tiled pages separately. An unsupported output operation
   must report a conversion error, rather than silently completing the job.
5. Regression: print the same simple drawing with the PostScript driver and
   export EPS using the existing exporter. Their source and interfaces have
   not changed, but live output comparison is still required.

## Independently testable next milestones

1. **This branch:** native streaming writer, PDL printer plumbing, basic
   vectors/text, native smoke application and development regression checks.
2. Full clip/path fidelity, masks and patterns;
   broaden shape fixtures and complete live spooler/legacy-viewer validation.
3. Font-family mapping, proper run metrics/justification, all GEOS characters,
   font embedding/subsetting and complex text-field graphics.
4. Changing palettes between slices; optional XObject output.
5. Replace the bounded xref table with VM-backed metadata for larger jobs;
   optimize text translation and add packaging/localization/UI refinements.

## Native path verification

The path fixture checks retained fill plus stroke, same-direction contours
with an odd-even hole, saved-scope clip replacement, independent application
and window clips, and transformed/intersected sections. A small pixel oracle
checks interior samples in the rendered PDF. Representative allocation and
write failures also check cleanup. This is a host adapter check; the existing
PDFPrint application's triangle is the corresponding native smoke fixture.

The path snapshot comes from GrGetPath, following SvgLib's C ownership pattern.
The separate playback state executes transforms and pen updates, while the PDF
writer constructs each section without painting its component primitives.
Stroke attributes are applied after path construction so the painting matrix
affects stroke width without transforming the retained geometry twice.
