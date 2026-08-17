# Refactor BbxBrow / ImpGraph Progressive Image Loading

## Summary

Refactor the current baseline in six independently compilable steps. Keep one importer implementation with independently optional stream and progress callbacks, move all browser, cache, scheduling, and probe policy into BbxBrow-private state, and make VM-chain ownership explicit.

Source and binary compatibility for the affected MIME and URL progress interfaces is not required. PicAlbum, GPCMail, BbxBrow, ImpGraph, ImpDoc, Wmg3Http, IJG JPEG, and Fjpeg are rebuilt together. Preserve rendered results, probing, cancellation, caching, and bounded concurrency. Fetching while importing becomes the only supported mode.

## Interface decisions

- Replace LoadProgressData with a small neutral StreamEndpoint containing only a callback and an opaque dword client value.
- Pass the BbxBrow image-job token as the stream client value. Wmg3Http and ImpGraph must never interpret it.
- Pass one StreamHeaders value to LPCT_HEADERS containing the MIME value and known content length. Do not add a separate LPCT_CONTENT_LENGTH operation.
- Fold LPCT_OPEN initialization into LPCT_HEADERS. Retain the decoder-facing read, pre-read, peek, flush, reset, and close operations that are actually needed.
- Define callback dispositions as CONTINUE, STOP, and REJECT:
  - CONTINUE keeps streaming;
  - STOP stops further stream callbacks but completes the file download;
  - REJECT cancels the response body.
- Eliminate ImportProgressData. Replace it with:
  - MimeGraphicOptions containing an optional StreamEndpoint, optional progress callback, and opaque dword client value;
  - an immutable MimeGraphicProgress value containing VM file, bitmap, ImageAdditionalData, and changed scanlines.
- Make the progress callback return Boolean. TRUE means the callback successfully transferred the current bitmap chain to client ownership; FALSE leaves it importer-owned.
- A NULL options pointer means an ordinary non-progressive file import. Stream and progress callbacks remain independently optional.
- Use one MIME graphic entry at MIME_ENTRY_GRAPHIC. Add flags and the optional MimeGraphicOptions pointer to that entry and remove MIME_ENTRY_GRAPHIC_EX and its forwarding wrapper.
- Bump the MIME-driver major protocol because the graphic entry stack layout changes. Bump the URL-driver major protocol when changing the stream descriptor and result contract. Old drivers must fail to load rather than call an incompatible stack layout.
- Remove compatibility padding, structure size and offset preservation, append-only enum requirements, and the LoadProgressData and ImportProgressData names.

## BbxBrow job and stream storage

- Rename and extend the existing URLTextRequestGraphic LMem request chunk into BbxBrowImageJob. Allocate it through the existing URLFetchExtraMemoryAlloc mechanism in G_allocBlock; do not allocate one MemHandle per image.
- Keep the job compact. It owns browser policy and lifecycle data such as text object, image index, NameToken, display policy, probe limits and result, ObjCache token, and fetch/import slot indices.
- Use the job optr as its stable identity and opaque callback client value. Lock G_allocBlock and re-dereference the chunk for every access. Never retain a raw job pointer across an unlock.
- Do not free the job in MSG_URL_TEXT_GRAPHIC_FETCHED before import. Transfer ownership of the same job token from URLText to URLFETCH and then to the import worker. The terminal success, failure, deferral, cancellation, or discarded-request path frees it exactly once.
- Queue the job token directly to the import worker and eliminate the separate T_importGraphicRequest MemHandle. Store the fetched MIME value and filename in the job or in its protected active slot before queueing import.
- Keep address-stable producer/consumer state in fixed fetch/import stream slots, not in the movable LMem job. This includes semaphores, Block/WakeUp queue words, VM stream handles, byte counts, reader state, and completion flags.
- The job stores only the stream-slot and import-worker indices. Always transfer an active stream slot to the import worker before reusing the fetch child; do not copy the complete job.
- Keep the job alive while either the transport or importer may call its endpoint. Update G_numExtraAllocs and shutdown handling so G_allocBlock cannot be freed while a job remains active.
- Queued UI progress records must copy the text object, NameToken, cache token, and immutable update they need. They must not retain a job pointer or token past import completion.

## BbxBrow memory stream

- Move MemStreamHeader, G_stream, and all MemStream functions from URLTEXT.goc into a private urlfetch/MEMSTRM.goc module.
- Build MEMSTRM.goc into the existing fixed URLFETCH_TEXT code resource with pragma option -zCURLFETCH_TEXT. Do not add a code resource or library.
- Keep G_stream and all implementation details private to the module. Put only the needed external function declarations in the existing urlfetch.goh.
- Expose reset, read, write, discard, and free-all operations by stream-slot index. Do not export the G_stream array or raw MemStreamHeader pointers.
- Keep producer/consumer semaphores, Block/WakeUp queues, job policy, and import scheduling outside the memory-stream module. The module owns byte storage only.
- Retain the current 8 KB block size and approximately 1.6 MB cumulative capacity unless measurements justify a different bound. Add EC assertions that one read or write spans at most two blocks.
- Mark the two-block operation limit and cumulative-capacity limit with ATTENTION comments. State that looping over arbitrary blocks or implementing a reusable ring is the upgrade path.
- Do not replace this storage with the native GEOS stream driver. Its 32 KB maximum buffer and lack of the required peek, pre-read, and rewind retention do not cover the decoder contract.

