# BbxBrow / ImpGraph Progress Refactor

## Goal

Decouple BbxBrow from ImpGraph and make ImpGraph a synchronous graphics
conversion library with no browser policy.

BbxBrow receives bytes, owns the transport state, decides whether an image is
allowed, manages ObjCache, and schedules UI updates. ImpGraph receives either a
file or a generic blocking byte source, selects an existing codec, and converts
the bytes into HugeBitmap or animation VM chains.

ImpGraph may report decoder facts through a generic observer. It must not know
why the caller wants those facts or what the caller does with them.

New ImpGraph core and codec paths must not know about:

- BbxBrow objects or messages
- LoadProgressData or ImportProgressData
- NameTokens or ObjCache
- fetch threads, fetch slots, or browser semaphores
- browser redraw throttling
- browser image-admission policy
- URL return codes

The dependency direction is BbxBrow to ImpGraph to the GIF, IJG JPEG, Fjpeg,
and PNG codecs. No new dependency points back toward BbxBrow.

## Non-goals

Do not add:

- asynchronous ImpGraph entry points
- decoder session objects or a push decoder API
- a new browser input queue
- a Wmg3Http protocol redesign
- incremental PNG decoding
- a global PROGRESS_DISPLAY cleanup
- breaking changes to existing MIME, Ijgjpeg, Fjpeg, PNG, or GIF exports
- removal or renumbering of existing MIME selectors
- unrelated codec cleanup

Ordinary file imports and animated GIF behavior must remain compatible.

## Existing compatibility facts

The existing ImpGraph selector ordinals are:

- 0: MIME_ENTRY_GRAPHIC
- 1: MIME_ENTRY_INFO
- 2: MIME_ENTRY_TEXT
- 3: MIME_ENTRY_GRAPHIC_EX
- 4: MIME_ENTRY_GRAPHIC_PROBE

ImpGraph is currently protocol 4.3. Append the new entry as selector 5 and
raise only ImpGraph to protocol 4.4. Keep MIME_DRV_PROTOMINOR at 0 so older
MIME drivers still load.

BbxBrow currently calls selectors 0 and 4. GPCMail calls selector 0. PicAlbum
calls selector 3 and uses MIME_GREX_NO_ANIMATIONS where appropriate. Graphvwr
uses its existing direct GIF code and must continue to compile without source
changes.

The existing entries remain ABI-compatible. Their implementations will become
legacy adapters to the same private coordinator used by the new entry. Legacy
MIME-driven codec order, return values, compaction, animation behavior, and
probe behavior must not change.

## Public ImpGraph API

Add the declarations to CInclude/htmldrv.h. Use the exact names below.

Add this selector:

    #define MIME_ENTRY_GRAPHIC_IMPORT 5

Append this to Library/Breadbox/ImpGraph/impgraph.gp:

    incminor
    export MIMEDRVGRAPHICIMPORT

Do not reorder any existing export.

### Callback rules

All callbacks are cross-geode callbacks. Store callback pointers as
void _pascal * and call them through ProcCallFixedOrMovable_pascal using the
matching pcfm_* typedef.

Use a dword callback context. The caller owns every parameter, descriptor,
callback context, and callback argument. Those values remain valid until the
synchronous import entry returns. ImpGraph must not retain them afterward.

### Generic source

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

The reader contract is:

- MGRS_DATA returns at least one byte in *bytesReadP.
- MGRS_EOF, MGRS_ERROR, and MGRS_ABORT return zero bytes.
- Short reads are valid.
- The reader may block until bytes, EOF, error, or cancellation are known.
- ImpGraph never requests zero bytes and never retains bufferP.
- MGRS_ERROR maps to MGE_SOURCE_ERROR.
- MGRS_ABORT maps to MGE_CANCELLED.

The checkpoint is required for codec selection and Fjpeg-to-IJG fallback.
Fjpeg may consume an arbitrary part of the JPEG header before deciding that it
does not support the image. IJG must then receive the identical stream from
byte zero.

The exact checkpoint sequence is:

- ImpGraph calls MGSO_MARK exactly once before the first source read.
- Signature detection occurs while the checkpoint is active.
- ImpGraph may use a small prefix buffer so a selected decoder can see bytes
  already read for signature detection.
