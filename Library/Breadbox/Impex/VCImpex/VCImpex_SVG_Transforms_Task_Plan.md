# VCImpex SVG Export — Sequenced Task Plan
Transform attributes everywhere (VCImpex / SVG exporter)

## Overview
A step-by-step plan that can be handed to a coding agent as a series of small, self-contained tasks. Each task has a goal, file touches, concrete changes, and acceptance criteria. Tasks build on one another and preserve legacy behavior when `exportTransformsEverywhere == FALSE`.

---

## Task 1 — Add context + state stack
**Goal:** Introduce the transform/pen stack and the feature flag.

**Touch:** `svgexp.h`, `svgexp.c` (or wherever `ExportProcedure` lives)

**Changes:**
- Add to `VCImpexSVGExportContext`:
  - `Boolean exportTransformsEverywhere` (default `TRUE`)
  - `TransMatrix currentMatrixScratch`
  - `PointWWFixed localCurrentPoint`
  - ```
    typedef struct {
        TransMatrix tm;
        PointWWFixed pen;
    } VCImpexSVGStateEntry;
    ```
  - `VCImpexSVGStateEntry stack[VCIMPEX_SVG_MAX_STATE_DEPTH];`
  - `word stackTop;`
- Add helpers (decls in header):
  - `void VCImpexSVGStateInit(VCImpexSVGExportContext *ctx);`
  - `Boolean VCImpexSVGStatePush(VCImpexSVGExportContext *ctx);`
  - `Boolean VCImpexSVGStatePop(VCImpexSVGExportContext *ctx);`
  - `void VCImpexSVGStateApplyMultiply(VCImpexSVGExportContext *ctx, const TransMatrix *m);`
  - `const TransMatrix* VCImpexSVGStateGetMatrix(VCImpexSVGExportContext *ctx, TransMatrix *scratchOut);`
- In `ExportProcedure` (before `VCImpexSVGExportGString()`):
  - Initialize flag to TRUE (unless caller overrides).
  - Seed `stack[0].tm = identity`, `stack[0].pen = {0,0}`, `stackTop = 0`.
  - Copy `stack[0].pen` to `localCurrentPoint`.

**Accept:** Build passes; initial export still works with no functional change.

---

## Task 2 — Wire SAVE/RESTORE + transform opcode handler shell
**Goal:** Start handling transform/state opcodes via our stack.

**Touch:** `svgexpproc.goc`

**Changes:**
- Remove the skip block that ignores transform/state opcodes in main loop.
- Add `static Boolean VCImpexSVGHandleTransformOpcode(...)` stub.
- Call it from the main loop before geometry handling; if it returns `TRUE`, continue.

**Accept:** No geometry regression on simple files; handler returns `FALSE` for unknown opcodes.

---

## Task 3 — Implement transform/state decoding
**Goal:** Update stack instead of calling Gr* during export.

**Touch:** `svgexpproc.goc`

**Changes:**
- In `VCImpexSVGHandleTransformOpcode(...)`, decode:
  - `GR_APPLY_TRANSLATION`, `GR_APPLY_SCALE`, `GR_APPLY_ROTATION`, `GR_APPLY_TRANSFORM`
  - `GR_SET_TRANSFORM`, `GR_RESET_TRANSFORM` (if present)
  - `GR_SAVE_STATE`, `GR_RESTORE_STATE`
- Update only the context stack:
  - Multiply/push/pop matrices accordingly.
  - On SAVE, push `{tm=current, pen=current local pen}`.
  - On RESTORE, pop both.
- Return `TRUE` for handled opcodes, `FALSE` otherwise.

**Accept:** Nested SAVE/RESTORE produces expected stack depth; no SVG output from these opcodes.

---

## Task 4 — Local pen tracking (framework)
**Goal:** Switch “current point” to local space pen.

**Touch:** `svgexpproc.goc` geometry dispatch

**Changes:**
- Use `context->localCurrentPoint` as the current pen for all geometry opcodes.
- After each emitted or move-only opcode, update this pen per op semantics:
  - Absolute: set to endpoint
  - Relative: add delta
  - MOVE-only: update pen, no emission
- Ensure SAVE pushes pen; RESTORE restores pen (already in Task 3).

**Accept:** Straight line/move sequences export unchanged SVG with flag FALSE; pen updates verified via debug logs (if available).

---

## Task 5 — Back-compat guard
**Goal:** Keep legacy “baked” path working.

**Touch:** places where we fetch current matrix / emit

**Changes:**
```c
const TransMatrix *tmPtr = NULL;
if (context->exportTransformsEverywhere)
    tmPtr = VCImpexSVGStateGetMatrix(context, &context->currentMatrixScratch);
```
- Legacy code path (flag FALSE) continues to use existing `VCImpexSVGTransformPointFrom*` and `GrGetCurPosWWFixed`.

**Accept:** With flag FALSE, byte-for-byte output unchanged for a legacy sample.

