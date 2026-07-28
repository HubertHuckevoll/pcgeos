# VCImpex SVG Export Development Plan

## Goal

Establish a dependable vector-only SVG exporter before adding new format
coverage. A successful export must preserve every supported drawing operation
and must fail clearly when a document contains an unsupported rendering
operation. Non-rendering metadata may continue to be ignored.

The exporter will use the playback GState as the sole source of graphics state,
current position, save/restore state, and transforms. It will not maintain a
second transform or pen stack.

## Milestone 1 - Define safe export behavior

- Accept export only when `EF_formatNumber` is `FORMAT_SVG`.
- Return `TE_EXPORT_NOT_SUPPORTED` for the HPGL and CGM format numbers.
- Classify all GString opcodes as supported rendering, supported state,
  ignorable metadata, or unsupported rendering.
- Return a clear export error for unsupported rendering opcodes instead of
  silently omitting content.
- Validate the minimum size of every fixed-size opcode before reading fields.
- Validate point counts and complete variable payload sizes before reading
  custom line styles, polygons, polylines, splines, or paths.
- Do not truncate or write the destination before the frame, format, clipboard
  format, GString, and initial bounds have been validated.

Acceptance:

- Selecting SVG exports SVG.
- Selecting HPGL or CGM never writes SVG under the requested extension.
- Malformed or unsupported rendering data returns an error without reporting a
  successful lossy export.
- Comments, labels, and other approved non-rendering metadata do not fail an
  export.

- Done!

## Milestone 2 - Introduce the shared C89 conversion core

Create a small conversion core compiled unchanged by the DOS test runner and
the GEOS translator.

- Keep the core free of GEOS memory, file, GState, object, and VM calls.
- Define exact signed and unsigned 16-bit and 32-bit types and compile-time size
  checks suitable for Watcom C.
- Pass normalized primitive data, fixed-point values, style values, and affine
  matrices into the core.
- Write output through a bounded sink callback that receives a pointer and byte
  count and reports success or failure.
- Keep GString traversal, `GrGetTransform()`, `GrGetCurPosWWFixed()`, LMem
  allocation, and `FileWrite()` in the GEOS adapter.
- Use bounded append and formatting operations throughout the core. Do not
  depend on unbounded `sprintf()` calls into fixed buffers.

Acceptance:

- The same core source compiles as Watcom C89 for DOS and as part of VCImpex.
- The core has no GEOS link dependencies.
- Sink failure is propagated to the caller without further output.

## Milestone 3 - Consolidate decoding and scratch memory

- Replace the two 4 KB library globals with one reusable LMem-backed scratch
  area owned by `VCImpexSVGExportContext`.
- Allocate or resize scratch storage only when the current validated element
  requires it.
- Stream polygon, polyline, and path coordinates to the sink where practical
  instead of retaining complete duplicate arrays.
- Decode each geometry opcode in one place. Use the normalized result for both
  ordinary primitive emission and path construction.
- Remove duplicated line and curve decoding from the outer GString traversal
  and the path traversal.
- Split code resources only if the resulting modules still exceed the desired
  resource size after duplication and allocation code have been removed.

Acceptance:

- No exporter scratch buffers remain in library dgroup.
- Normal and EC builds no longer report the current 8 KB of exporter
  uninitialized scratch data.
- Variable-length elements cannot read beyond the bytes reported by
  `GrGetGStringElement()`.

## Milestone 4 - Make transforms consistent

- Decode every supported primitive in local GEOS coordinates.
- Query `GrGetTransform()` immediately before handling the current output
  opcode and attach that matrix to the emitted SVG element.
- Use `GrGetCurPosWWFixed()` as the local starting point for relative and `_TO`
  opcodes.
- Allow the playback GState to apply transform, save-state, and restore-state
  opcodes during traversal.
- Do not add a private transform stack, private pen stack, or compatibility
  mode.
- Let normal SVG transform behavior scale strokes. Remove
  `vector-effect="non-scaling-stroke"` unless a focused GEOS rendering test
  proves that a particular operation requires it.
- Omit the SVG transform attribute only for an exact identity matrix.

Acceptance:

- Translation, scaling, rotation, shear, and nested save/restore sequences
  produce the same geometry as the source GString.
- Mixed absolute, relative, and `_TO` sequences start at the correct current
  position.
- All primitive families use the same transform policy.