- When a codec is final, ImpGraph calls MGSO_COMMIT once and continues reading.
- If Fjpeg reports unsupported, ImpGraph calls MGSO_RESET, then MGSO_COMMIT at
  the reset position, disables prefix replay, and starts IJG from byte zero.
- Source error, cancellation, malformed input, or allocation failure does not
  trigger IJG fallback.
- ImpGraph performs no checkpoint operation after commit.
- A failed control operation is MGE_SOURCE_ERROR and stops codec fallback.

The source must retain every byte consumed after MARK until COMMIT. RESET
restores the logical position and terminal status that an uninterrupted read
would have produced. The private prefix reader has its own replay position:
signature detection fills it, the first selected decoder sees it once, and an
Fjpeg-to-IJG reset clears prefix replay because IJG then reads the retained
bytes directly from source position zero.

### Generic observer

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

Observer events are decoder facts:

- MGPE_HEADER_READY is sent once dimensions and required header facts are
  known, before expensive output allocation where the codec permits it.
- A header event has MGP_bitmap zero. MGP_iad contains the dimensions and
  output type known at that point. Its changed-range fields are ignored.
- Returning FALSE from any event requests synchronous cancellation.
- MGPE_OUTPUT_READY is sent once when an observer-visible bitmap first exists.
  This event establishes the borrowed-handle lifetime and is not replaced by a
  bitmap-change event.
- MGPE_OUTPUT_PROVISIONAL is valid only with MGPE_OUTPUT_READY.
- MGPE_BITMAP_CHANGED reports a nonempty, conservative scanline range.
- The changed-range fields are valid only with MGPE_BITMAP_CHANGED.
- OUTPUT_READY may be combined with the first BITMAP_CHANGED event.
- Changed ranges are zero-based, inclusive, and within the reported height.
- ImpGraph clamps legacy codec ranges and suppresses empty ranges.
- progressP is valid only during the callback. The receiver queues copied
  values, never the pointer.
- The observer borrows the bitmap and must not free or replace it while the
  entry is active.

Preserve the current minimum batching of approximately ten scanlines for GIF,
IJG JPEG, Fjpeg, and PNG. Extra events are allowed for an interlace pass
boundary or final partial slice. Do not make one cross-geode callback per
scanline.

ImpGraph does not throttle display updates, access ObjCache, send UI messages,
or apply image-admission limits.

### Import parameters and errors

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

    typedef VMBlockHandle _pascal _export
    entry_MimeDrvGraphicImport(MimeGraphicImportParams *paramsP);

    typedef VMBlockHandle _pascal
    pcfm_MimeDrvGraphicImport(
        MimeGraphicImportParams *paramsP,
        void *pf);

Validation and result rules are:

- paramsP is required.
- MGIP_size smaller than MIME_GRAPHIC_IMPORT_PARAMS_V1_SIZE returns NullHandle
  without accessing any member after MGIP_size.
- Larger structures are accepted. Version 1 accesses only version-1 fields.
- MGIP_vmFile, MGIP_watcher, and MGIP_statusP are required.
- MGIP_resolution must be a defined MimeRes value.
- MGIP_file is required when MGIP_sourceP is null and ignored otherwise.
- A supplied source requires both callbacks.
- A supplied observer requires its callback.
- MGIP_mimeHint is optional and is only a hint for the new entry.
- MGIP_flags carries the existing graphic-ex flags.
- Initialize every version-1 output before doing import work.
- The return value and MGIP_output are identical.

Error mapping is centralized in the private coordinator:

- no recognized signature: MGE_UNSUPPORTED_FORMAT
- recognized but invalid data: MGE_MALFORMED_INPUT
- generic reader error: MGE_SOURCE_ERROR
- reader abort, observer rejection, or MIME_STATUS_ABORT: MGE_CANCELLED
- allocation refusal: MGE_NO_MEMORY
- streaming format requiring the completed file: MGE_REQUIRES_FILE
- otherwise unclassified codec failure: MGE_IMPORT_ERROR

Do not infer all failures from a null bitmap. Add private codec results where
needed so unsupported, malformed, source error, cancellation, and allocation
failure remain distinct.

Missing or empty MIME tests apply to direct calls to selector 5. BbxBrow still
uses its MIME association to locate the driver before calling the entry.

## Output ownership

ImpGraph owns every output chain until the entry returns. The observer only
borrows observer-visible chains.

