# BbxBrow / ImpGraph Maintainability and Decoupling Plan

## Goal

Make ImpGraph easier to maintain and remove browser-specific state from its
implementation without replacing the current synchronous import design.

ImpGraph remains a blocking, file-oriented graphics importer. Progressive GIF
and JPEG imports may continue to pull bytes from BbxBrow while the download is
in progress. ImpGraph receives those bytes through a generic reader callback
instead of through `LoadProgressData`.

The final dependency direction is:

```text
Wmg3Http <-> BbxBrow transport state
                 |
                 | generic blocking byte reader
                 | generic decoder progress observer
                 v
              ImpGraph
                 |
                 v
        GIF / IJG JPEG / Fjpeg / PNG
```

ImpGraph core code must not know about:

- BbxBrow objects
- `LoadProgressData`
- `ImportProgressData`
- NameTokens
- ObjCache
- fetch threads or fetch slots
- browser semaphores
- browser progress-display policy
- browser image-admission policy

Browser-specific compatibility code may temporarily exist behind one clearly
identified legacy boundary in each geode that owns an existing ABI export.
New core and codec paths must not use those boundaries.

## Non-goals

This project does not introduce:

- Begin / Advance / Destroy decoder sessions
- a push decoder API
- an asynchronous ImpGraph API
- a new BbxBrow input queue
- unconditional fetch/import concurrency
- a Wmg3Http protocol redesign
- incremental PNG decoding
- breaking changes to exported `ijgjpeg`, `fjpeg`, `pnglib`, or `giflib` APIs
- removal or renumbering of existing MIME driver selectors

Animated GIF behavior and ordinary file imports must remain compatible.

## Design rules

The new API is additive. Existing callers continue to use:

```text
MIME_ENTRY_GRAPHIC
MIME_ENTRY_GRAPHIC_EX
MIME_ENTRY_GRAPHIC_PROBE
```

Add one new struct-based entry after all existing exports. Do not remove old
exports or shift their ordinals. Increase ImpGraph from protocol 4.3 to 4.4 by
the normal `.gp` export process, but leave the global
`MIME_DRV_PROTOMINOR` at 0 so older MIME drivers still load. A caller must
verify protocol 4.4 or later before requesting the new entry.

The new entry remains synchronous. All parameter, source, observer, and
callback-context storage supplied by the caller must remain valid until the
entry returns. ImpGraph must not retain any of it after returning.

Callbacks are cross-geode callbacks. Store callback pointers as
`void _pascal *` and invoke them through `ProcCallFixedOrMovable_pascal` using
the corresponding `pcfm_*` typedef. The new driver entry also has both
`entry_*` and `pcfm_*` typedefs.

Use a `dword` callback cookie. BbxBrow can therefore pass a stable optr instead
of a movable LMem pointer. A browser callback may lock `G_allocBlock` only long
enough to re-dereference the job and copy stable identifiers or state. It must
unlock the block before waiting for source data or acquiring a source
semaphore. If it must update the job afterward, it re-locks the block and
re-dereferences the optr. It never retains an LMem pointer across the unlock.

## New generic API

Add public types with names consistent with the surrounding MIME driver API.
The exact prefixes may be adjusted while implementing, but the contract must
remain the same.

### Source reader

```c
typedef enum {
    MGRS_DATA,
    MGRS_EOF,
    MGRS_ERROR,
    MGRS_ABORT
} MimeGraphicReadStatus;

typedef MimeGraphicReadStatus _pascal
proc_MimeGraphicRead(
    dword context,
    byte *bufferP,
    word bufferSize,
    word *bytesReadP);

typedef MimeGraphicReadStatus _pascal
pcfm_MimeGraphicRead(
    dword context,
    byte *bufferP,
    word bufferSize,
    word *bytesReadP,
    void *pf);

typedef enum {
    MGSO_MARK,
    MGSO_RESET,
    MGSO_COMMIT
} MimeGraphicSourceOperation;

typedef Boolean _pascal
proc_MimeGraphicSourceControl(
    dword context,
    MimeGraphicSourceOperation operation);

typedef Boolean _pascal
pcfm_MimeGraphicSourceControl(
    dword context,
    MimeGraphicSourceOperation operation,
    void *pf);

typedef struct {
    void _pascal *MGS_read;
    void _pascal *MGS_control;
    dword MGS_context;
} MimeGraphicSource;
```

