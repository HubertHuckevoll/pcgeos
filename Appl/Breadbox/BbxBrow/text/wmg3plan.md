Yes. After comparing WMG3HTTP with `split/04-intelligent-image-loading-file-probe`, I think the two mechanisms fit together very cleanly — provided we treat them as **two separate gates**.

## Mental model: the existing branch

The current intelligent-image path is essentially:

```text
HTML <IMG>
   │
   ▼
Html4Par
HTMLimageData
   │
   ▼
BbxBrow URLTextClass
MSG_URL_TEXT_PROCESS_GRAPHICS
   │
   ├─ Automatic mode
   │      imageMaxPixels = 0
   │
   └─ Intelligent mode
          imageMaxPixels = 800*600
   │
   ▼
ProcessSingleGraphic()
   │
   ▼
URLFetchRequest()
   │
   ▼
URL fetch worker
   │
   ▼
LoadURLToFile()
   │
   ├─ source-cache hit ───────────────┐
   │                                  │
   └─ cache miss                     │
          │                           │
          ▼                           │
     LoadURLByDriver()                │
          │                           │
          ▼                           │
       WMG3HTTP                       │
          │                           │
          └── downloads whole file ──┘
                                      │
                                      ▼
                         ImportThreadRequestImportGraphic()
                                      │
                                      ▼
                         MimeDrvGraphicEx2 (entry 4)
                                      │
                           intrinsic area <= 480k pixels?
                              │               │
                             yes              no
                              │               │
                              ▼               ▼
                    streamed progressive  DEFER_LIKE_GRAPHICS
                    import                (buffered stream data
                                              │            is discarded)
                                              ▼
                                       HTML_IDF_COMPACT
                                              │
                                              ▼
                                     clickable [image GIF]
```

The crucial thing is that **the pixel protection happens at import time,
after the download**.

`ImportG.goc` receives `imageMaxPixels` and always starts the real import. The MIME drivers enforce the pixel budget themselves (MIME entry 4, `MimeDrvGraphicEx2`): after reading the format header and before any bitmap work, an image whose width exceeds `maxPixels / height` is rejected with `MIME_STATUS_DEFERRED` and no bitmap. Constrained GIF/JPEG imports stream from the network like unconstrained ones; when the import defers, the buffered stream data is discarded via `LPCT_DISCARD` and the fetch keeps running. Either way the browser then sends `MSG_URL_TEXT_INTERNAL_DEFER_LIKE_GRAPHICS`, and supported decoders display scanline updates while importing.

Html4Par then represents that state using the already-existing `HTML_IDF_COMPACT`. There is no special "too large" image type. That's good architecture.

And the current override is also quite elegant. Activating a compact image eventually reaches:

```text
MSG_HTML_TEXT_ACTIVATE_COMPACT_IMAGE
        ↓
MSG_URL_TEXT_LOAD_IMAGE
        ↓
ProcessSingleGraphic(... imageMaxPixels = 0)
```

So the second attempt bypasses the pixel admission policy.

Even better, that retry deliberately uses `ULM_CACHE`, not `ULM_ALWAYS`. Thus if the image was already downloaded and merely rejected by the **pixel** limit, clicking it imports the cached file instead of downloading it again.

That behavior must survive this patch.

---

# Where WMG3HTTP fits

WMG3HTTP itself has a very simple conceptual pipeline:

```text
URLDrvMain(URLRequestBlock)
        │
        ├─ allocate T_HTTPConnection
        ├─ copy URL/file/callback/etc.
        │
        ▼
HTTPGet()
        │
        ├─ resolve/connect
        ├─ send GET
        │
        ▼
header()
        │
        ├─ response code
        ├─ Content-Length
        ├─ Content-Type
        ├─ chunked
        ├─ caching headers
        └─ redirects
        │
        ▼
HTTPGet()
        │
        ├─ FileCreate()
        │
        └─ loop:
             SocketGetBlock()
                    ↓
             FileWrite()
                    ↓
             length += i
```

This gives us two excellent enforcement points.

For a known `Content-Length`, WMG3HTTP can reject the response **before `FileCreate()` and before reading the body**.

For missing `Content-Length` or chunked transfer, it can enforce the same cap inside the existing receive loop, immediately before `FileWrite()`.