After MGPE_OUTPUT_READY, a non-provisional output handle remains stable and is
the returned output. ImpGraph must not free an observer-visible chain and then
return NullHandle. Cancellation, source failure, or malformed trailing input
after output exists returns that usable bitmap with IAD_completeGraphic FALSE.

An animation-capable streamed GIF has special provisional ownership because
animation status is not known when its first bitmap becomes displayable:

- The first bitmap is reported with OUTPUT_READY and OUTPUT_PROVISIONAL.
- The preview chain remains valid until the import entry returns.
- A single-frame GIF returns that chain as MGIP_output and sets MGIP_preview to
  zero.
- An animated GIF returns an independent animation root as MGIP_output and the
  preview as MGIP_preview.
- The final animation must not reference MGIP_preview.
- If decoding stops before a usable final object exists, promote the preview
  to incomplete MGIP_output and set MGIP_preview to zero.
- JPEG and GIF imports using MIME_GREX_NO_ANIMATIONS never report provisional
  output.

On return, every nonzero output and preview belongs to the caller. MGIP_usedMem
includes each distinct returned chain once. The caller may release an
independent preview only after all queued preview UI work has finished.

Ordinary file imports retain their current final compaction behavior.
Non-provisional observer-visible output must not be replaced by compaction.

## Private ImpGraph architecture

Create one private ImpGraphImportContext. It contains normalized parameters,
source state, observer state, ownership state, selected codec, private codec
result, dispatch mode, and the existing ImpBmpParams data.

Implement one coordinator:

    static VMBlockHandle
    ImpGraphImport(ImpGraphImportContext *contextP);

It has two explicit dispatch modes:

- New entry: signature-first selection; MIME is only a hint.
- Legacy entries: preserve the existing MIME-driven order and fallback rules.

The new entry and legacy wrappers initialize the context and call the same
coordinator. Only the coordinator maps private terminal results to
MimeGraphicError and performs final ownership cleanup.

Put legacy translation in one clearly named ImpGraph compatibility source
file. That file may mention LoadProgressData and ImportProgressData. It adapts
old source and progress callbacks to the generic private context. Do not copy
legacy conditionals into the coordinator or codecs.

MimeDrvGraphic, MimeDrvGraphicEx, and MimeDrvGraphicProbe keep their exact
signatures and ordinals. MimeDrvGraphicProbe remains a compatibility entry.

## Codec changes

### GIF

Feed ImpGIFProcess through the generic reader in chunks no larger than 512
bytes. Do not fill the nominal 2048-byte ring: equal start and end indices
cannot represent a full ring, and its EC invariant requires more free space
than the incoming count.

Add an EC check for the 512-byte maximum. Verify source fragmentation at 511,
512, and 513 bytes and confirm no decoder call receives more than 512 bytes.

Convert header, first output, and changed-range reporting to the generic
observer. Preserve interlace-pass updates, batching, animation behavior, and
the provisional preview rules.

### IJG JPEG

Add an ImpGraph-owned IJG source manager. Do not change or append an Ijgjpeg
public export. Its fill callback uses the generic reader and records terminal
reader status in ImpGraph context.

The browser reader blocks for new bytes, so temporary lack of network data is
not reported to IJG as EOF. Preserve the existing IJG end-of-input and partial
decode behavior. Convert progress reporting to the generic observer.

JPEG_INIT_LOADPROGRESS and its old source manager remain only for existing
external callers.

### Fjpeg

Fjpeg remains first in the PRODUCT_FJPEG ImpGraph variant. Append one private
export after FJPEG_INIT_LOADPROGRESS:

    incminor
    export FJPEG_INIT_GENERIC_SOURCE

Declare fjpeg_init_generic_source and its private source descriptor in a
private header shared only by Fjpeg and ImpGraph. The descriptor contains a
fixed-or-movable read callback, dword context, and last generic read status.
It contains no browser type.

Do not change the size or layout of fjpeg_decompress_struct. Use the existing
src.infile slot to hold the private generic source descriptor and reserve a
private high bit in decomp_mode to identify generic-source mode. Existing
decomp_mode operations already preserve unrelated bits. The generic fill path
checks that bit before the legacy file and load-progress branches. Apply the
same generic branch to fill_input_buffer_i in code/init.c and
fill_input_buffer_a in code/decode.c.