Reader contract:

- `MGRS_DATA` returns one or more bytes in `*bytesReadP`.
- Short reads are valid.
- `MGRS_EOF`, `MGRS_ERROR`, and `MGRS_ABORT` return zero bytes.
- The reader may block until data, EOF, error, or cancellation.
- ImpGraph never calls the reader with a zero buffer size.
- ImpGraph never retains `bufferP` after the callback returns.
- The source is sequential and has no arbitrary seek or browser-specific
  operations.
- `MGSO_MARK` starts the one codec-selection checkpoint before source bytes are
  consumed.
- `MGSO_RESET` restores the logical read position to that checkpoint. It may be
  used more than once before commit.
- `MGSO_COMMIT` ends the checkpoint at the current logical position and permits
  retained bytes to be released.
- Mark, reset, and commit preserve the same byte sequence and terminal status
  that an uninterrupted read would have produced.
- A control failure is a source error. ImpGraph does not continue with another
  codec after such a failure.
- ImpGraph performs no checkpoint operation after commit.

ImpGraph starts the checkpoint before signature detection. It also owns a small
prefix buffer for signature handling. The checkpoint is only for codec
selection and Fjpeg-to-IJG fallback, not general seeking or decoder sessions.

The generic streaming source initially supports the formats that already have
progressive browser paths: GIF, IJG JPEG, and Fjpeg. PNG continues to use the
completed source file. If a streaming source is identified as PNG, ImpGraph
returns a specific `MGE_REQUIRES_FILE` result so BbxBrow can finish the download
and queue an ordinary file import.

### Progress observer

```c
typedef WordFlags MimeGraphicProgressEvents;

#define MGPE_HEADER_READY       0x0001
#define MGPE_OUTPUT_READY       0x0002
#define MGPE_BITMAP_CHANGED     0x0004
#define MGPE_OUTPUT_PROVISIONAL 0x0008

typedef struct {
    MimeGraphicProgressEvents MGP_events;
    VMFileHandle MGP_vmFile;
    VMBlockHandle MGP_bitmap;
    ImageAdditionalData MGP_iad;
    word MGP_firstLine;
    word MGP_lastLine;
} MimeGraphicProgress;

typedef Boolean _pascal
proc_MimeGraphicObserver(
    dword context,
    const MimeGraphicProgress *progressP);

typedef Boolean _pascal
pcfm_MimeGraphicObserver(
    dword context,
    const MimeGraphicProgress *progressP,
    void *pf);

typedef struct {
    void _pascal *MGO_callback;
    dword MGO_context;
} MimeGraphicObserver;
```

Observer contract:

- The observer receives decoder facts, not browser policy requests.
- `MGPE_HEADER_READY` is sent once dimensions and required header information
  are known, before expensive output allocation where practical.
- Returning `FALSE` requests a synchronous abort.
- `MGPE_OUTPUT_READY` is sent once when a displayable output bitmap first
  exists.
- `MGPE_OUTPUT_PROVISIONAL` is valid only together with
  `MGPE_OUTPUT_READY`. It means the reported bitmap may be a preview rather
  than the final returned object.
- JPEG and GIF imports using `MIME_GREX_NO_ANIMATIONS` never report provisional
  output. Their reported output handle is the final output handle.
- An animation-capable streamed GIF reports its first displayable bitmap with
  `MGPE_OUTPUT_READY | MGPE_OUTPUT_PROVISIONAL`, because animation status is
  not known until the stream reaches sufficient input.
- `MGPE_BITMAP_CHANGED` follows or accompanies `MGPE_OUTPUT_READY` and
  identifies a conservative changed scanline range. The range fields are
  valid only for this event, are zero-based and inclusive, and satisfy
  `0 <= MGP_firstLine <= MGP_lastLine < MGP_iad.IAD_size.XYS_height`.
- ImpGraph clamps legacy codec ranges to the image bounds and suppresses an
  empty range rather than reporting invalid line numbers.
- `progressP` is valid only during the callback. A recipient queues copied
  values, never the pointer.
- The bitmap is borrowed during the import. The observer must not free it.
- Ownership is decided when the import entry returns.

ImpGraph performs no redraw throttling, ObjCache work, text-object messaging,
or image-admission policy.

### Import parameters

