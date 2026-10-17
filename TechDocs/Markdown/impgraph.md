# ImpGraph import API

CInclude/htmldrv.h defines the MIME graphic entry points. Both slot 0
(MimeDrvGraphic) and slot 3 (MimeDrvGraphicEx) use the same five arguments:

    ImageImportStatus _pascal MimeDrvGraphic(
        const ImageImportSource *sourceP,
        VMFileHandle destinationH,
        const ImageImportOptions *optionsP,
        const ImageImportUpdates *updatesP,
        ImageImportResult *resultP);

Source, destination, options and result are required. Updates are optional.
Descriptors, callbacks and their contexts are borrowed until the synchronous
call returns. ImpGraph constructs GEOS bitmaps, GStrings and animation chains
in the destination VM file. The destination is not an encoded byte stream.

## Source and options

ImageImportSource selects IIS_FILE with data.filenameP, or IIS_STREAM with
data.inputP pointing to an ImageInput descriptor from CInclude/impinput.h.
A file requires a nonempty filename. A stream requires a descriptor with a
callback. Invalid descriptors return IMAGE_IMPORT_INVALID; a stream never
falls back to opening a filename.

ImageImportOptions contains configuration only:

- mimeTypeP is a required MIME hint. An empty string probes raster formats.
- resolution uses MIME_RES_*; DISPLAY_DEFAULT consults display/INI settings.
- flags contains MIME_GREX_NO_ANIMATIONS and/or
  MIME_GREX_NO_SCANLINE_COMPRESS. Zero preserves the library's defaults.
  Unknown flag bits are invalid.
- watcherH optionally supplies allocation accounting. Zero uses a temporary
  unrestricted watcher. Result.usedMem describes the final image reservation;
  a supplied watcher remains charged for it until the caller releases it.
- cancelP optionally points to a live MimeStatus. Set MIME_STATUS_ABORT to
  request cancellation. A null pointer disables external cancellation.
- keepPartial explicitly permits incomplete results. It is independent of
  stream input and intermediate notifications. Zero discards incomplete final
  images, while preserving ownership of every earlier publication.

JPEG/FJPEG and the animation-capable GIF importer support streams, including
single-frame GIFs. The no-animation GIF path, PNG, WebP and SVG remain
file-based. Unsupported stream combinations return IMAGE_IMPORT_UNSUPPORTED.
The NO_ANIMATIONS flag does not disable JPEG streaming. Raster probing can
retry the retained prefix after a format rejection; after FJPEG starts
consuming stream data it cannot retry IJGJPEG from the beginning. File-based
FJPEG fallback remains available.

## Encoded input

ImageInput contains its historical movable callback and opaque clientDataP.
The callback uses Pascal calling convention and returns a byte count:

    word callback(void *clientDataP, ImageInputOperation operation,
                  void *bufferP, word size);

- IIO_READ reads up to size bytes and retains the first packet for probing.
- IIO_PEEK copies bytes without advancing the position.
- IIO_PRE_READ advances a temporary offset while retaining probe bytes.
- IIO_RESET resets probe state; it does not rewind consumed stream data.
- IIO_FLUSH_FIRST commits size retained bytes and resets probe state. GIF
  uses this between frames.

Read operations must never return more than size. Live producers wait for
the requested bytes or producer completion; zero means end of input.
Control operations receive no buffer and their return value is ignored.
The decoder borrows bufferP only for the duration of the input callback.

The historically named jpeg_init_loadProgress and fjpeg_init_loadProgress
exports still accept ImageInput. Their public signatures and export ordinals
are unchanged by the five-argument MIME migration.

## Updates and ownership

ImageImportUpdates contains only a typed callback and clientDataP. A null
updatesP disables notifications; a supplied descriptor requires a callback.
ImpGraph invokes it synchronously on the importing thread through
ProcCallFixedOrMovable_pascal:

    void callback(void *clientDataP, const ImageImportUpdate *updateP);

The output-only description contains vmFile, bitmap, info and inclusive
firstLine/lastLine. Every delivered range satisfies
0 <= firstLine <= lastLine < info.IAD_size.XYS_height. Short JPEG/PNG slices
start at zero rather than wrapping. GIF describes the actual frame bitmap's
dimensions, which can differ from the final composite or logical screen.

Each first callback for a distinct (VM file, image handle) transfers cleanup
responsibility to the caller. Repeated updates of the same image do not
transfer it again. The caller must retain every published image until the
import returns: ImpGraph can continue reading or writing it. ImpGraph never
frees published chains during errors, cancellation, replacement or compaction.
It still frees private images and decoder working resources.