Add this required comment beside the private mode bit:

    ATTENTION: This bit and src.infile reuse preserve the public Fjpeg
    structure layout. The ceiling is one active source mode per decompressor.
    Replace this with an opaque Fjpeg context if a new public ABI is introduced.

The generic setup order is create decompress, call the existing stdio-source
initializer with a null FILE to allocate its input buffer, then call
fjpeg_init_generic_source to install the descriptor and mode bit.

In both Fjpeg fill functions, MGRS_DATA supplies the returned bytes and
MGRS_EOF follows the codec's existing synthetic-EOI behavior. MGRS_ERROR and
MGRS_ABORT record the terminal status and stop decoding; they must not be
converted into synthetic EOF or unsupported input.

Fjpeg must return a private result that distinguishes supported, unsupported,
malformed, source error, cancellation, and allocation failure. Only unsupported
causes MGSO_RESET and retry through IJG. Decide support before output allocation
or observer-visible output. Once Fjpeg is committed or output is reported, do
not switch to IJG.

Keep FJPEG_INIT_LOADPROGRESS and its existing declaration and behavior.

### PNG

PNG continues reading a completed file. If the new entry receives a generic
source whose signature is PNG, return MGE_REQUIRES_FILE with no output.

Convert file-based PNG progress reporting to the generic observer so the PNG
codec core no longer receives ImportProgressData. Preserve its current
batching and normalize first and last partial ranges.

## BbxBrow adapters and state transitions

BbxBrow owns all browser behavior. Implement the source adapter in the browser
module that owns the existing stream storage so both HugeArray and USE_MEM_STREAM
builds use the same correct storage operations. Implement the observer and
final ownership handling in htmlview/ImportG.goc.

Use two callback contexts because they have different lifetime and locking
requirements.

The source context is small and valid only for the synchronous entry call. It
contains the stable LoadProgressData pointer, checkpoint state, logical read
offset, admission byte count, and terminal status. Its steady-state read and
control callbacks must not lock or dereference G_allocBlock. They may acquire
LPD_sem, but release it before blocking for more data.

The observer context is a stable job optr when queued preview state must outlive
the import stack. Lock G_allocBlock only long enough to re-dereference the job
and copy or update state. Never retain an LMem pointer across unlock. Never hold
G_allocBlock while waiting for source data, acquiring LPD_sem, doing ObjCache
work, or sending a queued message.

The browser source maps checkpoint operations as follows:

- MARK starts retained reads at logical offset zero.
- Reads before COMMIT copy without deleting and advance the logical offset.
- RESET restores the logical offset to zero without changing stored bytes.
- COMMIT deletes bytes before the current logical offset, adjusts bytesAvail,
  and changes subsequent reads to consuming mode.

The adapter must implement these operations directly for the configured stream
storage. Do not expose LoadProgressData through the ImpGraph call.

### Starting a new streamed import

At LPCT_OPEN, preserve the legacy path for drivers older than protocol 4.4.
For ImpGraph 4.4 or later, start the new streamed import when the existing code
would start progressive GIF/JPEG work or when image admission is pending.

Append BbxBrow-private states to LoadProgressImageProbe rather than adding a
new LoadProgressData field:

- LPI_DECODER_PENDING = 4
- LPI_STREAM_HANDLED = 5
- LPI_FILE_REQUIRED = 6

Keep the numeric values of existing states unchanged.

When admission is enabled, set LPI_DECODER_PENDING before queuing the import.
The old LPI_PENDING state continues to mean that the legacy standalone probe
owns admission.

LPCT_WRITE behavior is:

- LPI_PENDING uses the existing legacy probe path.
- LPI_DECODER_PENDING or LPI_ACCEPTED appends normally and wakes the reader.
- LPI_DEFERRED returns LPCR_REJECT.
- Other existing states retain their current behavior.

LPCT_CLOSE sets fileDone and wakes the reader. The existing legacy probe runs
only for LPI_PENDING. A decoder-pending import finishes after the reader sees
EOF; fetch/import synchronization ensures its final state is known before the
fetch result is delivered.

### Same-pass admission

The observer applies browser admission policy to MGPE_HEADER_READY:

- With the pixel limit disabled, admission starts accepted and no pre-header
  byte limit applies.
- While LPI_DECODER_PENDING, the reader never supplies more than the existing
  imageProbeMaxBytes before a header event.
