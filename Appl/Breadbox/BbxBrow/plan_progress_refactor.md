# BbxBrow / ImpGraph Incremental Advance Refactor Plan

## How to use this plan with Codex

Each numbered step is an independent implementation task.

When assigning work, use instructions such as:

**“Implement Step 4 only. Do not begin Step 5. Keep all existing functionality needed by later migration steps compiling.”**

Do not renumber steps during the project.

After each step:

1. Build all components touched by that step.
2. Build EC and non-EC variants where relevant.
3. Fix all issues caused by the step.
4. Do not perform unrelated cleanup.
5. Do not begin the next step until the current step compiles.
6. Preserve existing line endings.
7. Review with `git diff --ignore-space-at-eol`.

The final architecture is:

```text
Wmg3Http
    |
    | raw response bytes
    v
BbxBrow
    |
    | browser-owned input queue
    v
BbxBrow import worker
    |
    | Begin()
    | Advance(raw bytes)
    | Advance(raw bytes)
    | ...
    v
ImpGraph
    |
    | consumed byte count
    | header information
    | changed HugeBitmap state
    | need-data / yield / done / error
    v
BbxBrow
```

ImpGraph must ultimately have no knowledge of:

- HTTP or URL drivers
- BbxBrow
- browser objects
- NameTokens
- ObjCache
- load-progress callbacks
- import-progress callbacks
- fetch threads
- semaphores
- browser progress-display policy
- browser probe policy

ImpGraph becomes a resumable decoder:

```text
raw bytes -> decoder state -> GEOS HugeBitmap
```

---

# Step 1 — Establish and document the current baseline

## Goal

Create a known-good baseline before changing interfaces.

## Scope

Do not refactor functionality in this step.

Inspect the complete repository for:

- `PROGRESS_DISPLAY`
- `LoadProgressData`
- `ImportProgressData`
- `_LoadProgressParams_`
- `_ImportProgressParams_`
- `MIME_ENTRY_GRAPHIC`
- `MIME_ENTRY_GRAPHIC_EX`
- `MIME_ENTRY_GRAPHIC_PROBE`
- `ToolsImportGraphicByDriver`
- `ToolsProbeGraphicByDriver`
- `ImpGIFCreate`
- `ImpGIFProcess`
- `IG_STATUS_NEED_DATA`
- IJG JPEG source-manager code
- Fjpeg source-manager code
- PNG file/chunk/IDAT input code
- BbxBrow memory-stream code
- Wmg3Http progress and stream calls

Identify all callers of ImpGraph, especially:

- BbxBrow
- PicAlbum
- GPCMail
- ImpDoc

Identify all relevant URL drivers.

Record enough of the current call graph that later changes do not accidentally omit a consumer.

Verify existing EC and non-EC builds.

## Completion criteria

- No intentional behavior change.
- Current image import paths still build.
- Current progressive BbxBrow path still builds.
- Relevant callers and interfaces are identified.

**Do not begin Step 2.**

---

# Step 2 — Add the new Begin / Advance / Destroy ABI

## Goal

Introduce the final incremental decoder API beside the legacy API.

Do not migrate any codec yet.

## Add public types

Add an opaque decoder-session handle, for example:

```c
typedef MemHandle MimeGraphicImportHandle;
```

Add input flags:

```c
typedef WordFlags MimeGraphicInputFlags;

#define MGIF_NONE           0x0000
#define MGIF_END_OF_DATA    0x0001
```

Add Advance status:

```c
typedef enum
{
    MGAS_NEED_DATA,
    MGAS_YIELD,
    MGAS_DONE,
    MGAS_DONE_PARTIAL,
    MGAS_ERROR
} MimeGraphicAdvanceStatus;
```

Add Advance event flags:

```c
typedef WordFlags MimeGraphicAdvanceEvents;

#define MGAE_HEADER_READY       0x0001
#define MGAE_BITMAP_CHANGED     0x0002
#define MGAE_OUTPUT_READY       0x0004
```

