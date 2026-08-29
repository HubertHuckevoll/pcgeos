# Intelligent Image Loading Problem Guide

This file is a compact introduction for humans and AI agents investigating
BbxBrow image loading. It explains the problem, architecture, important
tradeoffs, useful code locations, and approaches already tried.

The implementation may change. Establish the version under investigation
before relying on constants or exact behavior:

    git status --short
    git diff --ignore-space-at-eol
    git log --oneline -n 20

## Scope and non-goals

The primary concern is Intelligent image loading. Automatic and Disabled modes
must remain behaviorally unchanged unless a task explicitly includes them.

`plan_progress_refactor.md` is a historical planning artifact. Do not treat it
as the current implementation plan or as authoritative design documentation.
Do not start the large refactor described there without an explicit request.

Prefer surgical changes. This is 16-bit PC/GEOS: heap blocks, handles, loaded
geodes, layout stacks, region arrays, and queued events are all material costs.

## Design goals and invariants

Intelligent mode has used an 800 by 600, or 480000-pixel, admission limit. The
exact setting is a policy knob; the important behavioral goals are:

- Buffer at most a 4096-byte prefix while deciding.
- Stop the HTTP transfer early when an image is rejected.
- Reject missing, zero, unsupported, or excessive dimensions safely.
- Continue the normal download and import for accepted images.
- Keep accepted images compact until final import supplies the real graphic.
- Perform one normal geometry update and layout after final import.
- Preserve cancellation, memory-limit deferral, cache-token ownership, and
  waiting-image correctness.
- Show occasional page updates during loading without repeatedly restarting a
  complex layout.

Early accepted-image geometry was tried and was expensive. Be very cautious
about restoring equivalents of:

- `MSG_URL_TEXT_INTERNAL_ACCEPT_LIKE_GRAPHICS`
- `MSG_HTML_TEXT_COMMIT_IMAGE_GEOMETRY`
- `EARLY_IMAGE_LAYOUT_BATCH_SIZE`

Those made accepted images leave compact mode before import and caused an
extra geometry/layout path before the final image was available.

## Architecture and pipeline

The important path in the Intelligent-loading implementation is:

1. `urltext/URLTEXT.goc` selects Intelligent mode and sets
   `imageProbeMaxPixels` to `INTELLIGENT_IMAGE_MAX_PIXELS`.
2. `ProcessSingleGraphic` constructs `LoadProgressData`. Intelligent mode sets
   a 4096-byte probe ceiling and `LPI_PENDING`.
3. `urlfetch/URLFETCH.goc` copies that structure into asynchronous request
   storage.
4. `Library/Breadbox/UrlDrv/Wmg3Http/WMG3HTTP.goc` writes both the temporary
   file and the bounded probe stream. At the prefix limit, or at end of file,
   it invokes the load-progress callback.
5. `LoadGraphicProbeNow` in `URLTEXT.goc` calls
   `ToolsProbeGraphicByDriver` and checks dimensions without overflowing the
   pixel multiplication.
6. Rejection returns `LPCR_REJECT`; Wmg3Http stops receiving and returns
   `URL_RET_IMAGE_DEFERRED`.
7. Acceptance returns `LPCR_CONTINUE`; Wmg3Http finishes the same download and
   sets `URB_RF_IMAGE_PROBED`.
8. `MSG_URL_TEXT_GRAPHIC_FETCHED` clears the import-side probe limit when that
   flag is present, avoiding a second explicit probe.
9. `htmlview/ImportG.goc` performs the normal full import/decode and replaces
   the compact placeholder.
10. Html4Par updates final geometry, marks the affected cell/table dirty, and
    batches layout through the waiting-image list.

An accepted image is explicitly probed only once, but the normal decoder still
parses the downloaded image from the beginning. Probe decoder state is not
reused by the final import.

## Approaches tried and lessons learned

Several iterations established the following useful directions:

- Keeping accepted images compact until final import avoids an extra layout
  path and performed substantially better than committing probed dimensions
  early.
- Reusing `lastMimeDriver` avoids loading and unloading a 16-bit geode for
  every probe. Access must remain protected by `MimeDriverSemaphore`.
- A probe that runs after releasing the semaphore needs a temporary geode
  reference. Directory state must also be preserved.
- MIME drivers older than the probe protocol must return
  `MIME_GRAPHIC_PROBE_UNKNOWN` rather than calling a missing entry point.
- The final completed bitmap must expose all lines that may not have been
  displayed. Starting at line zero is safe; reporting only the final line was
  faster but could leave skipped progress ranges invisible.
- Memory-limit deferral, cancellation barriers, cache-token ownership, and
  importer/waiting-image corrections are correctness work, not optional
  performance features.
- Batched full-view redraws are preferable to one redraw per completed request.
  A tested batch size was 128, with no extra explicit redraw at zero pending
  because final layout already handles completion.
- A tested waiting-image capacity of 32 caused excessive layouts and an
  out-of-memory failure on a complex page. Values of 128 and the historical
  200 are much safer starting points.
- Avoid queuing another `MSG_HTML_TEXT_CALCULATE_LAYOUT` while layout is active.
  The running formatter already tracks image arrivals.

The active layout already handles image arrivals through
`LS_currentMasterCellGotImage` and `LS_oneMorePass`. Queuing another calculate
message while `HTS_CALCULATING_LAYOUT` is set requests an unnecessary restart.

## Why performance and memory fight each other

### Probe and import cost

Intelligent mode adds a bounded header probe to every candidate. Rejected
images save network, cache, and decode work. Accepted images still require the
normal complete download and decode, so they pay a small admission cost without
avoiding the old import path.