- Reaching that limit without a header sets LPI_DEFERRED and returns MGRS_ABORT.
- Reject zero dimensions.
- Compare width against maxPixels divided by height so multiplication cannot
  overflow.
- Acceptance sets LPI_ACCEPTED and returns TRUE.
- Rejection sets LPI_DEFERRED and returns FALSE.
- Update LPD_imageProbe only while holding LPD_sem.

When any new streamed import returns, set LPI_STREAM_HANDLED unless the final
state is LPI_DEFERRED or LPI_FILE_REQUIRED. Do this even if the decoder returned
a normal import error or cancellation; BbxBrow has already handled that result
and must not queue a second file import.

Add this BbxBrow result flag to CInclude/htmldrv.h:

    #define URB_RF_IMAGE_IMPORTED 0x1000

It means that the streamed image import was already handled.
URLFetchChildThread sets it after fetch/import synchronization when it sees
LPI_STREAM_HANDLED. The graphic fetch-result handler must not queue another
import or decrement the pending operation for that progress result.

If admission ends as LPI_DEFERRED, map the synchronized fetch result to the
existing URL_RET_IMAGE_DEFERRED behavior and suppress import-failure UI.

### Completed-file fallback

For MGE_REQUIRES_FILE:

- Set LPI_FILE_REQUIRED under LPD_sem.
- Set LPD_progress FALSE under the same semaphore.
- Release fetch/import synchronization normally.
- Do not report import failure, replace the image, decrement pending, or
  delete the destination file from the streaming import.
- After synchronization, map LPI_FILE_REQUIRED to URL_RET_FILE when transport
  itself succeeded.
- Preserve the original pixel limit so the completed-file import performs the
  existing probe when admission has not already succeeded.
- Queue exactly one ordinary file import from the normal URL_RET_FILE path.

Transport completion remains responsible for network error, cancellation,
temporary-file cleanup, and eventual pending completion. Wmg3Http requires no
new entry point or protocol change.

### Progress UI and final ownership

The observer copies event values, applies browser coalescing, creates transient
ObjCache state, and queues UI work. A provisional preview must never be made
permanently cacheable.

Queue final replacement after all preview updates. For an animated GIF, the
queued final replacement owns responsibility for releasing the independent
preview after replacement is processed. For a single-frame GIF or promoted
partial preview, MGIP_preview is zero and no separate release is queued.

Keep the ImpGraph library referenced for the entire synchronous call. Check
protocol 4.4 before requesting selector 5 and use the legacy entry otherwise.

## Legacy boundaries

After conversion, browser-specific names are allowed only in these documented
compatibility areas:

- the ImpGraph source file that implements selectors 0, 3, and 4 adapters
- the existing Ijgjpeg JPEG_INIT_LOADPROGRESS declaration and implementation
- the existing Fjpeg FJPEG_INIT_LOADPROGRESS declaration and implementation
- BbxBrow and Wmg3Http transport code

The new coordinator, new public entry, generic reader, generic observer,
ImpGraph codec integrations, and Fjpeg generic descriptor must contain no
LoadProgressData, ImportProgressData, LPD_, IPD_, ObjCache, NameToken, or browser
message reference.

Maintain an explicit search allowlist for the compatibility files. Do not make
all PROGRESS_DISPLAY code part of this project.

## Implementation order and build gates

Implement this as one change in the following order. Intermediate states need
not be committed or shipped, but do not cross a build gate while a changed
component fails to compile.

### Gate 1: ABI and private coordinator

Files in scope:

- CInclude/htmldrv.h
- Library/Breadbox/ImpGraph/impgraph.gp
- Library/Breadbox/ImpGraph/MAIN/impgraph.goc
- one new private ImpGraph context header
- one new ImpGraph legacy-adapter source file

Add selector 5, the exact public types, parameter validation, the private
context, file reader, generic reader wrapper, signature detection, centralized
result mapping, and legacy wrappers. Initially codecs may still call their
existing internals through private adapters, but all entries must compile and
legacy dispatch order must remain unchanged.

Build EC and non-EC ImpGraph and the FJPEG ImpGraph variant. Verify selectors
0 through 4 retain their ordinals and selector 5 is present only in protocol
4.4 or later.

### Gate 2: codecs and ownership

Files in scope:

- ImpGraph GIF, IJG JPEG, Fjpeg, and PNG integration files
- the private Fjpeg generic-source header
- Fjpeg source input implementation and fjpeg.gp