Add a result structure similar to:

```c
typedef struct
{
    word MGA_consumed;
    MimeGraphicAdvanceEvents MGA_events;

    VMBlockHandle MGA_output;
    ImageAdditionalData MGA_iad;

    word MGA_firstLine;
    word MGA_lastLine;

    dword MGA_usedMem;
    word MGA_error;
} MimeGraphicAdvance;
```

## Add driver entries

Add:

```text
MIME_ENTRY_GRAPHIC_BEGIN
MIME_ENTRY_GRAPHIC_ADVANCE
MIME_ENTRY_GRAPHIC_DESTROY
```

Do not remove:

```text
MIME_ENTRY_GRAPHIC
MIME_ENTRY_GRAPHIC_EX
MIME_ENTRY_GRAPHIC_PROBE
```

yet.

Do not reuse or renumber the new entry values later merely for cosmetic reasons.

The new entry points should conceptually be:

```c
MimeGraphicImportHandle
MimeDrvGraphicBegin(...);

MimeGraphicAdvanceStatus
MimeDrvGraphicAdvance(
    MimeGraphicImportHandle importH,
    const byte *dataP,
    word dataSize,
    MimeGraphicInputFlags inputFlags,
    MimeGraphicAdvance *advanceP);

void
MimeDrvGraphicDestroy(
    MimeGraphicImportHandle importH);
```

The skeleton implementation may return unsupported/error because no codec has migrated yet.

## Important contract

`dataP` is valid only for the duration of `Advance()`.

ImpGraph must never retain a raw caller input pointer after `Advance()` returns.

## Completion criteria

- New ABI exists.
- Legacy API still works unchanged.
- All affected components compile.
- No codec has been migrated yet.

**Do not begin Step 3.**

---

# Step 3 — Implement generic ImpGraph decoder-session infrastructure

## Goal

Implement the generic state machine behind Begin / Advance / Destroy without decoding images yet.

## Session state

Create private session state containing at least:

- selected or undecided codec
- destination VM file
- resolution
- graphic flags/options
- AllocWatcher state if required
- MIME hint
- small format-detection prefix
- header-reported flag
- output-exposed flag
- current output VM block
- `ImageAdditionalData`
- used-memory accounting
- codec-private state/handle
- lifecycle state

## Format detection

Implement signature recognition for:

- GIF
- JPEG
- PNG

The MIME value is a hint only.

Required behavior eventually must support:

- correct MIME
- empty MIME
- missing MIME
- incorrect MIME with recognizable supported signature

Do not require rewind of the caller stream.

Retain a small prefix internally until the format is known.

## EC assertions

Add assertions for:

- valid session handle
- valid lifecycle state
- `MGA_consumed <= dataSize`
- codec enum matching codec-private state
- no mutation after terminal destruction
- stable exposed output handle

## Completion criteria

- Begin allocates a valid session.
- Advance dispatch infrastructure exists.
- Destroy releases the session.
- Signature detection exists.
- Legacy imports remain unchanged.
- No real codec is using Advance yet.

**Do not begin Step 4.**

---

# Step 4 — Migrate GIF to Begin / Advance / Destroy

## Goal

Make GIF the first working incremental codec.

GIF is the proof of the Advance architecture.

## Use existing incremental GIF functionality

Base the new path on the existing concepts around:

- `ImpGIFCreate`
- `ImpGIFProcess`
- `IG_STATUS_NEED_DATA`

Do not wrap the old synchronous file importer and pretend it is incremental.

The new path must work as:

```text
Begin

Advance(bytes)
    -> consume some/all bytes
    -> preserve GIF state
    -> NEED_DATA or YIELD

Advance(more bytes)
    -> continue same decoder

...

DONE
```

## Header event

When width/height and required header information become known, return:

```text
MGAE_HEADER_READY
```

Return control before unnecessary pixel decoding where possible.

## Bitmap updates

Translate GIF progress information into:

```text
MGAE_OUTPUT_READY
MGAE_BITMAP_CHANGED
MGA_firstLine
MGA_lastLine
```

Use a conservative line range for interlaced updates if necessary.

Do not call:

- `LoadProgressData`
- `ImportProgressData`
- browser callbacks

from the new path.

## Keep legacy GIF path

The old file/progress path must still compile and work because BbxBrow and ordinary callers have not migrated yet.

## Tests

Test:

- ordinary GIF
- interlaced GIF
- header split across buffers
- input one byte at a time
- truncated GIF
- malformed GIF
- early Destroy
- wrong MIME but GIF signature
- partial output

## Completion criteria

- GIF works through Begin / Advance / Destroy.
- Legacy GIF still works.
- JPEG and PNG remain legacy-only.

**Do not begin Step 5.**

---

# Step 5 — Make IJG JPEG source input suspendable

## Goal

Create a JPEG input mechanism suitable for Advance.

Do not migrate the complete JPEG importer yet.

## Scope

The current IJG JPEG path assumes a blocking/file-style source.

Implement a new raw-memory source manager that:

- accepts supplied bytes
- never calls BbxBrow
- never waits for input
- supports JPEG suspension
- preserves decoder state across calls
- does not treat suspension as an error
- does not retain an unsafe caller buffer pointer

If retained bytes are required, copy only the minimum required bytes into decoder-owned state.

Handle `JPEG_SUSPENDED` correctly wherever the IJG API permits suspension.

Do not delete the old source manager yet.

Do not change browser behavior yet.

## Completion criteria

- New suspendable JPEG source manager compiles.
- Legacy JPEG import still works.
- No public JPEG Advance decoding is required yet.

**Do not begin Step 6.**

---

# Step 6 — Migrate IJG JPEG to Begin / Advance / Destroy

## Goal

Make the normal IJG JPEG importer incremental.

## Persistent phases

Represent the JPEG lifecycle explicitly, for example:

```text
read header
report HEADER_READY
configure output
start decompression
decode bounded scanlines
finish decompression
DONE
```

The exact state representation is private.

## Suspension

Every IJG operation that can suspend must return control cleanly.

Suspension means:

```text
MGAS_NEED_DATA
```

not decoder failure.

## Header handling

When dimensions become known:

```text
MGAE_HEADER_READY
```

must be returned before expensive complete-output work where practical.

## Output

Create/update a stable HugeBitmap.

Return changed scanline ranges via:

```text
MGAE_BITMAP_CHANGED
```

Do not perform browser/UI throttling.

## Bounded work

Do not decode an arbitrarily large image in one `Advance()` call merely because all bytes are available.

Return `MGAS_YIELD` after a bounded amount of scanline work.

## Completion criteria

- IJG JPEG works through Advance.
- Source starvation cleanly produces NEED_DATA.
- Legacy JPEG path remains available.
- Stable output rules are followed.

**Do not begin Step 7.**

---

# Step 7 — Migrate Fjpeg to Begin / Advance / Destroy

## Goal

Give the Fjpeg variant the same public incremental behavior.

## Scope

Inspect Fjpeg independently.

Do not assume the IJG implementation can simply be copied.

Implement equivalent:

- resumable source input
- persistent decoder state
- header-ready event
- bounded scanline processing
- NEED_DATA handling
- stable HugeBitmap output
- correct cleanup

Preserve intentional Fjpeg limitations.

The public Begin / Advance / Destroy contract must not change depending on the JPEG backend.

## Completion criteria

- Fjpeg build supports the same Advance API.
- EC and non-EC builds pass.
- Legacy Fjpeg behavior remains available during migration.

**Do not begin Step 8.**

---

# Step 8 — Refactor PNG parser into incremental persistent state

## Goal

Prepare PNG for arbitrary raw-byte input.

Do not remove the old PNG file importer yet.

## Persistent state

Create persistent state covering:

- PNG signature
- partial chunk headers
- chunk type
- chunk length
- IHDR
- PLTE and relevant metadata
- IDAT position/state
- zlib state
- filter state
- previous row
- current row
- output conversion state

The parser must suspend at any byte boundary.

It must not require:

- complete file
- complete PNG chunk
- complete IDAT block
- file seek
- decoder-visible rewind

## Header event

After IHDR has been validated and dimensions are known:

```text
MGAE_HEADER_READY
```

must become available.

Avoid allocating the complete output before the caller has had an opportunity to reject the image.

## Completion criteria

- Incremental PNG parser exists.
- Existing PNG file importer still works.
- Arbitrary chunk fragmentation is handled internally.

**Do not begin Step 9.**

---

# Step 9 — Migrate PNG to Begin / Advance / Destroy

## Goal

Complete Advance support for all primary image formats.

## Scope

Connect the persistent PNG parser to the generic ImpGraph session.

Return:

- NEED_DATA when required
- YIELD after bounded work
- HEADER_READY after IHDR
- BITMAP_CHANGED for scanline modifications
- DONE / DONE_PARTIAL / ERROR appropriately

Test:

- palette PNG
- grayscale PNG
- RGB PNG
- alpha handling
- IDAT split across arbitrary buffers
- chunk header split across buffers
- input one byte at a time
- truncated PNG
- malformed PNG
- early Destroy
- allocation failure

## Completion criteria

- GIF, IJG JPEG, Fjpeg, and PNG all support Begin / Advance / Destroy.
- Legacy interface still exists temporarily.

**Do not begin Step 10.**

---

# Step 10 — Define and enforce stable HugeBitmap ownership

## Goal

Remove ambiguity about who frees progressive output.

## Required invariant

Before output has been exposed:

```text
ImpGraph owns it.
```

The first time `MGA_output` is returned nonzero:

```text
caller receives disposal responsibility.
```

ImpGraph may continue modifying the same HugeBitmap while the session exists.

The caller must not free it while the session exists.

After exposure, ImpGraph must never free that output chain.

## Stable handle

After first exposure:

```text
MGA_output
```

must remain the same VMBlockHandle until the decoder session ends.

Allowed:

```text
Advance #4 -> bitmap 0042
Advance #5 -> bitmap 0042
Advance #6 -> bitmap 0042
DONE       -> bitmap 0042
```

Forbidden:

```text
Advance    -> bitmap 0042
DONE       -> bitmap 0087
```

## Compaction

Do not allow final `GrCompactBitmap()` replacement to violate this invariant.

For non-progressive file imports, later convenience code may compact after the decoder has finished and before exposing the result to the application.

For progressive imports, retain stable output.

Remove ownership assumptions from the new Advance path.

Do not yet delete `FreeViaProgress()` if the legacy path still needs it.

## Completion criteria

- All Advance codecs obey one ownership model.
- Stable-output assertions exist.
- Error/Destroy paths obey the model.

**Do not begin Step 11.**

---

# Step 11 — Reimplement ordinary file import using Advance

## Goal

Move source-file reading above ImpGraph.

Applications such as PicAlbum and GPCMail should retain a simple API.

## Convenience path

Reimplement the generic file-import layer as:

```text
select driver
Begin
open file

read input chunk
Advance
discard MGA_consumed
repeat

Advance(... END_OF_DATA ...)
Destroy
close file

optional final compaction
return graphic
```

ImpGraph itself must no longer need the filename for the new decoder path.

The high-level application API may remain filename-based.

## File import does not need progress

Ignore intermediate bitmap-change events in the ordinary convenience path.

The wrapper owns the exposed output until returning it to its caller.

Because no external caller has seen it yet, optional final bitmap replacement/compaction is allowed here after decoder completion.

## Completion criteria

- PicAlbum/GPCMail-style ordinary imports work through Advance internally.
- Application-facing API remains simple.
- Rendered output matches the old importer.

**Do not begin Step 12.**

---

# Step 12 — Reimplement generic image probing using Advance

## Goal