## Fetch/import concurrency

- Make fetching while importing unconditional. Remove ALLOW_FETCH_WHILE_IMPORTING, G_fetchWhileImport, and the fetchWhileImport INI setting.
- Fetch children never wait for image import and no image request allocates an import-completion semaphore.
- A progressive import owns its stream slot until completion. The fetch child is immediately reusable after transferring the slot and job token.
- If no progressive stream/import slot is available, continue downloading the file and queue an ordinary non-progressive file import. This is the bounded-resource fallback; do not block the fetch child.
- Keep intelligent probing available through its bounded prefix buffer even when no progressive import slot is available.
- Replace cross-module policy checks and G_importActive bookkeeping with protected stream/import-slot ownership state. Each slot has exactly one free, fetching, or importing owner.
- Make shutdown wait on a semaphore or engine-completion event until active imports release their slots and LMem jobs. Do not retain the current busy-wait loop.

## Six compilable steps

### 1. Remove the PROGRESS_DISPLAY=OFF implementation

- Unconditionally compile the current ON signatures and behavior throughout BbxBrow, ImpGraph, GIF/JPEG/PNG importers, IJG JPEG, Fjpeg, Wmg3Http, and their headers.
- Remove alternate signatures, OFF decoder behavior, conditional macros, conditional globals/messages, and the void-only ImportProgressData definition.
- Preserve later decoder fixes already present after the cited source revisions.
- Update ordinary callers as needed so PicAlbum, GPCMail, BbxBrow, and local imports compile before changing the interface.
- Gate the step on EC and non-EC builds of the touched libraries and geodes.

### 2. Replace the MIME and stream interfaces

- Add StreamEndpoint and StreamHeaders and change the stream callback to use an opaque dword client value.
- Add MimeGraphicOptions and immutable MimeGraphicProgress. Wire the Boolean progress-callback result through all decoder paths.
- Merge MimeDrvGraphicEx into MimeDrvGraphic, add flags to the single entry, and remove the extended export and forwarding wrapper.
- Update BbxBrow, PicAlbum, GPCMail, ImpGraph, ImpDoc, Wmg3Http, IJG JPEG, and Fjpeg in one compilable change.
- Define empty or unknown MIME input explicitly as signature-based GIF/JPEG/PNG fallback, as required by PicAlbum, rather than leaving the decoder status undefined.
- Bump the MIME and URL driver protocols and update all in-tree users and drivers.

### 3. Introduce the LMem image job, extract the memory stream, and simplify scheduling

- Replace URLTextRequestGraphic with BbxBrowImageJob in an existing private header and continue allocating it from G_allocBlock.
- Pass the job optr through URLFetchRequest, URLFetchResult, stream callbacks, and import messages as the sole job identity.
- Transfer job ownership between stages instead of copying complete jobs or allocating a separate import-request MemHandle.
- Keep thread-shared stream state in fixed slots and record only slot indices in the job.
- Move the MemStream implementation into urlfetch/MEMSTRM.goc in the existing URLFETCH_TEXT resource. Make the module own G_stream and expose only slot-based storage operations through urlfetch.goh.
- Preserve and assert the two-block-per-operation and cumulative-capacity limits, with ATTENTION comments naming the upgrade paths.
- Select the import worker from the job. Requests without a browser job use worker zero.
- Remove ALLOW_FETCH_WHILE_IMPORTING, G_fetchWhileImport, the fetchWhileImport INI setting, per-request import-completion semaphores, and their blocking paths.
- Always release the fetch child after transferring the job and any active stream slot. If no progressive slot is free, use the ordinary file-import fallback.
- Replace G_importActive with protected slot ownership. Use a completion semaphore or event for shutdown instead of polling active slots.
- On every exit, release owned NameTokens and cache references, release its stream/import slot, signal shutdown completion when required, and free the LMem chunk exactly once.
- Remove the unused IMPORTWK/G_importWorkFile setup after confirming its only initial value is overwritten by ImpGraph.

### 4. Move probing into BbxBrow and neutralize Wmg3Http

- Keep maximum pixels, maximum bytes, MIME value, and pending, accepted, or deferred probe state in BbxBrowImageJob.
- Have LPCT_HEADERS initialize the selected stream mode and make the small-content decision in BbxBrow.
- Buffer only the configured probe prefix, invoke ToolsProbeGraphicByDriver through the neutral endpoint, and make the admission decision in BbxBrow.
- Return STOP after an accepted probe so HTTP completes the file without further stream callbacks. Return REJECT after a deferred probe.
- Keep probing available when intermediate bitmap display is disabled.
- Have Wmg3Http use only the endpoint callback, opaque client value, StreamHeaders, and callback disposition. Keep stream-active state local to the driver.
- Remove all Wmg3Http inspection of MIME buffers, display policy, probe limits/results, browser flags, and ObjCache state.
- Remove URL_RET_PROGRESS, URL_RET_PROGRESS_ABORT, URL_RET_IMAGE_DEFERRED, and URB_RF_IMAGE_PROBED. Wmg3Http returns ordinary transport results; URLFETCH consults the private job result to choose the BbxBrow completion path.