Convert one codec at a time in this order: IJG JPEG, Fjpeg, non-animation GIF,
animation-capable GIF, then PNG observer reporting. Build the changed codec and
both ImpGraph variants after each conversion.

Before passing this gate, generic codec paths contain no browser state, every
private terminal result maps correctly, observer ranges are valid, Fjpeg only
falls back on unsupported input, and provisional GIF ownership follows the
public contract.

### Gate 3: BbxBrow migration

Files in scope:

- Appl/Breadbox/BbxBrow/htmlview/ImportG.goc
- Appl/Breadbox/BbxBrow/htmlview/LoadURL.goc
- Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc
- the minimum matching BbxBrow headers and URL fetch result handling

Add the source and observer adapters, exact admission states, selector-5
protocol check, old-driver fallback, completed-file fallback, result flag, and
queued preview ownership.

Build BbxBrow and its AB variant in EC and non-EC form. Then build GPCMail,
PicAlbum, Graphvwr, Ijgjpeg, Fjpeg, and both ImpGraph variants.

Use the matching Installed directories and the normal generated build flow.
If dependencies changed, run mkmf and pmake depend. Do not manually edit
Makefile or dependencies.mk.

After every gate, preserve line endings, review git diff --ignore-space-at-eol,
and make no unrelated cleanup.

The BbxBrow import thread has a 4000-byte stack. Do not add an automatic buffer
larger than the existing 512-byte GIF buffer. Inspect generated Watcom code for
new coordinator and callback frame sizes. If safe headroom cannot be shown,
move persistent observer state to the existing LMem job or a temporary GEOS
memory block instead of increasing the thread stack.

## Validation

Record exact fixture names, commands, and expected results while implementing.
Do not leave a claim such as "tested JPEG" without identifying the file and
observed output.

At minimum verify:

- selectors 0 through 4 with existing callers
- selector 5 parameter sizes below, at, and above version 1
- null required parameters and each public error mapping
- correct, empty, missing, and incorrect MIME hints in direct selector-5 tests
- ordinary, interlaced, single-frame, and animated GIF
- ordinary and progressive JPEG through IJG
- JPEG accepted by Fjpeg
- JPEG rejected by Fjpeg and replayed from byte zero through IJG
- source checkpoint mark, reset, commit, and control failure
- one-byte reads and short reads
- GIF fragmentation at 511, 512, and 513 bytes
- ordinary PNG and streamed PNG completed-file fallback
- header admission accepted, rejected, and byte-limit deferred
- zero dimensions and overflow-safe pixel comparison
- EOF before a header and truncation after output exists
- malformed input, source error, and cancellation before and after output
- cancellation and shutdown while completed-file fallback is pending
- exactly one file import and one pending completion per fallback
- changed ranges at first, last, and interlace-pass boundaries
- streamed single-frame GIF preview promotion
- streamed animated GIF with independent final and preview chains
- preview updates processed before independent preview release
- ObjCache enabled and disabled
- AllocWatcher accounting with final and preview chains
- early application shutdown

Use Swat where needed to verify:

- fixed and movable reader, control, observer, and entry callbacks
- callback-context lifetime
- no retained source buffer or progress pointer
- G_allocBlock unlocked during blocking reads and source semaphore waits
- stable observer-visible handles
- output and preview VM-chain ownership
- no double free on cancellation or shutdown
- loaded ImpGraph lifetime
- Fjpeg checkpoint cleanup on success, fallback, error, and cancellation

## Final acceptance

The work is complete only when:

- ImpGraph remains synchronous.
- BbxBrow passes no browser structure through selector 5.
- ImpGraph core only selects codecs, reads bytes, creates VM chains, reports
  decoder facts, and normalizes codec results.
- BbxBrow alone owns transport, admission, ObjCache, UI coalescing, and URL
  completion behavior.
- File and animated GIF compatibility is preserved.
- Existing selectors and codec exports retain their ordinals and signatures.
- Fjpeg-to-IJG fallback replays the identical byte stream from byte zero.
- PNG remains file based.
- Observer-visible bitmap handles obey the ownership contract.
- No blocking read holds G_allocBlock or a browser source semaphore.
- Legacy browser coupling is confined to the documented compatibility files.
- No VM chain, bitmap, watcher allocation, callback context, library reference,
  temporary file, pending operation, or preview is leaked or freed twice.