Make probing a consequence of normal decoding rather than a separate decoder architecture.

## Convenience probe

Temporarily retain `ToolsProbeGraphicByDriver()` if callers still need it.

Implement it internally as:

```text
Begin
read bounded input prefix
Advance
repeat until:
    HEADER_READY
    byte limit
    ERROR
Destroy
```

Do not use the old MIME driver probe implementation for migrated callers.

The decoder must not be restarted after probing in the BbxBrow path later.

## Completion criteria

- Generic probing works through Begin / Advance.
- The old probe driver entry may still exist only for not-yet-migrated callers.

**Do not begin Step 13.**

---

# Step 13 — Introduce BbxBrowImageJob

## Goal

Create the browser-private state object that replaces mixed load/import progress state.

## Allocation

Rename/extend the existing image request LMem chunk into:

```text
BbxBrowImageJob
```

Continue allocating jobs from the existing `G_allocBlock`.

Do not allocate one MemHandle for every image job.

## Job owns browser state

Include browser-private information such as:

- text object
- image index
- NameToken
- MIME hint/value
- filename if still required by fetch fallback
- display-progress policy
- maximum probe pixels
- maximum probe bytes
- probe/admission state
- ObjCache token/state
- fetch slot
- import worker index
- active decoder session
- exposed bitmap
- lifecycle state

## Lifetime

Use the job optr as stable identity.

Never retain a raw LMem pointer across an unlock.

Always:

```text
lock G_allocBlock
re-dereference chunk
use job
unlock
```

The job must remain alive while either transport or import processing may refer to its identity.

Do not change Wmg3Http's transport API yet.

## Completion criteria

- BbxBrowImageJob exists.
- Current browser path compiles.
- Legacy loading may still use old callback structures temporarily.

**Do not begin Step 14.**

---

# Step 14 — Switch the BbxBrow import worker to Advance

## Goal

Make BbxBrow decode images using the new raw-byte API.

Keep the existing byte producer/stream implementation temporarily.

## Import worker loop

The worker should conceptually become:

```text
get available BbxBrow bytes

Advance(
    decoder,
    bytes,
    byteCount,
    EOF flag)

consume MGA_consumed

handle:
    HEADER_READY
    BITMAP_CHANGED
    OUTPUT_READY
    NEED_DATA
    YIELD
    DONE
    DONE_PARTIAL
    ERROR
```

## Important separation

ImpGraph does not:

- wait on fetch semaphores
- request bytes
- publish browser progress
- touch ObjCache
- know the image job

BbxBrow owns all of that.

## Need-data handling

When Advance returns `MGAS_NEED_DATA`:

- release any locked buffer state;
- wait/sleep at the BbxBrow import-worker level;
- resume when producer bytes arrive.

ImpGraph itself must not wait.

## Completion criteria

- BbxBrow decodes using Advance.
- Existing Wmg3Http delivery mechanism can still feed the browser's byte storage.
- Old ImpGraph callbacks are no longer required by BbxBrow decoding.

**Do not begin Step 15.**

---

# Step 15 — Move BbxBrow progress display entirely outside ImpGraph

## Goal

Make bitmap updates plain decoder facts rather than callbacks.

## On `MGAE_BITMAP_CHANGED`

BbxBrow decides whether to:

- ignore the update for now
- coalesce it
- create/update ObjCache state
- queue a UI update
- redraw the text object
- wait for a larger slice
- suppress intermediate display for small images

ImpGraph must not contain browser-oriented progress thresholds.

Queued UI records must contain copied data needed by the UI.

They must not require the `BbxBrowImageJob` to still exist by the time the UI event executes.

## Remove browser dependence on ImportProgressData

BbxBrow's Advance path must no longer use:

```text
ImportProgressData
IPD_textObj
IPD_nameT
IPD_cacheItem
IPD_loadProgressDataP
```

The legacy structures may remain elsewhere until final cleanup.

## Completion criteria

- Browser progressive drawing works solely from Advance results.
- No ImpGraph progress callback is used by BbxBrow.