Chunking is not a problem. `SocketGetBlock()` already strips the chunk framing; the outer loop sees actual entity bytes. So `length` is exactly what we want to limit.

There is one trap: **don't implement the check inside `header()` itself.** `header()` is also used to parse the HTTP response to an HTTPS proxy `CONNECT`. Putting the policy there would mix content-download policy into connection establishment.

The check belongs immediately after the final response `header()` call in `HTTPGet()`.

## The design I recommend

I would make the URL-driver mechanism generic, not image-specific.

So **not**:

```c
ERR_IMG_TOO_BIG
```

but:

```c
#define URL_RET_TOO_LARGE 105
```

And add two request flags without changing `URLRequestBlock` itself:

```c
#define URB_RQ_LIMIT_SIZE         0x0002
#define URB_RQ_IGNORE_SIZE_LIMIT  0x0004
```

That is important. Adding another field such as `URB_maxDownloadSize` would change the shared URL-driver ABI. Adding two unused bits to the existing `URB_reqFlags` doesn't.

It also gives sane semantics:

```text
LIMIT_SIZE=0                      ordinary request; old behaviour
LIMIT_SIZE=1                      enforce configured WMG3HTTP cap
LIMIT_SIZE=1 + IGNORE_SIZE_LIMIT  explicit user override; download anyway
```

`IGNORE_SIZE_LIMIT` wins if both somehow appear.

I would configure WMG3HTTP with something like:

```ini
[http]
downloadSizeLimitKB = 512
```

with WMG3HTTP itself defaulting to `0 = disabled`. The Breadbox product template can enable 512 KiB. That means other WMG3HTTP users don't suddenly acquire a new limitation just because they got a newer library.

No URL-driver protocol bump is necessary: the request structure remains binary-compatible, old drivers simply ignore the unfamiliar bits, and old clients never set them.

## The combined intelligent-image pipeline

Then intelligent mode becomes:

```text
                 INTELLIGENT IMAGE REQUEST
                           │
                           ▼
                  URB_RQ_LIMIT_SIZE
                           │
                           ▼
                       WMG3HTTP
                           │
              ┌────────────┴─────────────┐
              │                          │
       Content-Length known       length unknown/chunked
              │                          │
       > configured cap?          receive block
              │                          │
          yes │                   total > cap?
              │                          │
              ▼                          ▼
       URL_RET_TOO_LARGE          URL_RET_TOO_LARGE
              │                          │
              └────────────┬─────────────┘
                           ▼
                        BbxBrow
                           │
             INTERNAL_DEFER_LIKE_GRAPHICS
                           │
                           ▼
                   HTML_IDF_COMPACT
                           │
                       user clicks
                           │
                           ▼
              IGNORE_SIZE_LIMIT + ULM_CACHE
                           │
                           ▼
                    download/import
```

If the compressed file is small enough to download but has enormous intrinsic dimensions, it passes WMG3HTTP and then gets rejected by the import-time pixel admission in ImpGraph.

So we get:

```text
Gate 1: HTTP bytes       protects bandwidth + disk/cache
Gate 2: image pixels     protects decoder + memory + rendering
```

That separation is excellent.

There is also a lovely consequence of how your current code is structured. Intelligent mode currently gives `imageMaxPixels` only to ordinary inline images:

```c
p->pos < HTML_IMAGE_POS_RESERVED ?
    imageMaxPixels : 0
```

Background images therefore bypass the existing pixel gate. If the new HTTP-limit flag is derived from the same intelligent-image decision, backgrounds automatically retain their current "always load" behavior. No second background-image special case is needed.

## One subtle browser change

I would **not** use the existing `forceLoad` argument as the new override.

`forceLoad` currently controls this:

```c
forceLoad ? ULM_ALWAYS : ULM_CACHE
```

That's source-cache policy.

The new flag answers a different question:

> Should the HTTP size safety limit apply?

Those need to remain orthogonal.

Otherwise clicking a pixel-deferred image would use `ULM_ALWAYS`, unnecessarily download the same image again, and destroy one of the nicest properties of your current implementation.

So BbxBrow should gain an internal `URLFetchFlags` word propagated alongside `loadMode`, something like:

```c
#define UFF_NONE               0x0000
#define UFF_LIMIT_SIZE         0x0001
#define UFF_IGNORE_SIZE_LIMIT  0x0002
```

