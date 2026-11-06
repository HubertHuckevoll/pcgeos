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
  result after the final output element is legitimate. A zero-size read is
  a fault. A new-page marker is consumed; an end-of-string marker is retained.
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

This is a **restricted SBCS vector/text milestone**, not general document
fidelity yet. Bitmaps, arbitrary paths, arcs, patterned fills/dashes,
non-copy mixing, window clipping, embedded graphics in text fields, automatic
hyphens, underline/strikeout/super/subscript and DBCS remain future work.
Font family/shape fidelity, fractional text-field positioning, full character
coverage and justified field metrics need further work. Prefix-width queries
currently favor correctness of simple text positioning over speed on long
runs. Failed jobs may leave incomplete output; the spooler owns destination
cleanup. The backend does not publish a success trailer after a latched error.

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
   `Native PDF page 1` / `Native PDF page 2` text.
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
4. Incremental bitmap XObjects and color/palette support; failure stress tests.
5. Replace the bounded xref table with VM-backed metadata for larger jobs;
   optimize text translation and add packaging/localization/UI refinements.