**Do not begin Step 16.**

---

# Step 16 — Move intelligent image admission to HEADER_READY

## Goal

Replace the separate BbxBrow probe/import cycle.

## Behavior

When:

```text
MGAE_HEADER_READY
```

arrives, BbxBrow checks its private job policy:

- width
- height
- maximum pixels
- bytes received so far
- maximum speculative probe bytes
- browser display policy

If accepted:

```text
continue advancing the same decoder session
```

If deferred/rejected:

```text
Destroy decoder
mark job deferred
perform browser/transport completion behavior
```

Do not:

- rewind
- restart decoder
- call separate graphic probe
- write probe decisions into shared progress structures

## Completion criteria

- BbxBrow normal network image path no longer calls `ToolsProbeGraphicByDriver()`.
- Probe and import are stages of the same decoder session.

**Do not begin Step 17.**

---

# Step 17 — Simplify the BbxBrow memory stream into a byte queue

## Goal

Remove pseudo-file functionality that only existed because ImpGraph pulled data through callbacks.

## New requirement

BbxBrow only needs:

```text
producer writes bytes
consumer obtains contiguous bytes
consumer reports MGA_consumed
queue discards consumed bytes
EOF indication
cancellation
```

Remove decoder-facing concepts such as:

- peek
- pre-read
- reset
- rewind-to-prefix
- flush-first

No ImpGraph callback should reference the byte queue.

## Storage

Do not combine this step with replacement by the GEOS native stream driver.

Keep the existing private storage first, but simplify it.

The previous reason for requiring retained-prefix rewind semantics no longer exists. Native-stream replacement can be evaluated separately later.

## Completion criteria

- Byte queue supports partial consumption correctly.
- Arbitrary Advance fragmentation works.
- No decoder-specific pseudo-file operation remains.

**Do not begin Step 18.**

---

# Step 18 — Make fetching while importing unconditional

## Goal

Apply the concurrency cleanup after Advance is stable.

## Remove

- `ALLOW_FETCH_WHILE_IMPORTING`
- `G_fetchWhileImport`
- `fetchWhileImport` INI option
- fetch-child waiting for image import completion
- per-image import completion semaphore where no longer required
- old `G_importActive` policy bookkeeping where slot ownership replaces it

## Required behavior

Fetch children never wait for an image import to finish.

When an incremental import slot is available:

```text
download + decode concurrently
```

When no incremental slot is available:

```text
continue downloading file
do not block fetch child
after completion queue ordinary file import
```

This is the bounded-resource fallback.

## Shutdown

Replace busy waiting with an event/semaphore-based shutdown completion mechanism.

## Completion criteria

- Fetching while importing is the only mode.
- Saturated import slots do not block later downloads.
- Shutdown does not busy-wait.

**Do not begin Step 19.**

---

# Step 19 — Neutralize the Wmg3Http transport interface

## Goal

Make Wmg3Http know only HTTP/transport concepts.

## Final Wmg3Http responsibilities

Wmg3Http may notify BbxBrow about:

- response headers
- MIME/content type
- known content length
- raw response bytes
- response completion
- transport error
- generic continue/stop/reject result if required

It must not know:

- image dimensions
- image probe limits
- image probe result
- progressive display policy
- ObjCache
- ImpGraph state
- browser image admission rules

## Remove LoadProgressData

Replace the mixed `LoadProgressData` transport contract with a small transport-specific interface.

This transport callback is private to URL/BbxBrow architecture.

It is unrelated to the ImpGraph decoder API.

Bump the URL-driver major protocol because compatibility is intentionally dropped.

Remove obsolete URL return/result flags that only existed to expose image-progress/probe state.

## Completion criteria

- Wmg3Http is transport-only.
- `LoadProgressData` is no longer required by BbxBrow's new path.
- Other URL drivers rebuild against the new transport contract.

**Do not begin Step 20.**

---