`LoadURLByDriver()` translates those into `URB_reqFlags`.

There is one PC/GEOS-specific thing Codex needs to be very careful about: `T_fetchEngineChild` is duplicated between `URLFETCH.goc` and `LoadURL.goc`. The `LoadURL.goc` copy even says it "must match." If another field is introduced, both declarations need identical field order. In fact the current `LoadURL.goc` copy is already missing the `referer` member that exists in the real structure; that code is presently behind disabled `#if ... && 0`, but while touching this area I would restore exact structural parity.

## What Html4Par needs

Very little — and that's a positive result.

I would **not add `HTML_IDF_TOO_LARGE`** or a second compact-placeholder state.

`HTML_IDF_COMPACT` already means what we need: "this image is intentionally represented as an explicit load action rather than rendered."

Likewise `MSG_HTML_TEXT_ACTIVATE_COMPACT_IMAGE` already gives us the UI gesture required for the override.

So the production changes belong primarily to WMG3HTTP and BbxBrow. Html4Par's current compact-image machinery should simply be reused and regression-tested.

That makes these two patches complement each other rather than becoming entangled.

Here's the Codex-ready plan. I’ve made one concrete configuration choice: **512 KiB default for the Breadbox product, 0/disabled inside WMG3HTTP when no INI setting exists**.

# WMG3HTTP download-size limit integrated with intelligent image loading

## Goal

Extend the current `split/04-intelligent-image-loading-file-probe` implementation so Intelligent Image Loading can reject oversized HTTP image downloads before importing them, while preserving the existing import-time pixel admission and allowing explicit user actions to override both restrictions.

The two limits must remain independent:

```text
HTTP download-size limit
    -> protects transfer/cache/disk

ImpGraph intrinsic-pixel limit
    -> protects image import/memory/rendering
```

A user-activated compact image must bypass the download-size limit without unnecessarily bypassing the existing source cache.

## Important existing behavior to preserve

The current branch already implements intelligent image import limiting.

`MSG_URL_TEXT_PROCESS_GRAPHICS()` sets `imageMaxPixels = INTELLIGENT_IMAGE_MAX_PIXELS` only for ordinary inline images in Intelligent mode.

`ProcessSingleGraphic()` downloads/caches the source file.

`ImportThreadEngineClass::MSG_IMPORT_THREAD_ENGINE_IMPORT_GRAPHIC` always imports and passes `imageMaxPixels` into the driver.

If the constrained import reports `MIME_STATUS_DEFERRED` (or a constrained `MIME_STATUS_MEMORY_LIMIT` with no bitmap), it discards any buffered stream data via `LPCT_DISCARD` and sends `MSG_URL_TEXT_INTERNAL_DEFER_LIKE_GRAPHICS`, which marks matching images `HTML_IDF_COMPACT`. The HTTP transfer itself is not cancelled.

If the driver accepts the image, the import proceeds with progress callbacks enabled. For streamed imports, geometry-changing first updates schedule the existing waiting-image layout pass, after which subsequent scanline ranges are drawn progressively while the HTTP download continues.

Activating a compact image reaches `MSG_URL_TEXT_LOAD_IMAGE()`, which calls `ProcessSingleGraphic()` with `imageMaxPixels == 0`.

This retry currently uses `ULM_CACHE`. Preserve that. A pixel-deferred image may already exist in the source cache and must not be redownloaded merely because the user activates it.

Do not repurpose the existing `forceLoad` parameter for the new size-limit override. `forceLoad` controls source-cache/reload policy through `ULM_ALWAYS`; the new override controls transport-size policy.

## Shared URL-driver API

Modify `CInclude/htmldrv.h`.

Add two unused `URB_reqFlags` bits after `URB_RQ_ALWAYS`:

```c
#define URB_RQ_ALWAYS             0x0001
#define URB_RQ_LIMIT_SIZE         0x0002
#define URB_RQ_IGNORE_SIZE_LIMIT  0x0004
```

Add a generic failure return code after `URL_RET_AUTHORIZATION`:

```c
#define URL_RET_TOO_LARGE         105
```

Do not add fields to `URLRequestBlock`.

Do not call the result `IMG_TOO_BIG`: the URL driver is enforcing transfer size, not image dimensions.

Do not bump `URL_DRV_PROTOMAJOR` or change structure layout. This is a backwards-compatible flag/return-code extension. Older drivers may ignore the new request bits; in that case the import-time pixel admission remains the fallback protection.