```c
typedef enum {
    MGE_NONE = 0,
    MGE_INVALID_PARAMETER = 1,
    MGE_UNSUPPORTED_FORMAT = 2,
    MGE_REQUIRES_FILE = 3,
    MGE_NO_MEMORY = 4,
    MGE_MALFORMED_INPUT = 5,
    MGE_SOURCE_ERROR = 6,
    MGE_CANCELLED = 7,
    MGE_IMPORT_ERROR = 8
} MimeGraphicError;

typedef struct {
    word MGIP_size;

    TCHAR *MGIP_mimeHint;
    TCHAR *MGIP_file;
    VMFileHandle MGIP_vmFile;
    MimeRes MGIP_resolution;
    AllocWatcherHandle MGIP_watcher;
    MimeStatus *MGIP_statusP;
    dword MGIP_flags;

    MimeGraphicSource *MGIP_sourceP;
    MimeGraphicObserver *MGIP_observerP;

    VMBlockHandle MGIP_output;
    VMBlockHandle MGIP_preview;
    ImageAdditionalData MGIP_iad;
    dword MGIP_usedMem;
    MimeGraphicError MGIP_error;
} MimeGraphicImportParams;

#define MIME_GRAPHIC_IMPORT_PARAMS_V1_SIZE \
    (offsetof(MimeGraphicImportParams, MGIP_error) + \
     sizeof(MimeGraphicError))
```

Keep the version-1 size anchored to the end of `MGIP_error` when later fields
are appended; do not redefine it as the future structure's full size.

Add one entry with the normal exported and fixed-or-movable typedefs:

```c
typedef VMBlockHandle _pascal _export
entry_MimeDrvGraphicImport(MimeGraphicImportParams *paramsP);

typedef VMBlockHandle _pascal
pcfm_MimeDrvGraphicImport(
    MimeGraphicImportParams *paramsP,
    void *pf);
```

Parameter contract:

- `paramsP` is required.
- `MGIP_size` must be at least
  `MIME_GRAPHIC_IMPORT_PARAMS_V1_SIZE`. If it is smaller, the entry returns
  `NullHandle` without accessing any member after `MGIP_size`. A larger size
  is accepted; ImpGraph accesses only fields it knows whose complete storage
  is present within `MGIP_size`. Later versions append fields only.
- `MGIP_mimeHint` is optional and is only a hint.
- `MGIP_vmFile`, `MGIP_watcher`, and `MGIP_statusP` are required and valid for
  the whole call. `MGIP_resolution` must be a defined `MimeRes` value.
- `MGIP_file` is required when `MGIP_sourceP` is null and is ignored when a
  source is supplied.
- `MGIP_sourceP` selects generic streaming input when non-null. Its read and
  control callbacks are both required. The source descriptor and its callback
  context remain valid for the whole call.
- `MGIP_observerP` is optional.
- If supplied, its callback is required, and the observer descriptor and its
  callback context remain valid for the whole call.
- `MGIP_flags` carries the existing graphic-ex options.
- ImpGraph initializes every known output field present in `MGIP_size` before
  doing work.
- The returned handle and `MGIP_output` are identical.
- `MGIP_preview` is nonzero only when provisional output was reported and the
  final `MGIP_output` is a different VM chain.
- `MGIP_iad` describes `MGIP_output`; preview metadata is supplied by the
  observer event.
- `MGIP_usedMem` counts every distinct returned VM chain exactly once,
  including `MGIP_preview` when nonzero.
- `MGE_NONE` means complete success. A recognized format that cannot be
  decoded is malformed; input with no recognized signature is unsupported.
  `MGRS_ERROR` maps to `MGE_SOURCE_ERROR`. `MGRS_ABORT`, observer rejection,
  or `MIME_STATUS_ABORT` maps to `MGE_CANCELLED`. Allocation refusal maps to
  `MGE_NO_MEMORY`. An otherwise unclassifiable codec failure maps to
  `MGE_IMPORT_ERROR`.
- `MGE_REQUIRES_FILE` returns no output and requests the completed-file path.
- A usable partial output may accompany `MGE_CANCELLED`, `MGE_SOURCE_ERROR`,
  or `MGE_MALFORMED_INPUT`; fatal errors before usable output return no chain.
- A returned partial bitmap has `IAD_completeGraphic == FALSE`.

## Ownership

ImpGraph owns every output and preview VM chain until the import entry returns.

