# PDF translator backlog

Updated 2026-11-07. These items are deferred. Keep future changes small and
use focused checks. The agent must not run PC/GEOS; runtime checks are user-run.

## Text

- Add outline text style (TS_OUTLINE).
- Compare mixed-style and justified GeoWrite lines with native or EPS output.
  Check word spacing, run boundaries, fractional positions and baselines.
  Native width, pair/track kerning and space-padding queries already exist;
  add layout code only when a comparison shows a defect.
- Support embedded graphics in text fields. C_GRAPHIC still fails explicitly;
  it must not be treated as an invisible control character.
- Add font-specific glyphs in other C0 control slots if real documents need
  them. Common GEOS layout controls and formatting-mark mappings are handled.
- Extend character coverage, including the currently rejected currency,
  accented Y/y and GEOS logo characters, and DBCS text.
- Improve exact font fidelity through font embedding/subsetting. Ordinary
  text currently uses PDF standard-font substitutions with GEOS positioning.
- Support bitmap-only fonts in painted or clipped text paths. They have no
  vector outline for the current font-driver outline route.

## Optional image and line details

- Support a palette change within one sliced indexed bitmap. Initial and
  repeated identical palettes already work. Normal kernel output writes the
  palette once, so this has low priority. Use separate image pieces or RGB
  conversion if support is needed; preserve the meaning of earlier pixels.
- Make dashed hairline spacing exact for the target device resolution.
  Only zero-width dashed strokes use the current 1/16-point dash scale.
  Solid hairlines and dashed strokes with nonzero width already work.

## Further graphics support

- Add patterned fills, partial drawing masks and non-copy mix modes where
  useful. Unsupported operations must keep reporting an error.
- Consider exact vector Boolean unions. Union fills/clips currently use
  native regions at 300 dpi; other paths retain vector curves. The region
  route uses signed-word device coordinates and translated page strips.
- Extend the 32-byte native glyph-command decoder only if a font driver
  produces larger records. Keep allocations and stack use bounded.
- Revisit three-point arc fitting and 16.16 operand limits only when actual
  documents exceed the current supported range.

## User-run application checks

- Print GeoWrite text with control characters, formatting marks, scripts,
  decorations, automatic/optional hyphens and mixed styles.
- Print an example with union/intersection clips and holes, including shapes
  across the native region conversion-strip boundary. Host checks supply
  region fixtures; they do not execute the native Boolean region engine.
- Check imported SVG shapes, strokes, holes and clipping.
- Check the existing PDFPrint text, image, mask, dash, arc and brush examples.
- Check landscape, copies and tiled output.
- Check cancellation, disk-full handling and late finalization errors.
- Open the output in both the native GEOS PDF viewer and a host PDF reader.
- Compare one representative document with existing PostScript/EPS output.

## Larger jobs and packaging

- Extend page/object metadata beyond the current 256-page limit if needed.
- Consider PDF output compression, image XObjects and other output-size
  improvements after ordinary document acceptance.
- Review packaging, localization and printer UI details.
- Keep the existing 31 saved-state levels and 32760-byte output-record limit
  unless a real use case requires a change.