### 5. Replace mutable progress state and make ownership explicit

- Update GIF, JPEG, Fjpeg, and PNG paths to consume the stream whenever it is present, independently of the progress callback.
- Send immutable MimeGraphicProgress values. Resolve the callback client to BbxBrowImageJob only inside BbxBrow.
- Move NameToken and cache-token creation, replacement, and release into BbxBrow helpers operating on the locked job.
- Replace queued public progress-data copies with a BbxBrow-private queue record. Preserve coalescing by job identity, VM file, and bitmap while the job is alive, but make queued records independent of job lifetime.
- Add small ImpGraph-internal helpers that establish a newly current bitmap and mark it importer-owned only when the VM file or bitmap changes, record successful callback adoption, and free a chain only while importer-owned.
- Treat a TRUE progress-callback result as the ownership transfer. Do not infer ownership from callback history, matching stale fields, or cache-token state.
- Apply the rule to decoder errors, aborted partial images, GIF composition, GrCompactBitmap replacement, final publication, and paths where no progress callback fires.
- On compaction, leave a client-owned old chain with ObjCache and treat the new compacted chain as importer-owned until BbxBrow adopts it.
- Audit every exit so each chain has exactly one owner and every cache reference acquired for a queued update is released.

### 6. Final cleanup and contract checks

- Remove obsolete LPD_ and IPD_ names, dead PROGRESS_DISPLAY branches, compatibility macros, reserved fields, old exports, comments, and unused globals.
- Add EC assertions for job-block and chunk validity, LMem job lifetime, stream-slot bounds and ownership, memory-stream operation limits, worker selection, shutdown completion, callback ownership transitions, and exactly-once job cleanup.
- Run repository-wide searches and confirm no affected PROGRESS_DISPLAY OFF implementation, ALLOW_FETCH_WHILE_IMPORTING branch, G_fetchWhileImport use, old MIME entry, legacy URL progress result, or browser-specific public-field dependency remains.
- Verify diffs with git diff --ignore-space-at-eol and preserve every file's existing line endings.

## Validation

- After each compilable step, build the touched components from Installed with pmake -L 4 full, regenerating dependencies only when required.
- Final EC and non-EC builds cover BbxBrow including AB, ImpGraph including FJPEG, Wmg3Http, Wmg3Ftp, Wmg3Ext, Ijgjpeg, Fjpeg, ImpDoc, PicAlbum, and GPCMail.
- Exercise local GIF/JPEG/PNG imports with NULL options; empty, missing, incorrect, and correct MIME values; progressive GIF/JPEG/PNG; small images; accepted and deferred probes; abort during fetch and import; published partial-image cancellation; compaction after publication; ObjCache enabled and disabled; and concurrent fetch children.
- Saturate all progressive stream/import slots and verify that later fetches continue, use ordinary file import, and do not exceed the configured worker and stream bounds.
- Exercise reads and writes at block boundaries, two-block operations, stream reset and discard, the cumulative-capacity boundary, short allocation, and allocation failure.
- Exercise allocation failure and shutdown with queued, fetching, and importing jobs. Verify that G_allocBlock is not freed early and that an LMem job chunk is neither leaked nor freed twice.
- Use Swat to verify job-optr validity, LMem lock boundaries, worker and stream-slot ownership transitions, shutdown semaphore balance, progress-queue references, ObjCache reference counts, VM-chain ownership, and absence of leaked VM blocks.
- Final acceptance requires identical rendered image results, successful EC and non-EC builds, continued fetching during imports, bounded fallback under slot saturation, no busy wait, no double-free or orphaned chain, no leaked job chunk or global handle, and no ImpGraph or Wmg3Http dependency on BbxBrow state.

## Assumptions

- The cited revisions are the intended baseline; later decoder error-path fixes are retained.
- Repository-wide source inspection identifies BbxBrow, PicAlbum, and GPCMail as the relevant ImpGraph clients. ImpDoc and all in-tree URL drivers are rebuilt because they share the changed public driver headers.
- Compatibility with third-party MIME and URL drivers is intentionally dropped. Protocol major bumps make incompatibility explicit and safe.
- G_allocBlock remains alive until all BbxBrowImageJob chunks are released. Shutdown must enforce this in EC and non-EC builds.
- Existing fetchWhileImport INI values are intentionally ignored after the refactor because fetching while importing is unconditional.
- The private memory stream remains justified despite the native GEOS stream API because progressive decoders require retained prefix data and rewind-like operations beyond the native stream's 32 KB limit.