## Milestone 5 - Correct the existing primitives

- Lines and cubic curves:
  - Preserve local start, control, and end points.
  - Verify all absolute, relative, horizontal, vertical, and `_TO` forms.
- Rectangles and rounded rectangles:
  - Compute local `x`, `y`, width, height, and radii before attaching the
    matrix.
  - Normalize reversed corners without losing the transform.
  - Preserve rotation and shear by emitting a local SVG `rect`.
- Ellipses:
  - Use 32-bit intermediate sums and differences for centers and radii.
  - Apply the same matrix and stroke policy as other primitives.
- Bounding-box arcs:
  - Treat angles as signed values and normalize them without repeated
    unbounded loops.
  - Use 32-bit intermediate arithmetic for centers, radii, and angle
    differences.
  - Emit the required closing segment for open, chord, and pie semantics.
  - Split a 360-degree arc into two SVG arc commands so a full circle cannot
    collapse to an empty path.
  - Preserve the requested fill rule and stroke/fill distinction.
- Polygons, polylines, and paths:
  - Preserve fill rules and closure.
  - Support move, line, horizontal line, vertical line, cubic curve, and close
    operations consistently inside and outside paths.
  - Fail if an unsupported rendering opcode occurs inside a path.

Acceptance:

- Golden output covers normal, reversed, negative, odd-sized, and near-limit
  coordinates for every existing primitive.
- Rotated and sheared rectangles and rounded rectangles render correctly.
- Arc tests cover negative angles, zero sweep, 180 degrees, wraparound, full
  circles, and open, chord, and pie closure.

## Milestone 6 - Add vector coverage

Add new rendering support only after all earlier acceptance checks pass, in
this order:

1. Points and current-position points.
2. Splines and spline-to operations, converted to equivalent cubic paths.
3. Absolute, `_TO`, relative, draw, and fill three-point arcs.
4. Brush polylines, using an explicitly documented SVG approximation when an
   exact representation is not practical.

Each family must use the shared decoder, local-coordinate transform policy,
bounded sink, and both test layers before the next family begins.

Text, bitmaps, clipping, masks, and non-copy mixing modes remain unsupported
later milestones. Each requires a separate fidelity policy before
implementation.

## Watcom 16-bit DOS tests

- Build the shared core and a small golden-output runner with
  `wcl -bt=dos -ms -zq`.
- Keep the runner framework-free and return a non-zero DOS exit code on the
  first failed check.
- Store compact input cases and expected SVG strings. Compare lengths and bytes,
  not only null-terminated strings.
- Cover fixed-point formatting, matrix formatting, bounded writes, sink
  failures, opcode payload validation, style attributes, every primitive, and
  every arc edge case.
- Run the DOS executable in an available DOS environment. QEMU is installed,
  but a DOS boot image or another ready DOS runner must be supplied before this
  test can be automated locally.

Acceptance:

- The DOS runner compiles with warnings enabled under the 16-bit Watcom
  compiler.
- All golden tests pass in DOS.
- The runner links the same conversion-core object source used by VCImpex; no
  implementation is copied into the filter later.

## PC/GEOS integration tests

Add a tiny test geode that exercises the real translator boundary.

- Create VM-backed GStrings using the actual `Gr*` APIs.
- Include style changes, paths, transforms, nested save/restore, relative
  operations, and each supported primitive.
- Invoke VCImpex through its translator ABI with a real `ExportFrame`.
- Read the produced SVG and compare it with compact golden output.
- Include negative cases for non-SVG format numbers, malformed element sizes,
  unsupported rendering opcodes, output write failure, and allocation failure
  where practical.
- Run the integration checks against both normal and EC builds.

Acceptance:

- The integration geode verifies GString traversal, GState state timing, path
  extraction, transform retrieval, LMem behavior, and file output.
- Normal and EC VCImpex geodes build after Meta with no new warnings.
- Supported test drawings match their expected SVG and unsupported drawings
  fail without silent content loss.

## Completion criteria

The vector-only milestone is complete when:

- SVG is the only accepted export subformat.
- Every encountered rendering opcode is either exported correctly or causes a
  clear failure.
- Existing primitives and transforms pass the DOS golden tests and the GEOS
  integration tests.
- Exporter scratch memory is context-owned rather than global.
- No private transform stack exists.
- Text, bitmap, clipping, mask, and non-copy mixing limitations are documented
  as explicit future work.