The progress observer only borrows the bitmap. BbxBrow may prepare cache and UI
state while importing, but it must not free or replace the VM chain before the
entry returns. A provisional preview keeps the same valid VM chain until that
return, although the decoder may continue updating its contents.

On complete success, `MGIP_output` belongs to the caller. If `MGIP_preview` is
nonzero, it is a separate caller-owned chain. The final animation must not
reference `MGIP_preview`, so the caller can release the preview independently.

For an animation-capable streamed GIF:

- if the GIF is single-frame, `MGIP_output` is the same handle reported as the
  provisional preview and `MGIP_preview` is zero;
- if the GIF is animated, `MGIP_output` is the final animation root and
  `MGIP_preview` is the independently owned preview chain;
- if cancellation, source failure, truncation, or malformed trailing input
  occurs after a preview exists but before a usable final object exists, the
  preview is promoted to `MGIP_output`, `MGIP_preview` is zero, and
  `IAD_completeGraphic` is `FALSE`.

After output has been reported, cancellation, source failure, or malformed
trailing input must return the usable partial bitmap with
`IAD_completeGraphic == FALSE`. The caller then decides whether to retain or
free it. ImpGraph must not free an output that it has reported to the observer
and then return a null handle.

Before output has been reported, an error leaves cleanup entirely to ImpGraph
and returns null `MGIP_output` and `MGIP_preview` handles.

Ordinary file import may retain the existing final compaction behavior before
returning the bitmap. Non-provisional progressive output must not be replaced
after `MGPE_OUTPUT_READY` because the observer may already have copied its
handle. Provisional GIF output follows the explicit preview handoff above.

Animated GIF output retains its current file-import behavior. Do not force an
animation into the progressive single-HugeBitmap ownership rules. The
provisional preview contract formalizes the new streaming path only. Preserve
the existing no-animation option used by callers that require a plain bitmap.

## Implementation steps

Do not renumber these steps. Implement and build one step at a time.

After each step:

- build every component changed by that step;
- build EC and non-EC variants where relevant;
- fix issues caused by the step before continuing;
- preserve existing line endings;
- review `git diff --ignore-space-at-eol`;
- do not perform unrelated cleanup.

# Step 1 - Record the baseline

Search the complete repository for:

- all MIME graphic selectors and callers
- `LoadProgressData`
- `ImportProgressData`
- `PROGRESS_DISPLAY`
- `ImpGIFCreate` and `ImpGIFProcess`
- IJG JPEG source managers
- Fjpeg input handling
- PNG import and progress handling
- `FreeViaProgress`

Record which callers require animated GIFs and which pass
`MIME_GREX_NO_ANIMATIONS`.

Build current EC and non-EC variants of ImpGraph and BbxBrow. Also establish
the relevant IJG and Fjpeg variant builds.

Completion criteria:

- No behavior change.
- Caller and ABI inventory is recorded.
- Baseline builds pass or pre-existing failures are recorded.

# Step 2 - Add the struct-based driver entry

Add the generic public types and the single new MIME driver selector.

Append the new export after the existing ImpGraph exports. Do not delete,
reorder, or repurpose selectors 0 through 4. Set the ImpGraph protocol to 4.4
and add a helper or explicit 4.4-or-later check for new callers. Do not raise
the shared minimum protocol used to load older MIME drivers.

Implement a skeleton entry that:

- validates `MGIP_size`, required parameters, and resolution without reading
  beyond the caller's declared structure size;
- initializes all output fields;
- reports unsupported until the internal core is connected.

Keep all old entries unchanged.

Completion criteria:

- Old callers still build and run through the old entries.
- The new entry can be found only after a protocol/capability check.
- Public `proc_*`, `pcfm_*`, and entry typedefs compile for fixed and movable
  callback targets.
- Null required parameters, undersized structures, and larger compatible
  structures follow the documented contract.
- EC and non-EC ImpGraph builds pass.

# Step 3 - Introduce the private ImpGraph import context

Create one private `ImpGraphImportContext` containing normalized inputs,
outputs, ownership state, selected codec, source state, observer state, a
dispatch mode, and the existing shared `ImpBmpParams` data.

Use two private dispatch modes:

- the new entry uses signature-first selection and treats MIME as a hint;
- the old graphic, graphic-ex, and probe wrappers preserve their existing
  MIME-driven dispatch and codec fallback order.

Do not let conversion to a shared coordinator change which codec a legacy
caller reaches or how an unrecognized legacy MIME value is handled.