## WMG3HTTP request state and configuration

Modify:

```text
Library/Breadbox/UrlDrv/Wmg3Http/wmg3con.goh
Library/Breadbox/UrlDrv/Wmg3Http/WMG3HTTP.goc
```

Add the request flags to private connection state, near the existing token/callback request state:

```c
WordFlags reqFlags;
```

In `URLDrvMain()`, copy:

```c
p_conn->reqFlags = req->URB_reqFlags;
```

Do not change connection allocation semantics; `T_HTTPConnection` is internal to WMG3HTTP.

Add a WMG3HTTP configuration value:

```c
word downloadSizeLimitKB = 0;
```

Read it from:

```ini
[http]
downloadSizeLimitKB = ...
```

during `Initialize()` using the same `InitFileReadInteger()` style already used in WMG3HTTP.

Semantics:

```text
0               no limit
N               N * 1024 bytes
```

Keep the internal default at zero so products without the new INI setting retain historical behavior.

In the Breadbox product template:

```text
Tools/build/product/bbxensem/Template/geos.ini
```

enable:

```ini
[http]
downloadSizeLimitKB = 512
```

Merge with an existing `[http]` category if one exists; do not create a duplicate category.

Create a small local helper in `WMG3HTTP.goc` expressing policy rather than duplicating bit tests:

```c
Boolean DownloadSizeLimitActive(T_HTTPConnection *p_conn)
{
    return downloadSizeLimitKB &&
           (p_conn->reqFlags & URB_RQ_LIMIT_SIZE) &&
           !(p_conn->reqFlags & URB_RQ_IGNORE_SIZE_LIMIT);
}
```

Use dword arithmetic when converting KB to bytes:

```c
(dword)downloadSizeLimitKB * 1024L
```

## WMG3HTTP known-Content-Length rejection

Do not put the size decision in `header()`.

`header()` is also used for the HTTPS proxy `CONNECT` response. Keep it as the generic HTTP-header parser.

Implement the known-size check in `HTTPGet()` immediately after the final response-header loop:

```c
while (responseCode == 100)
    rcode = header(conn, &contentlength, &responseCode);

p_conn = ConnectionLock(conn);
```

and before `FileCreate()` or body reception.

Apply the test only when:

```text
URLRequestGetRet(rcode) == URL_RET_FILE
DownloadSizeLimitActive(p_conn) == TRUE
contentlength != CL_UNKNOWN
```

Reject only when the total expected downloaded data is strictly greater than the configured limit. Exactly-at-limit is allowed.

Account for `resumePos` when `GET_RANGE` is enabled so a resumed transfer cannot bypass the total limit.

On rejection:

```c
rcode = URLRequestMakeRet(URL_RET_TOO_LARGE) | URB_RF_NOCACHE;
p_conn->allowSocketCache = FALSE;
```

Do not create the destination file.

Do not create an HTML error message.

Do not consume the response body merely to preserve HTTP keep-alive.

The existing persistent-connection fallback currently drains bodies for non-file responses using `SocketGetBlock(..., TRUE)`. Change that branch so `URL_RET_TOO_LARGE` skips this drain.

Because `allowSocketCache` is FALSE, let the existing socket-cache cleanup remove any cached socket entry and close the connection normally. Do not invent a second socket-close path.

## WMG3HTTP unknown/chunked-length enforcement

Keep the existing outer receive loop and `SocketGetBlock()` chunk handling.

Immediately before each `FileWrite()` calculate whether writing the next block would make the total response exceed the configured byte limit.

Use dword arithmetic and include `resumePos` when applicable.

Conceptually:

```c
if (DownloadSizeLimitActive(p_conn) &&
    totalBytesAfterThisBlock > sizeLimitBytes)
{
    rcode = URLRequestMakeRet(URL_RET_TOO_LARGE) | URB_RF_NOCACHE;
    p_conn->allowSocketCache = FALSE;
    break;
}
```

Perform this check before `FileWrite()`. Never write bytes past the configured cap.

The existing non-success cleanup should delete the partial temporary file. Verify this for both normal and `GET_RANGE` builds rather than adding duplicate deletion logic.

This per-block check must run even if `Content-Length` was present, so a lying or malformed server cannot exceed the configured limit by sending more data than declared.

