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
  `TextAttr` is 23 bytes in the SBCS ABI. CInclude's OpDrawLine member names
  interchange x2/y1, so scalar operands are explicitly decoded little endian.
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
| `pdfStream.asm` | Checked Pascal wrapper for the stream strategy |
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
* RGB fill/stroke/text colors; solid masks, line width/caps/joins/miter limit.
* DrawText/DrawTextAtCP, DrawChar/DrawCharAtCP, plain counted text-field runs.
* Helvetica regular/bold/oblique/bold-oblique, substituting other GEOS fonts.
  Characters use GEOS-measured positions to preserve line/run layout. The
  common MacRoman subset includes German umlauts and sharp s. GEOS characters
  that differ from MacRoman are rejected. No embedded fonts are required.
* Balanced save/restore scopes (up to 31 nested saves). Rectangular clipping
  supports intersection and replacement/null in scopes without an inherited
  clip. Replacing a parent scope's clip and unions currently fail explicitly.
* Uncompacted mono and RGB24 bitmaps: simple headers and complex sliced headers,
  explicit DPI, DrawBitmap/DrawBitmapAtCP; FillBitmap/FillBitmapAtCP for mono.
  Empty introductory headers emitted by HugeBitmapToString are supported.

This is a **restricted SBCS vector/text milestone**, not general document
fidelity yet. Paletted/compacted bitmaps, stored bitmap masks, arbitrary paths,
arcs, patterned fills/dashes,
non-copy mixing, window clipping, embedded graphics in text fields, automatic
hyphens, underline/strikeout/super/subscript and DBCS remain future work.
Font family/shape fidelity, fractional text-field positioning, full character
coverage and justified field metrics need further work. Prefix-width queries
currently favor correctness of simple text positioning over speed on long
runs. Failed jobs may leave incomplete output; the spooler owns destination
cleanup. The backend does not publish a success trailer after a latched error.

## Bitmap boundary and extension points

The bitmap pipeline separates **source storage**, **canonical rows**, and
**PDF encoding**. No GEOS bitmap flag is used as a PDF image-format constant.

| Layer | Current contract | Extension point |
| --- | --- | --- |
| `PdfBitmapParse` | Validate the 6-byte Bitmap or 20-byte CBitmap, dimensions, row count, data offset and DPI | Recognize additional storage headers/flags without changing PDF objects |
| `PdfBitmapReaderOpen` / `PdfBitmapNextRow` | Return borrowed, top-down canonical scanlines from one locked source slice; no extra allocation today | Palette expansion or bounded scanline decompression belongs here; keep encoded-row cursor and optional workspace in the reader |
| `PdfImageBegin` / `PdfImageRow` / `PdfImageEnd` | Canonical stencil1/RGB24 rows, exact byte/row counts, ASCIIHex inline image | Additional PDF color spaces or encodings remain independent of GEOS storage; indexed input can initially expand to existing RGB24 rows |

GEOS monochrome drawing is **not** an opaque black/white image: zero bits leave
existing content alone. DrawBitmap paints set bits black, whereas FillBitmap
paints them with the current area color (`graphicsRaster.asm` and the video
driver's PutBWScan/FillBWScan). The writer therefore uses an inline image mask
with `/IM true /D [1 0]`. This supports the inherent mono stencil and does not
mean that separately stored `BMT_MASK` planes are implemented. Those are rejected;
a later masked-color implementation can add a separate mask-plane path instead
of changing opaque RGB samples into a guessed background color.

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
at a time, plus a 65-byte hex conversion buffer. There is no full-image or
additional scanline allocation. ASCIIHex output approximately doubles data size.

Physical dimensions are pixels*72/DPI, calculated with checked 32-bit integer
arithmetic. The local image matrix corrects PDF's top-row orientation within
GEOS's downward y axis, while retaining the caller's affine transform. The
classic page resources declare ImageB/ImageC. Image lifetime is checked: a page
cannot end inside an image, and partial or extra rows do not produce a successful
trailer. No seek, external converter or new exported library function is needed.

Remaining bitmap work: PackBits/LZG, indexed/palette formats, separately stored
masks, pointer/optr records and colored FillBitmap semantics. Unsupported forms
fail explicitly. This boundary allows those converters to be developed with
source-row fixtures independently of the print driver and spooler.

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

The tests use the production serializer and GEOS adapter. The kernel double
checks element dispatch, end/new-page handling, packed text-field layout,
rectangular clipping, allocation/write failures and handle cleanup. A separate
Perl checker validates every xref byte offset, indirect stream length and page
reference. Poppler parsing/rendering is checked when installed. These are
host-side development checks, not runtime dependencies.

Bitmap checks cover simple/complex headers, CP/fill variants, empty intro slices,
continuation validation, DPI, malformed payloads, every slice allocation failure,
and streaming an image larger than a 16-bit block. At most two owned heap blocks
(job context and current element) may be live in the double. Image tests inject
write failures and prevent premature page finalization. When Poppler is available,
an independent Perl pixel oracle verifies exact RGB channel/row order, mono
stencil polarity, transparent zero bits and non-byte-aligned widths. The GString
fixture itself also contains mono/RGB images and is parsed/rendered independently.

The shape module provides internal C functions `PdfEllipse` and `PdfRoundRect`;
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
   a blue filled rounded rectangle, and the appropriate
   `Native PDF page 1` / `Native PDF page 2` text. Near the bottom are a
   red/green-over-blue/yellow RGB bitmap and a red mono stencil over green,
   whose unset pixels must retain the green background.
4. Open in the GEOS PDF Viewer; also inspect with `pdfinfo`, `pdftotext` and
   `tests/check_pdf.pl output.pdf 2` on a development host. Check portrait,
   landscape, copies and tiled pages separately. An unsupported output operation
   must report a conversion error, rather than silently completing the job.
5. Regression: print the same simple drawing with the PostScript driver and
   export EPS using the existing exporter. Their source and interfaces have
   not changed, but live output comparison is still required.

## Independently testable next milestones

1. **This branch:** native streaming writer, PDL printer plumbing, basic
   vectors/text, native smoke application and development regression checks.
2. Full clip/path fidelity, arcs, line styles, masks and patterns;
   broaden shape fixtures and complete live spooler/legacy-viewer validation.
3. Font-family mapping, proper run metrics/justification, all GEOS characters,
   font embedding/subsetting and complex text-field graphics.
4. Bitmap compression/palette/mask converters and optional XObject output.
5. Replace the bounded xref table with VM-backed metadata for larger jobs;
   optimize text translation and add packaging/localization/UI refinements.