MIME-driver reuse removes repeated load/unload overhead. It also means one
driver can remain loaded until the import engine is killed. For accepted
images this driver is normally needed by the importer anyway. For pages that
only reject images, the retained driver is a possible secondary memory cost.

### Geometry and layout cost

Final image dimensions can change text and table geometry. Html4Par records
dirty image/cell pairs in a fixed waiting-image block. The list capacity is
also the trigger for an intermediate layout.

Each waiting entry is 8 bytes. Approximate block sizes are:

- 32 entries: 272 bytes
- 64 entries: 528 bytes
- 128 entries: 1040 bytes
- 200 entries: 1616 bytes

Changing 200 to 32 saved only about 1.3 KB, but could queue a full layout every
32 distinct dirty images. On complex table-heavy pages this caused region-array
construction, longest-line calculations, layout-stack allocation, restarts,
swapping, and eventually out-of-memory failures. It also starved importer
threads, making image decoding appear slower.

A value of 128 was tested as a compromise: some progressive updates on very
image-heavy pages, much less layout churn than 32, and a smaller block than the
historical value of 200. Verify the value in the version being investigated.

### Drawing cost

One correctness iteration changed final import notification to invalidate the
completed bitmap from line zero. The tree at `95ed93f78` invalidated only the
last line when progress callbacks were active. That was faster, but incorrect
when progress updates were coalesced or skipped. Do not restore the last-line
behavior unless the code tracks the actual first line not yet displayed.

A tested pending-request heartbeat sent `MSG_GEN_VIEW_REDRAW_CONTENT` when the
nonzero pending count was divisible by 128. It provided occasional visible
updates, but a full-view redraw is still expensive and can contribute to update
region pressure on extreme pages.

### Heap warnings

`GLOBAL_HEAP_IS_CONGESTED_SO_THREAD_IS_SLEEPING` comes from
`Library/Kernel/Heap/heapLow.asm` after a global heap allocation failure. The
kernel sleeps and retries, so one allocation can produce repeated warnings.
Some warnings are expected under tight memory. A large increase usually means
allocation churn or long-lived locked/non-discardable blocks. An out-of-memory
dialog means retry/recovery did not free enough memory.

## Historical reference points

- The tree at `95ed93f78` is the accepted-image layout baseline: compact until
  final import, waiting-image capacity 200, and no early geometry commit. The
  commit itself mostly changed the refactor plan; compare the complete tree,
  not only that commit's patch.
- `966c35a1b` added important correctness work, but also early accepted geometry,
  extra layout/redraw behavior, and full final-bitmap exposure.
- `73199299c` made redraw/layout batch constants easier to understand.
- `master` lacks much of Intelligent loading and is useful for broad speed
  comparison, not as a drop-in correctness baseline.

Useful commands:

    git diff --ignore-space-at-eol 95ed93f78 -- \
      Appl/Breadbox/BbxBrow Library/Breadbox/Html4Par CInclude
    git diff --ignore-space-at-eol 95ed93f78..966c35a1b
    git show 966c35a1b

## Known observations

- `nachrichtenleicht.de` became much faster after removing early accepted
  geometry and reducing redraw/layout work.
- A temporary waiting-image threshold of 32 made `tagesschau.de` fail with an
  out-of-memory message and made images appear slower. The likely cause was
  repeated complex layout and swapping, not a slower image decoder.
- Some heap-congestion warnings are an accepted memory/performance tradeoff.
- The product requirement is not a blank page until completion: occasional
  visible progress must remain.

## Secondary issue outside the Intelligent-mode focus

The examined implementation constructs and passes `LoadProgressData` for
ordinary image requests even when Intelligent probing is disabled. URLFetch
then allocates and copies it. Depending on progress-display settings, this can
add per-image work in Automatic mode. Treat this separately from an
Intelligent-only regression.

## Safe investigation order

When a page regresses, check in this order:

1. Count full layouts and `HTS_LAYOUT_RESTART_REQUESTED` transitions.
2. Count dirty images accumulated between layouts.
3. Correlate heap warnings with layout-stack/region-array work versus MIME
   driver changes and import progress allocations.
4. Distinguish network time, probe time, import/decode time, layout time, draw
   time, and heap-retry sleep time.
5. Check whether the page mixes GIF, JPEG, and PNG, which forces cached-driver
   switching.
6. Check whether images are accepted, rejected, canceled, unsupported, cached,
   or deferred by the memory limit.

Do not optimize by blindly:

- Restoring early geometry.
- Redrawing on every completed request.
- Reducing `MAX_WAITING_IMAGES` to save about one kilobyte.
- Reverting final exposure to only the last bitmap line.
- Removing memory-limit deferral or cancellation barriers.
- Loading and freeing the MIME driver for every probe.

## Build and runtime checks

Build source changes from matching Installed directories:

    cd Installed/Library/Breadbox/Html4Par
    pmake -L 4 full

    cd Installed/Appl/Breadbox/BbxBrow
    pmake -L 4 full

Always inspect the source diff with `--ignore-space-at-eol`. Some legacy files
use CRLF; do not normalize them.

Minimum runtime matrix:

- Many accepted small images.
- Oversized image rejected after the bounded prefix.
- Mixed GIF/JPEG/PNG images and repeated images of one MIME type.
- Invalid and unsupported image formats.
- Cancellation during probe, download, and import.
- Cached and uncached loads.
- Memory-limit deferral.
- Automatic and Disabled mode regression checks.
- `nachrichtenleicht.de` for ordinary-page responsiveness.
- `tagesschau.de` for layout, swapping, and out-of-memory stress.

For accepted images, verify that placeholders remain compact until final import,
then receive correct dimensions and one normal final geometry/layout update.