# Step 20 — Remove legacy ImpGraph progress callbacks and old graphic entries

## Goal

Delete the old importer architecture after all callers have migrated.

## Verify first

Repository-wide confirm that no active caller still uses:

- old graphic entry
- graphic-ex entry
- graphic-probe entry
- ImportProgressData
- load-progress access from ImpGraph codecs

## Codec-library compatibility boundary

This step removes only obsolete ImpGraph driver entries, adapters, and
progress/load integration.

Do not remove or change the existing exported APIs or ordinary file-import
behavior of:

- `ijgjpeg`
- `fjpeg`
- `pnglib`
- `giflib`

Incremental support must remain internal to ImpGraph or use additive
codec-library interfaces. Existing direct codec-library consumers, including
Graphvwr, must continue to compile and work unchanged.

## Remove

- `ImportProgressData`
- `_ImportProgressParams_`
- `proc_ImportProgressCallback`
- `MIME_ENTRY_GRAPHIC`
- `MIME_ENTRY_GRAPHIC_EX`
- `MIME_ENTRY_GRAPHIC_PROBE`
- old forwarding wrappers
- `FreeViaProgress()`
- GIF import-progress callback code
- JPEG import-progress callback code
- Fjpeg import-progress callback code
- PNG import-progress callback code
- ImpGraph `LoadProgressData` usage
- old graphic-probe driver implementations
- obsolete ImpGraph-only JPEG load-progress source path
- obsolete ImpGraph-only GIF load-progress adapter path
- obsolete ImpGraph-only PNG load-progress adapter path

Do not interpret these removals as permission to delete or alter legacy
file-based entry points exported by the codec libraries.

Do not reuse removed selector numbers immediately.

The graphic decoder driver API is now only:

```text
GRAPHIC_BEGIN
GRAPHIC_ADVANCE
GRAPHIC_DESTROY
```

## Completion criteria

- ImpGraph has no load callback.
- ImpGraph has no progress callback.
- ImpGraph has no separate probe entry.
- Existing `ijgjpeg`, `fjpeg`, `pnglib`, and `giflib` consumers require no
  source changes.

**Do not begin Step 21.**

---

# Step 21 — Remove PROGRESS_DISPLAY and remaining compatibility code

## Goal

Complete the original cleanup.

## Repository-wide search

Search for:

```text
PROGRESS_DISPLAY
LoadProgressData
ImportProgressData
LPD_
IPD_
MIME_ENTRY_GRAPHIC_EX
MIME_ENTRY_GRAPHIC_PROBE
ALLOW_FETCH_WHILE_IMPORTING
G_fetchWhileImport
G_importActive
URL_RET_PROGRESS
URL_RET_PROGRESS_ABORT
URL_RET_IMAGE_DEFERRED
URB_RF_IMAGE_PROBED
```

Remove obsolete:

- compile-time branches
- structures
- fields
- callback typedefs
- globals
- messages
- compatibility macros
- stream rewind logic
- import request blocks
- comments describing the old architecture
- unused IMPORTWK/G_importWorkFile setup if confirmed dead

Do not merely define `PROGRESS_DISPLAY` permanently ON.

Delete the obsolete paths.

## Completion criteria

There is no affected `PROGRESS_DISPLAY=OFF` implementation because there is no ImpGraph progress mechanism anymore.

**Do not begin Step 22.**

---

# Step 22 — Final ownership, failure, and shutdown audit

## Goal

Audit the new architecture without making unrelated design changes.

## Verify decoder ownership

### Output never exposed + error

ImpGraph frees its private output during Destroy.

### Output exposed + success

Caller owns the bitmap.

Destroy releases decoder state only.

### Output exposed + cancellation

Destroy stops modification.

BbxBrow decides whether to retain or free partial output.

### Output exposed + malformed source

ImpGraph must not silently free the exposed chain.

### Ordinary file import

The Tools wrapper owns output until returning it to the application and may compact it after decoder completion.

## Verify job ownership

Every BbxBrowImageJob must have exactly one terminal cleanup path.