Implement one internal coordinator:

```c
static VMBlockHandle
ImpGraphImport(ImpGraphImportContext *contextP);
```

The new public entry initializes the context and calls this coordinator.

Convert `MimeDrvGraphic()` and `MimeDrvGraphicEx()` into thin wrappers that
initialize the same context and call the same coordinator. Preserve their
exact ABI and behavior.

Keep ImpGraph legacy progress translation isolated in one compatibility source
file rather than conditional browser code throughout the main dispatcher.
Other geodes retain their own clearly named compatibility boundaries when an
existing export requires one.

Add one status-normalization point in the coordinator. Codec-specific results
must be translated there to `MimeGraphicError` according to the public
contract; individual public wrappers must not invent different mappings.

Completion criteria:

- All public entries use one internal coordinator.
- New and legacy dispatch modes have separate tests and preserve their defined
  selection order.
- All terminal internal statuses map to one documented `MimeGraphicError`.
- Format behavior, animation behavior, compaction, and return values match the
  baseline.
- Codec implementations have not yet been broadly rewritten.

# Step 4 - Add generic input and signature buffering

Implement a small internal reader wrapper that obtains bytes from either:

- the generic source callback; or
- the existing ordinary file path.

For a generic source, mark the codec-selection checkpoint before reading the
small prefix required for signature detection. Detect GIF, JPEG, and PNG
without consulting BbxBrow. Commit once codec selection is irreversible.

MIME remains a hint. Test correct, empty, missing, and incorrect MIME values.

Adapt the existing incremental GIF path to receive bounded chunks from the
generic reader. Retain the existing maximum feed of 512 bytes per
`ImpGIFProcess()` call. Do not attempt to fill the nominal 2048-byte ring: its
EC invariant requires strictly more free space than the incoming byte count,
and equal start and end indexes cannot represent a full ring. Add an EC check
that no feed exceeds 512 bytes and tests with 511-, 512-, and 513-byte source
fragmentation.

Add an ImpGraph-only generic IJG source manager. Use IJG's existing custom
source-manager mechanism; do not add or change any public Ijgjpeg API. Preserve
IJG suspension behavior. The source manager must not mention
`LoadProgressData`.

Fjpeg remains first for JPEG in the FJPEG ImpGraph variant. Add one private
generic-source initialization entry to Fjpeg after all existing exports and
increase only the Fjpeg protocol minor version. Declare it in a private header
shared with ImpGraph, not in the public Fjpeg header. Do not change the
signatures, ordinals, behavior, or public declarations of any existing Fjpeg
export, including `FJPEG_INIT_LOADPROGRESS`. Do not change the size or layout of
`fjpeg_decompress_struct`.

The private Fjpeg entry accepts only an opaque generic source descriptor with
fixed-or-movable read callback and context. It must not accept, construct, or
reference `LoadProgressData`. Fjpeg internally distinguishes this generic
source mode from its preserved standalone file and load-progress modes.

Keep the checkpoint active while Fjpeg determines whether it supports the
JPEG, and make that decision before output allocation or observer-visible
output. Then:

- on supported input, commit the checkpoint and continue with Fjpeg;
- on unsupported input, reset to the checkpoint, commit at that position, and
  retry with the ImpGraph-owned IJG source manager;
- on source error, cancellation, or malformed input, do not retry as
  unsupported;
- after Fjpeg has committed or reported output, do not replace it with IJG.

The ImpGraph Fjpeg integration must therefore preserve distinct supported,
unsupported, malformed, source-error, and cancellation results instead of
using a null bitmap as the only fallback signal.

Do not make PNG incremental. Return `MGE_REQUIRES_FILE` when a generic stream
is detected as PNG.

Completion criteria:

- Streaming GIF, IJG JPEG, and Fjpeg input uses only the generic reader.
- The FJPEG variant tries Fjpeg first and replays the same source bytes to IJG
  only when Fjpeg reports unsupported input.
- Ordinary GIF, JPEG, Fjpeg, PNG, and animated GIF file imports remain
  unchanged.
- ImpGraph's IJG and Fjpeg generic integration and Fjpeg's private generic
  source path contain no `LoadProgressData` reference.
- Existing public Ijgjpeg and Fjpeg APIs and export ordinals are unchanged; the
  new private Fjpeg export is appended.

# Step 5 - Replace codec progress data with the generic observer