For a size-limited request, disable progressive loading from the network stream before receiving the body. Intelligent-mode requests already pass no loading-progress callback, but WMG3HTTP should not allow a generic caller to stream partial image data and later return `URL_RET_TOO_LARGE`.

Do not disable post-download local-file import progress. After WMG3HTTP returns the completed file and the import-time pixel admission accepts it, the existing import-progress callback and waiting-image layout path must display supported formats incrementally while decoding.

Use the same semaphore-safe callback disabling pattern already used by the `contentlength < progressMinCL` path.

Requests carrying `URB_RQ_IGNORE_SIZE_LIMIT` must retain normal progressive behavior.

## BbxBrow fetch-policy plumbing

Modify:

```text
Appl/Breadbox/BbxBrow/urlfetch.goh
Appl/Breadbox/BbxBrow/urlfetch/URLFETCH.goc
Appl/Breadbox/BbxBrow/htmlview.goh
Appl/Breadbox/BbxBrow/htmlview/LoadURL.goc
Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc
```

Introduce a fetch-policy word separate from `loadMode`:

```c
typedef WordFlags URLFetchFlags;

#define UFF_NONE               0x0000
#define UFF_LIMIT_SIZE         0x0001
#define UFF_IGNORE_SIZE_LIMIT  0x0002
```

Do not encode these bits into `ULM_NEVER`, `ULM_CACHE`, or `ULM_ALWAYS`.

`ULM_*` remains source-cache policy.

`UFF_*` becomes transport policy.

Propagate `URLFetchFlags fetchFlags` through:

```text
URLFetchRequest()
MSG_URL_FETCH_ENGINE_GET_URL
T_fetchEngineChild
URLFetchChildThread
LoadURLToFile()
LoadURLByDriver()
```

Use aihelp.py to scan for
"URLFetchRequest" in BbxBrow
"LoadURLToFile" in BbxBrow
"LoadURLByDriver" in BbxBrow

and update every caller explicitly. Ordinary non-image requests pass `UFF_NONE`.

Do not rely on implicit zero stack arguments.

`T_fetchEngineChild` has duplicated declarations in `URLFETCH.goc` and `htmlview/LoadURL.goc`. Make their field sequence identical while adding `fetchFlags`.

The canonical sequence around this area must include:

```c
NameToken url;
word loadMode;
URLFetchFlags fetchFlags;
HTMLFormDataHandle postData;
NameToken referer;
optr ackObject;
Message ackMessage;
dword extraData;
void *abortRoutine;
```

The current `LoadURL.goc` mirror is missing the `referer` member that exists in `URLFETCH.goc`. Restore exact structural parity while touching this definition even though its current runtime use is behind disabled code.

## Translate browser fetch flags to URL-driver flags

In `LoadURLByDriver()`, preserve the existing:

```c
req->URB_reqFlags = URB_RQ_ALWAYS;
```

Then OR in the transport policy:

```c
if(fetchFlags & UFF_LIMIT_SIZE)
    req->URB_reqFlags |= URB_RQ_LIMIT_SIZE;

if(fetchFlags & UFF_IGNORE_SIZE_LIMIT)
    req->URB_reqFlags |= URB_RQ_IGNORE_SIZE_LIMIT;
```

Do not alter `URB_RQ_ALWAYS` semantics.

Do not change `URLRequestBlock` layout.

## Intelligent image requests

In `URLTEXT.goc`, extend the internal `ProcessSingleGraphic()` interface with a separate boolean indicating explicit size-limit override, e.g.:

```c
Boolean ignoreDownloadSizeLimit
```

Do not reuse `forceLoad`.

Build `URLFetchFlags` inside `ProcessSingleGraphic()`.

For ordinary Intelligent-mode inline images, `imageMaxPixels != 0` already identifies the requests that participate in intelligent limiting. Set:

```c
UFF_LIMIT_SIZE
```

for those requests.

Do not set it for backgrounds, because their current `imageMaxPixels` is zero and they intentionally bypass the intelligent-image restriction.

Do not set it for normal Automatic mode.

When `ignoreDownloadSizeLimit` is TRUE, add:

```c
UFF_IGNORE_SIZE_LIMIT
```

Explicit override wins if both flags are present.