---

## Task 6 — Helper utilities
**Goal:** Provide shared helpers used by handlers and writers.

**Touch:** `svgsubcode.goc` (or a shared util), header decls in `svgexp.h`

**Changes:**
- `Boolean VCImpexSVGIsIdentityMatrix(const TransMatrix *tm, WWFixed eps);` (compare e11/e22≈1, e12/e21≈0)
- Point/WWFixed packers:
  - `void VCImpexSVGPointFromInt(PointWWFixed *out, const GStringPointInt *in);`
  - `void VCImpexSVGPackWWFixed(WWFixed *out, int val);` (or existing)

**Accept:** Unit calls compile; identity detection used later in writers.

---

## Task 7 — Update simple geometry handlers (move/line, absolute+relative)
**Goal:** Operate purely in local coords when flag TRUE.

**Touch:** `svgexpproc.goc` (handlers), `svgsubcode.goc` (writers will change later)

**Changes (flag TRUE path):**
- Convert payload ints → `WWFixed`.
- For `_TO` variants, first corner uses `localCurrentPoint`.
- Relative ops: add delta to **local** pen before storing/after emitting as needed.
- After emission, update `localCurrentPoint`.
- Fetch `tm` via Task 5 and pass to writers.

**Accept:** A simple polyline with mixed abs/rel produces same shape but with a `transform` attribute on elements.

---

## Task 8 — Rect / RoundRect correctness
**Goal:** Fix prior bug: compute rects from untransformed corners.

**Touch:** rect/round-rect handler(s) + writer(s)

**Changes (flag TRUE path):**
- Compute `x,y,width,height` from local `corner1`/`corner3` only; radii from payload.
- No recomputation from already-transformed points.
- Pass `tm` to writer.

**Accept:** Rotated rectangle exports as `<rect ... transform="matrix(...)" ...>` (no skewed width/height).

---

## Task 9 — Polygons, curves, arcs/ellipses (local math)
**Goal:** Keep all math in local space; stop calling `GrTransform`.

**Touch:** respective handlers

**Changes:**
- Polygons: fill `svgPolygonBuffer` in local coords directly; track last point into `localCurrentPoint` if semantics require.
- Curves & path segments: build control points/deltas in local; relative adds before store; no world transforms.
- Arcs/Ellipses: reuse existing center/radii formulas but **do not** call `GrTransform`; attach `tm` from stack.

**Accept:** Bezier test file and ellipse/arc samples render correctly when viewed with the emitted `transform`.

---

## Task 10 — Path emission rewrite
**Goal:** Make path builder run in local space and emit a single `<path>` with `transform`.

**Touch:** `VCImpexSVGEmitPath()` and new writer

**Changes:**
- Replace any `VCImpexSVGTransformPointFrom*` usage with direct reads → local `PointWWFixed`.
- Maintain a path-local `PointWWFixed localPen`, seeded from `context->localCurrentPoint` at path start; update per opcode.
- Add `VCImpexSVGWritePathElement(..., const TransMatrix *tm)` or extend existing builder to accept `tm`.
- After final write, set `context->localCurrentPoint = localPen`.

**Accept:** Mixed absolute/relative path reproduces geometry; single `transform="matrix(...)"` on `<path>`.

---

## Task 11 — Writer signatures + transform attribute
**Goal:** Let every primitive writer accept an optional transform.

**Touch:** `svgsubcode.goc` (all writers), corresponding headers and call sites

**Changes:**
- Update signatures: `...WriteLine(..., const TransMatrix *tm)`, etc. for line, rect, round-rect, polygon, path, curve, arc, ellipse.
- In each writer:
  - Temporarily force non-scaling stroke when `tm != NULL` (use existing override pattern around `VCImpexSVGStyleToAttributes()`).
  - Format matrix with `VCImpexSVGFormatMatrix()`.
  - Skip attribute if `tm == NULL` or `VCImpexSVGIsIdentityMatrix(...) == TRUE`.
  - Append attribute before closing `>`/`/>`.
- Rect/RoundRect writers: keep negative width/height normalization (now on local coords).

**Accept:** All primitives compile with new sig; sample export shows `vector-effect="non-scaling-stroke"` when transformed.

---

## Task 12 — Final back-compat + regression cover
**Goal:** Prove both modes behave.

**Touch:** test scaffolding / sample inputs

**Checks:**
- **Transforms Everywhere (TRUE):**
  - Rotated rect/round-rect yields `<rect>`/`<rect rx ry>` + `transform="matrix(...)"`.
  - Nested SAVE/RESTORE alters emitted transform as stack changes.
  - Relative path commands maintain expected local pen (including when path isn’t emitted due to open subpath).
- **Baked mode (FALSE):**
  - Old files export byte-for-byte (or attribute-order-equivalent).

**Accept:** Visual diff (or textual diff for baked mode); manual spot check in an SVG viewer for TRUE mode.