Route header, output-ready, and bitmap-change facts through the generic
observer.

Convert GIF, IJG JPEG, Fjpeg, and PNG progress reporting one codec at a time.
The PNG input remains file based, but its optional progress reporting uses the
same observer.

Keep display throttling out of ImpGraph. Report the decoder's natural changed
range, normalize it to the zero-based inclusive observer contract, and let
BbxBrow coalesce notifications.

Implement the ownership contract before removing `FreeViaProgress()` from the
core. A legacy adapter may retain equivalent compatibility behavior while old
callers exist.

For an animation-capable streamed GIF, mark the first displayable bitmap as
provisional. Keep that preview stable until return. Return the same chain as
the final output for a single-frame GIF, or return an independently owned final
animation root plus the preview chain for an animated GIF. If decoding stops
after the preview but before a usable final object exists, promote the preview
to an incomplete final output. Do not apply provisional handling to JPEG or to
GIF imports using `MIME_GREX_NO_ANIMATIONS`.

Completion criteria:

- New core and codec paths contain no `ImportProgressData` reference.
- Header rejection causes a clean synchronous abort.
- Cancellation after output returns a partial bitmap rather than freeing an
  observer-visible chain.
- Every bitmap-change event has a nonempty in-bounds range, including the first
  and last partial PNG slices and full-height GIF updates.
- Animated streamed GIF output uses the explicit provisional-preview handoff;
  the final animation does not reference the separately returned preview.
- New paths do not use `FreeViaProgress()` to infer output ownership.
- Animated GIF behavior remains unchanged.

# Step 6 - Migrate BbxBrow to the new entry

Add BbxBrow-private adapters:

- a reader that blocks on the existing browser byte storage and returns
  generic reader statuses;
- source control that maps the generic codec-selection checkpoint onto the
  existing retained-read behavior: marked reads retain bytes, reset restores
  the retained start, and commit switches to ordinary consuming reads;
- an observer that applies admission policy, updates ObjCache state, coalesces
  scanline ranges, and queues copied UI update data.

Use a stable optr as each callback cookie. The reader locks `G_allocBlock` only
to re-dereference the job and copy its stable BbxBrow source descriptor or
fetch-slot identity. It unlocks `G_allocBlock` before waiting on the source
semaphore or blocking for network data. After a wait, it re-locks and
re-dereferences the job before changing job state. Never retain an LMem pointer
across an unlock.

Track whether the observer reported provisional output in that stable job
state. A provisional preview may be displayed and represented by a transient
ObjCache entry, but it must not be made permanently cacheable.

Replace the separate probe in the new streamed-import path with header
admission through the same import call:

- if the pixel limit is disabled, mark admission accepted before importing and
  do not apply a pre-header byte limit;
- while admission is undecided, the BbxBrow reader counts source bytes and
  does not read beyond the existing probe-byte limit;
- if that limit is reached before `MGPE_HEADER_READY`, mark the job deferred
  and return `MGRS_ABORT`;
- on `MGPE_HEADER_READY`, reject zero dimensions and compare the dimensions to
  the existing pixel limit using division so the calculation cannot overflow;
- on acceptance, mark the job accepted and return `TRUE` from the observer;
- on rejection, mark the job deferred and return `FALSE`;
- whenever admission becomes accepted or deferred, mirror that result into the
  existing BbxBrow-owned `LPD_imageProbe` transport field under `LPD_sem`; the
  `LoadProgressData` pointer remains entirely inside the BbxBrow adapter;
- when the import returns, BbxBrow interprets its own deferred job state as
  intentional image deferral, suppresses import-failure UI, and follows the
  existing `URL_RET_IMAGE_DEFERRED` behavior.

Do not call `MIME_ENTRY_GRAPHIC_PROBE` before the new streamed import. Retain
that selector for old callers and non-migrated paths only. No admission result
or probe limit is added to the generic ImpGraph API.

After the import returns, queue final replacement behind every already queued
preview update. For an animated GIF, replace the transient preview with the
final animation root, then release the independently returned preview only
after that replacement has been processed. For a single-frame GIF or a partial
result that promoted the preview to `MGIP_output`, retain the output normally
and perform no separate preview release. This ordering ensures that queued UI
work never observes a freed preview chain.

The browser must keep the loaded ImpGraph library referenced for the entire
synchronous import call. It must verify the new selector's protocol version
before calling it and fall back to the legacy entry when necessary.