Preserve the existing behavior: Intelligent limited requests may import streamed constrained GIF/JPEG data concurrently with network loading, but a deferred import discards the buffered stream data, and accepted images use progressive display after the import-time pixel admission succeeds.

## Compact-image activation

`MSG_URL_TEXT_LOAD_IMAGE()` is the explicit per-image override.

Keep:

```text
loadMode = ULM_CACHE
imageMaxPixels = 0
```

and call `ProcessSingleGraphic()` with:

```text
ignoreDownloadSizeLimit = TRUE
```

This produces the desired two cases.

Case A: the source file had already downloaded but exceeded the intrinsic-pixel limit. `ULM_CACHE` reuses the existing source file, no HTTP transfer occurs, and `imageMaxPixels == 0` forces import.

Case B: WMG3HTTP rejected the original transfer because the encoded file itself was too large. There is no source-cache file, so `ULM_CACHE` falls through to HTTP. `UFF_IGNORE_SIZE_LIMIT` becomes `URB_RQ_IGNORE_SIZE_LIMIT`, and WMG3HTTP downloads the complete file.

Do not switch this path to `ULM_ALWAYS`.

## Explicit "Load Graphics" command

`MSG_URL_FRAME_LOAD_GRAPHICS()` currently calls:

```c
MSG_URL_TEXT_PROCESS_GRAPHICS(FALSE, TRUE)
```

where `bypassIntelligent == TRUE`.

Treat this explicit user operation as an override of the transfer-size gate as well as the intrinsic-pixel gate.

Pass `ignoreDownloadSizeLimit = bypassIntelligent` from `MSG_URL_TEXT_PROCESS_GRAPHICS()` to `ProcessSingleGraphic()`.

A normal page reload with `forceLoad == TRUE` but `bypassIntelligent == FALSE` must still obey Intelligent-mode limits. Reloading the page is not the same as explicitly asking to load a deferred image.

Switching from Intelligent mode to Automatic mode naturally stops setting `UFF_LIMIT_SIZE`; do not add another special case.

## Handle URL_RET_TOO_LARGE in image acknowledgement

Modify:

```text
URLTextClass::MSG_URL_TEXT_GRAPHIC_FETCHED
```

After retrieving:

```c
ret = URLRequestGetRet(result.retType);
```

handle `URL_RET_TOO_LARGE` before the generic failure branch.

For an Intelligent-mode limited request, send:

```c
MSG_URL_TEXT_INTERNAL_DEFER_LIKE_GRAPHICS(
    request.nameT,
    resultFormatFlags);
```

then decrement pending count normally.

Do not mark the image broken.

Do not show an HTTP error page.

Do not synthesize `OCT_NULL` replacement graphics.

The MIME header has already been parsed by WMG3HTTP before the rejection, so continue using the current MIME/format detection to populate `resultFormatFlags`.

Use `request.imageMaxPixels != 0` as the assertion that this was an intelligent limited image request. An unexpected `URL_RET_TOO_LARGE` on an explicit forced request should follow the generic failure path rather than silently re-entering the compact state forever.

`MSG_URL_TEXT_INTERNAL_DEFER_LIKE_GRAPHICS` already updates all matching image instances and marks them `HTML_IDF_COMPACT`; reuse it unchanged.

## Html4Par

Do not add a second "download too large" image flag.

Do not add `HTML_IDF_TOO_LARGE`.

Do not change `HTMLimageData` layout.

Reuse:

```text
HTML_IDF_COMPACT
MSG_HTML_TEXT_ACTIVATE_COMPACT_IMAGE
MSG_HTML_TEXT_SET_IMAGE_LOAD_MODE
CompactImageLayoutText()
```

for both kinds of intelligent deferral.

The compact placeholder means "explicit load required", regardless of whether the original reason was encoded download size or intrinsic pixel size.

No Html4Par protocol/incminor change is required unless implementation unexpectedly changes an exported structure or message.

## Regression fixture

Keep:

```text
Library/Breadbox/Html4Par/htmtest/cmpimage.htm
```

as the primary intelligent-image regression page.

The existing assets are particularly useful:

```text
limit.png    765 bytes, 800x600
small.jpg   1973 bytes, 160x120
large.gif   2380 bytes, 801x600
```

Add a short test note to `cmpimage.htm` explaining the HTTP download-size test; do not change the meaning of the existing intrinsic-pixel tests.