The description is borrowed only during the callback. Queue copied values
and a protected image reference, never the descriptor or request-context
pointer. Failure to allocate a queued notification does not undo ownership
transfer. If ImpGraph cannot allocate its private publication record, it
skips that notification before any transfer; final-result delivery remains
available. Notifications are optional, not guaranteed for every row.

The final image can be an already-published image or a distinct image. An
identical result does not transfer ownership twice. A distinct final image
becomes caller-owned on return. Failure, cancellation and a null final result
do not revoke ownership of earlier publications. After return, release images
that display or queued work no longer need. Keep the destination VM file open
until the last image user finishes.

GIF publishes only its first raw frame. Animation assembly uses a separate
working composite and copies/compacts frames into the final chain. Published
previews are not also embedded as caller-owned children of that chain.

Updates describe live images. They are not snapshots or a whole-image lock.
HugeArrayLock and HugeArrayLockDir reach VMLock's thread grab/release locking;
GIF releases raster locks before returning to its publishing C wrapper.
Interlaced rewrites and bitmap-directory changes retain those native locks.
Callers must use the normal GEOS graphics/VM APIs for concurrent access.

## Final status and result

ImpGraph clears ImageImportResult before validation and work. Its fields are
bitmap, info and usedMem. A null bitmap leaves the entire result zeroed.

- IMAGE_IMPORT_SUCCESS returns a non-null complete image.
- IMAGE_IMPORT_PARTIAL returns a non-null incomplete image with keepPartial.
- IMAGE_IMPORT_CANCELED reports the cancellation input. Its result can be
  null, complete, or incomplete when keepPartial permits it.
- IMAGE_IMPORT_FAILURE returns no final image after decode/resource failure
  or rejection of an incomplete image by policy.
- IMAGE_IMPORT_INVALID reports invalid required arguments/descriptors.
- IMAGE_IMPORT_UNSUPPORTED reports unsupported source/format combinations.

Fatal JPEG errors return no final image, even after scanline publication.
PNG decode errors likewise return no final image. Earlier publications remain
caller-owned. Truncated input can yield an incomplete image under keepPartial;
a partial image is never reported as complete merely because a callback exists.

## BbxBrow integration

The independent Boolean INI entries in [HTMLView] both default TRUE:

- progressLoading enables eligible GIF/JPEG imports during download.
- progressDisplay enables intermediate display, including completed files.

Position, minimum-height and HTTP eligibility restrictions still apply to
streaming. Disabling either setting does not disable the other. BbxBrow owns
download buffers, routing, cancellation, cache references and display policy.
Its worker binds the synchronous callback context after copying the queued
request. Fetch/import barriers retain borrowed download state until return.
Pending counts, name tokens and source-page references retain their existing
completion owners.

Each request retains all published cache tokens in small linked blocks.
There is no fixed image-count limit. Retention uses the cache's native no-error
allocation policy, so an ownership record cannot be silently dropped on OOM.
Queued snapshots hold independent references; coalesced updates share one.
They contain only copied identities/ranges and can outlive the request.
After import returns, the request releases its references; queued/display
users keep theirs. Final completion refreshes cache metadata and redraws the
whole final image, including formats that never publish intermediate updates.
Stop preserves displayed partial updates through the existing cancellation
receiver; the explicit keepPartial option no longer depends on notifications.

## Compatibility and validation

This is a coordinated ABI change. Rebuild and install ImpGraph, ImpDoc,
BbxBrow, PicAlbum and GPCMail together. MIME major is 6. Graphic slots keep
ordinals 0 and 3; slot 3 now takes flags through options, with no trailing
legacy argument. Text/info slots and their behavior are unchanged. IJGJPEG
remains major 7 and FJPEG major 1; this migration does not bump them again.

The runnable check Appl/Breadbox/BbxBrow/tests/check_import_callbacks.pl
executes source-backed publication, JPEG cleanup, PNG import, GIF frame
handling, browser retention/queue receipt, input adapters/readers and MIME
validation/dispatch with host resource shims. It covers post-publication
failure, cancellation, replacement, repeated/same/distinct results, record
and notification OOM, retained-prefix probing and end of input. Other browser
checks cover routing, pending/name cleanup, picture fallback and stream waits.
WebpLib corpus checks and SvgLib's cancellation check cover their adapters.
These checks and native builds do not establish GEOS scheduling or full
rendering correctness. PC/GEOS is not run for these checks.