For a streamed PNG or another `MGE_REQUIRES_FILE` result, hand the operation
back to the existing completed-file path:

- lock `LPD_sem`, set `LPD_progress` to `FALSE`, and unlock `LPD_sem`;
- record locally that completed-file fallback is pending;
- release the existing fetch/import synchronization normally;
- do not report import failure, replace the image, decrement the pending
  operation, or delete the destination file from the streaming import;
- let transport completion return through the existing `URL_RET_FILE` path;
- let that path queue exactly one ordinary file import using the completed
  destination file.

The URL completion path retains responsibility for network failure,
cancellation, temporary-file cleanup, and eventual pending-operation
completion. No new `LoadProgressData` field or Wmg3Http change is required.
Do not add incremental PNG work to this project.

Wmg3Http and the existing BbxBrow transport contract remain unchanged.
`LoadProgressData` may continue to exist between those components, but it is
not passed into ImpGraph's new entry.

Completion criteria:

- BbxBrow uses the new entry for supported ImpGraph drivers.
- BbxBrow progress and dimension admission comes from generic observer events;
  its reader enforces the pre-header byte budget.
- The new streaming path performs header admission in the import call, honors
  both probe limits, and maps rejection or a missing header within the byte
  limit to intentional deferral rather than import failure.
- BbxBrow-specific data never crosses the new driver entry.
- Fjpeg-to-IJG fallback replays the same bytes without exposing
  `LoadProgressData` to ImpGraph or either new generic codec path.
- Completed-file fallback queues exactly one ordinary import without an
  intermediate failure notification or premature pending-count decrement.
- A provisional GIF preview is only transiently cached, final replacement is
  ordered after preview updates, and an independent preview is released only
  after that replacement is processed.
- `G_allocBlock` is not locked while a source callback waits for input or a
  source semaphore.

# Step 7 - Quarantine legacy compatibility code

Repository-wide verify that the new ImpGraph coordinator, generic probe, and
new codec paths no longer depend on:

- `LoadProgressData`
- `ImportProgressData`
- `LPD_` fields
- `IPD_` fields
- browser callbacks
- ObjCache or text objects

Keep the old graphic selectors and their ordinals. Their wrappers may translate
legacy parameters into the new private context. Keep `MimeDrvGraphicProbe()` as
a legacy wrapper around a generic probe reader. Do not remove these entries in
this project.

Keep existing exported codec-library APIs unchanged. Direct consumers such as
Graphvwr must compile without source changes.

The appended private Fjpeg generic-source entry is an internal ImpGraph/Fjpeg
integration boundary, not part of the standalone public Fjpeg API. It must not
reuse `FJPEG_INIT_LOADPROGRESS` or any `LoadProgressData` compatibility type.

Legacy compatibility is isolated per exporting geode:

- ImpGraph owns the old graphic-entry and probe wrappers that translate
  `ImportProgressData` and `LoadProgressData`;
- Ijgjpeg retains `JPEG_INIT_LOADPROGRESS` and its old load-progress source
  path behind an Ijgjpeg compatibility boundary;
- Fjpeg retains `FJPEG_INIT_LOADPROGRESS` and its old load-progress source path
  behind an Fjpeg compatibility boundary.

These named legacy files and public legacy declarations are exempt from the
new-path dependency search. Maintain an explicit allowlist and verify that no
other ImpGraph or codec file contains `LoadProgressData`, `ImportProgressData`,
`LPD_`, or `IPD_` references. The new private Fjpeg generic-source entry and
the ImpGraph code that calls it are not exempt and must pass this search.

Remove obsolete conditional branches only when repository-wide searches prove
that the new core no longer needs them. Do not turn this step into a global
`PROGRESS_DISPLAY` removal project; browser and transport code may still use
that option.

Completion criteria:

- Browser coupling is isolated to BbxBrow and one documented legacy boundary
  in each geode that owns a preserved ABI export.
- The maintainable ImpGraph path uses one context, one reader contract, and one
  observer contract.
- Legacy wrappers select the explicit legacy dispatch mode; the new entry uses
  signature-first dispatch.
- Existing ABI exports remain intact.
- Existing public Ijgjpeg and Fjpeg APIs remain unchanged, and the private
  Fjpeg integration export is appended without shifting an existing ordinal.

# Step 8 - Build and behavioral validation

Build EC and non-EC variants where relevant:

- ImpGraph
- ImpGraph FJPEG variant
- BbxBrow
- BbxBrow AB variant
- Ijgjpeg
- Fjpeg
- GPCMail
- PicAlbum
- Graphvwr

Build from matching `Installed/` directories with the normal generated build
workflow. Do not manually edit generated Makefiles or dependency files.

Test at least:

- ordinary GIF
- interlaced GIF
- animated GIF
- ordinary and progressive JPEG
- progressive JPEG where supported
- Fjpeg
- streamed JPEG accepted by Fjpeg
- streamed JPEG rejected by Fjpeg and replayed successfully to IJG
- checkpoint mark, repeated reset, and commit ordering
- checkpoint-control failure before and during Fjpeg selection
- ordinary PNG
- streamed PNG completed-file fallback
- network failure after completed-file fallback begins
- cancellation and shutdown while completed-file fallback is pending
- exactly one ordinary import and one pending-operation completion per fallback
- correct MIME
- missing MIME
- empty MIME
- incorrect MIME with a recognized signature
- legacy MIME-driven dispatch and codec fallback order
- null required parameters
- import-parameter sizes below, at, and above the version-1 size
- each public `MimeGraphicError` mapping, including partial-output cases
- one-byte reader results
- short reader results
- GIF source fragmentation at 511, 512, and 513 bytes, with no decoder feed
  exceeding 512 bytes
- EOF before header
- truncated input after output exists
- malformed input
- source error
- cancellation before header
- header rejection
- header admission accepted below the pixel limit
- header admission rejected for zero dimensions or above the pixel limit
- admission deferred when no header is available within the probe-byte limit
- cancellation after output is visible
- streamed single-frame GIF whose provisional preview becomes `MGIP_output`
  with a null `MGIP_preview`
- streamed animated GIF with distinct final and preview chains, and no final
  animation reference to the preview
- cancellation, source failure, truncation, and malformed trailing input after
  a GIF preview, promoting the preview to an incomplete `MGIP_output`
- queued preview updates completing before independent preview release
- `MGIP_usedMem` accounting each distinct final and preview chain once
- success, cancellation, and shutdown cleanup without a preview double free
- early application shutdown
- ObjCache enabled and disabled, including provisional preview lifetime
- old graphic entry callers
- graphic-ex no-animation callers
- legacy probe callers

Verify with Swat where useful:

- callback invocation through fixed-or-movable code
- callback cookie and job optr lifetime
- no retained source buffer pointer
- no retained progress pointer
- fixed and movable reader, control, observer, and driver-entry calls
- `G_allocBlock` unlocked throughout a blocking source wait
- zero-based inclusive changed ranges within the reported image height
- output VM chain ownership
- provisional preview promotion, replacement ordering, and independent release
- partial bitmap return behavior
- AllocWatcher accounting
- loaded ImpGraph library lifetime
- Fjpeg checkpoint release after commit, error, cancellation, and IJG fallback

Final acceptance criteria:

- ImpGraph remains synchronous.
- Existing file and animated GIF behavior is preserved.
- Existing MIME driver selector ordinals are preserved.
- The callback ABI includes fixed-or-movable typedefs and invocation rules.
- Required parameters, compatible structure sizes, and normalized errors have
  one public contract.
- New callers pass one import-parameter pointer.
- ImpGraph core receives streaming bytes through a generic reader.
- The FJPEG variant tries Fjpeg first and uses the source checkpoint to retry
  unsupported JPEGs with IJG.
- ImpGraph core reports decoder facts through a generic observer.
- Changed-line events use nonempty zero-based inclusive in-bounds ranges.
- Non-provisional observer output remains the stable returned output chain.
- Provisional animated GIF output has explicit ownership: it remains valid
  through return, and a distinct final animation and preview are independently
  caller-owned.
- New ImpGraph core and codec paths contain no browser state; preserved legacy
  ABI boundaries are documented and allowlisted.
- BbxBrow owns progress display, ObjCache, and admission policy.
- New streamed imports perform admission from the same decoder pass without
  holding `G_allocBlock` during blocking source reads.
- Wmg3Http requires no protocol redesign.
- PNG requires no incremental rewrite.
- Existing public Ijgjpeg and Fjpeg APIs and export ordinals are unchanged; the
  private Fjpeg integration export is appended.
- No bitmap, VM chain, watcher allocation, callback context, or library
  reference leaks.