Serve this directory through HTTP when testing WMG3HTTP. Loading it as `file:` does not exercise the HTTP driver.

## Required behavioral tests

1. Set `downloadSizeLimitKB = 2`.

   Serve `cmpimage.htm` through HTTP in Intelligent mode.

   `limit.png` and `small.jpg` must download normally, pass the import-time pixel admission, and display progressive scanline updates while importing.

   `large.gif` must return `URL_RET_TOO_LARGE` before full download and appear as the compact image UI.

   Activating `large.gif` must download it despite the 2 KiB cap and import it.

2. Set `downloadSizeLimitKB = 3`.

   `large.gif` must now download successfully because 2380 bytes is below 3 KiB.

   Its 801x600 intrinsic dimensions must then trigger the import-time pixel admission and compact UI.

   It must not produce import-progress display before entering the compact state.

   Activating it must reuse the source-cache file and must not require another HTTP transfer.

   This is the critical integration test proving that the two limits remain independent.

3. Set `downloadSizeLimitKB = 0`.

   Behavior must match the current branch exactly.

4. Test a response whose Content-Length is exactly the configured limit.

   It must be accepted.

5. Test a Content-Length one byte above the limit.

   WMG3HTTP must reject before `FileCreate()`/body download.

6. Test an HTTP/1.1 chunked or otherwise unknown-length response exceeding the limit.

   WMG3HTTP may receive data up to the threshold, but must never write beyond it, must delete the partial temporary file, return `URL_RET_TOO_LARGE`, and close rather than cache the socket.

7. Test a server that declares a Content-Length below the limit but sends excess data.

   The per-block check must still enforce the cap.

8. After rejecting an oversized response on a persistent connection, load another image from the same host.

   The next request must succeed; no closed socket may remain in the socket cache.

9. Test View -> Load Graphics on a size-deferred image.

   It must explicitly bypass both intelligent limits.

10. Test normal Automatic image mode.

    The new HTTP size limit must not apply.

11. Test page/background and table-background images.

    Preserve the current behavior: they bypass intelligent inline-image limiting.

12. Test duplicate `<IMG>` elements referencing the same oversized URL.

    They must enter and leave compact state together using the existing `*_LIKE_GRAPHICS` machinery.

13. Test an unsupported format.

    Preserve `HTML_IDF_UNSUPPORTED`; do not convert unsupported images into ordinary size-deferred images.

14. Test redirects.

    Do not apply the body-size decision to proxy `CONNECT` headers or intermediate redirect semantics; apply it to the final file response.

## Build checks

Build the shared headers/dependents and the three affected modules from the branch:
- Wmg3Http
- Html4Par
- BbxBrow

Use `aihelp` to compile as described in the AGENTS.md.
Use the repository's normal EC and non-EC build workflow if wrappers exist in the current checkout.

At minimum verify both EC and non-EC variants because the changes touch shared request structures, asynchronous fetch state, persistent socket handling, and GOC message signatures.

Run:

```bash
git diff --check
```

and inspect the final diff specifically for duplicated struct ordering, request/message parameter ordering, exported/shared-header constants, and resource/export ordering.

## Expected files changed

```text
CInclude/htmldrv.h

Library/Breadbox/UrlDrv/Wmg3Http/wmg3con.goh
Library/Breadbox/UrlDrv/Wmg3Http/WMG3HTTP.goc

Appl/Breadbox/BbxBrow/urlfetch.goh
Appl/Breadbox/BbxBrow/urlfetch/URLFETCH.goc
Appl/Breadbox/BbxBrow/htmlview.goh
Appl/Breadbox/BbxBrow/htmlview/LoadURL.goc
Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc

Library/Breadbox/Html4Par/htmtest/cmpimage.htm

Tools/build/product/bbxensem/Template/geos.ini
```

No production Html4Par source change is expected. Its existing compact-image state and activation mechanism are the intended integration point.

Before editing, use `rg` to verify all `URLFetchRequest`, `LoadURLToFile`, `LoadURLByDriver`, `T_fetchEngineChild`, `URB_reqFlags`, and `URL_RET_*` call sites/definitions and adjust this file list if the current branch has moved them.

Keep the patch narrowly scoped. Do not refactor WMG3HTTP header parsing, URL caching, image state, or progressive-import architecture beyond what is required for the size gate.