Test:

- success
- deferred image
- fetch failure
- decoder error
- cancellation before decoder creation
- cancellation after decoder creation
- cancellation after output exposure
- ordinary file fallback
- shutdown during fetch
- shutdown during import

## Verify memory

No leaked:

- decoder session MemHandle
- BbxBrowImageJob chunk
- stream slot
- NameToken
- ObjCache reference
- HugeBitmap VM chain
- temporary file/import block

## Completion criteria

- Ownership is explicit.
- No double frees.
- No orphaned chains.
- No stale job references.
- No shutdown busy-wait.

**Do not begin Step 23.**

---

# Step 23 — Final build and behavioral validation

## Build all affected components

Build EC and non-EC versions of at least:

- BbxBrow
- BbxBrow AB variant
- ImpGraph
- ImpGraph FJPEG variant
- Ijgjpeg
- Fjpeg
- Wmg3Http
- Wmg3Ftp
- Wmg3Ext
- ImpDoc
- PicAlbum
- GPCMail

Use the repository's existing Installed workflow and normal:

```text
pmake -L 4 full
```

process.

Regenerate dependencies only when required.

## Functional validation

Test:

- local GIF
- local JPEG
- local PNG
- correct MIME
- missing MIME
- empty MIME
- incorrect MIME
- signature one byte at a time
- GIF interlacing
- JPEG suspension
- progressive JPEG where supported
- Fjpeg
- PNG arbitrary chunk fragmentation
- PNG arbitrary IDAT fragmentation
- accepted intelligent image
- deferred intelligent image
- probe-byte limit
- abort before header
- abort after header
- abort after output exposure
- malformed input after output exposure
- truncated image
- small image
- ObjCache enabled
- ObjCache disabled
- concurrent fetch children
- all incremental import slots occupied
- ordinary-file fallback
- shutdown with queued jobs
- shutdown with active imports
- allocation failure
- stream/queue capacity boundary

## Swat validation

Verify:

- decoder handle lifetime
- job optr lifetime
- G_allocBlock lifetime
- input queue ownership
- `MGA_consumed`
- stable output VMBlockHandle
- import-slot ownership
- fetch-slot ownership
- shutdown semaphore/event balance
- ObjCache reference counts
- HugeBitmap VM chains
- decoder sessions

Useful breakpoint areas include:

```text
MimeDrvGraphicBegin
MimeDrvGraphicAdvance
MimeDrvGraphicDestroy
ImpGIFProcess
JPEG suspension/source manager
JPEG scanline output
PNG IHDR completion
PNG IDAT processing
BbxBrow HEADER_READY handling
BbxBrow BITMAP_CHANGED handling
BbxBrowImageJob terminal cleanup
```

## Final acceptance criteria

The project is finished when:

- ImpGraph accepts raw bytes rather than loading source files itself.
- ImpGraph never waits for source data.
- ImpGraph has no load callback.
- ImpGraph has no progress callback.
- ImpGraph has no browser state.
- `LoadProgressData` is gone from image-import architecture.
- `ImportProgressData` is gone.
- `PROGRESS_DISPLAY` is gone from this subsystem.
- the separate graphic-probe driver API is gone.
- probing and decoding use the same decoder session.
- BbxBrow owns all progress/display/cache/admission policy.
- Wmg3Http knows only transport state.
- ordinary applications retain a simple file-import convenience API.
- GIF supports Advance.
- IJG JPEG supports Advance.
- Fjpeg supports Advance.
- PNG supports Advance.
- arbitrary input fragmentation produces the same image as file import.
- exposed HugeBitmap handles remain stable.
- cancellation requires no asynchronous status pointer inside ImpGraph.
- fetching while importing is unconditional.
- import-slot saturation falls back to completed-file import without blocking fetches.
- shutdown contains no busy wait.
- no bitmap ownership is inferred from callback history.
- no jobs, decoder sessions, cache references, stream slots, or VM chains leak.
