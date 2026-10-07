# Inline SVG backing-file ownership

## Investigation of the current source

This investigation uses the current checkout, not an earlier inline-SVG implementation.

InitTransferItem in Library/Breadbox/Html4Par/htmlpars/parsinit.goc creates a
VM chain tree containing text, graphics, hypertext arrays and a local name pool.
FinishTransferItem saves that pool and chainifies the arrays. ParseHTMLFile
returns the item even when parsing is stopped, after finishing the partial page.

MSG_URL_FRAME_URL_FETCHED in Appl/Breadbox/BbxBrow/urlframe/FRFETCH.goc parses
into ObjCacheGetVMFile and registers the item as OCT_TEXTOBJ with ObjCacheAddURL.
The external-script retry path also uses FreeHTMLTransferItem to free an
unusable page, so external files follow the same destruction path.

MSG_URL_FRAME_FLIP_PAGE in urlframe/URLFRAME.goc locks the new cache token,
attaches the item to URLText, starts graphics and shows the page. It detaches
the old item before releasing its cache token. Html4Par attachment copies the
image array and loads the local name pool. MSG_HTML_TEXT_UPDATE_ITEM saves
those arrays back into the same item on detachment. Attachment clears image
resolution flags and graphic cache handles, allowing source images to reload.
The original image references survive in the image records and name pool.

ObjCacheUnlockItem retains cacheable unlocked pages. ObjCacheRemoveEntry is
the common final-destruction path for eviction, clearing and non-cacheable
items, and calls FreeHTMLTransferItem for text pages. That library routine
already frees external region DB items before freeing the VM chain. No
existing page-owned DOS-file table was found.

The object cache files can persist across restart, but ObjCacheCheckPersist
explicitly rejects OCT_TEXTOBJ. DetachFromObjCache removes unlocked text pages
before saving its index. The last cache client calls it from
RemoveCacheFileReference in init/INIT.goc. A cache left without a committed map
is discarded on attachment. Parsed pages therefore have session lifetime;
persistent source HTML can be parsed again. MSG_HTML_TEXT_STORE_CONTENTS is
currently disabled, so native-page saving does not copy these page resources.

ImpGraph ImpSVG opens the supplied filename and calls SvgImport on that file.
SvgImport accepts an optional pointer to a live Boolean cancellation flag after
its progress callback. SvgLib checks for nonzero between tags even without a
progress callback. ImpGraph casts its MS_mimeFlags pointer to the Boolean pointer
at this boundary: GEOS Boolean and MimeStatusFlags are signed and unsigned
16-bit words, and MIME_STATUS_ABORT is the only defined status flag.
Cancellation returns TE_ERROR with no output chain, and ImpGraph reports
IBS_IMPORT_STOPPED. The flag storage must remain valid and cancellation set
until the call returns.
Graphvwr and the SVG translator pass a null cancellation pointer, retaining
their existing progress callbacks and callback-based cancellation.
ImportThreadRequestImportGraphic queues requests on the existing serial
non-streaming import thread. Its temporary flag means delete after import and
must be false for page resources. Each outstanding inline request must lock
its exact owning page token, because navigation can detach that page before
the importer opens its file.

MSG_HTML_TEXT_RESOLVE_IMAGE updates geometry and dirties cells. BbxBrow's
MSG_URL_TEXT_DEC_PENDING calculates layout when the last request completes.
The waiting-image list can itself request layout on overflow, and an active
formatter can request another pass on image geometry changes. Inline images
should defer those intermediate requests while retaining dirty geometry for
the final existing layout call.

## Minimal representation

Add a separate local name token to HTMLimageData for the absolute backing
filename and one inline-image flag. imageURL remains empty; there is no
fabricated URL or SRC. A separate resource table or resource index would add
another lookup and ownership structure for no sharing benefit.

Capture only after identifying SVG, using the raw reader and a 1024-byte
sequential write buffer. The ordinary character reader is unchanged. Only
XML framing is recognized: quotes, comments, CDATA, processing instructions,
declarations, nested SVG and self-closing tags. HTML foreign-content breakout
tags outside foreignObject/title/desc return to the existing named-tag handler
without a replay buffer or a change to the character input routine. SvgLib interprets all shapes.

The image record owns the completed file. A partial capture deletes its file.
Final page destruction enumerates inline image filenames before freeing the
name pool and VM chain. Successful import, failure, temporary detachment and
cache placement retain the file. Import requests hold a page-cache reference
until the import thread has finished using the source. The existing thread
serializes imports and the existing pending count groups their final layout.
Inline graphics are not retained independently in the graphics cache: a freed
temporary filename may be reused, so it cannot identify an old cached graphic.

Temporary resources use SP_TEMP_FILES with absolute filenames and the native
.TMP suffix. The explicit image/svg+xml MIME request selects SvgLib regardless
of that suffix. Renaming the file would remove the basename reservation used
by FileCreateTempFile, allowing same-tick captures to collide. Keeping the
native temporary name also avoids a rename and retains the exact input file. No source
persistence layer is needed because parsed text entries are not persisted.
Unclean process termination cannot execute page destructors; these are
session temporary files, not persistent cache resources.

## Verification

Run perl Library/Breadbox/Html4Par/htmtest/check_inline_svg.pl. It compiles
extracted production scanner, destructor and cache-reference functions with
host I/O and VM shims. Checks include exact source bytes (case, CR/LF and UTF-8),
1024-byte writes, a 128 KB source, 200 icons, self-closing and nested SVG,
comments, CDATA, escaped text, processing instructions, declarations, ordinary
HTML recovery after an unclosed SVG, and integration elements containing HTML.
Injected creation/write/close/token/image-admission failures and parse aborts
verify that partial files disappear. Actual cache functions verify retention,
restore, eviction, shutdown persistence policy, and an outstanding import
reference surviving frame detachment. These shims do not execute GEOS messaging,
SvgLib rendering or asynchronous layout.

Generate runtime fixtures by passing --fixtures DIR to that check. Copy the
resulting .htm files into a GEOS-accessible directory. Use rebuilt Html4Par and
BbxBrow and other Html4Par consumers together: HTMLimageData gains a filename
token, requiring Html4Par protocol 4.0. Object-cache version 2.4 invalidates
older serialized image records.

The host checks pass. Standard EC and NC builds pass for Html4Par, BbxBrow
and the HTML translator. The additional Html4Par DBCS build compiles the
changed scanner and destructor but fails in unchanged htmlclas/htmlfedi.goc
at lines 1861 and 1864 with char/TCHAR pointer-type errors. Runtime rendering,
page-load performance and GEOS message ordering remain unverified.

Runtime checks still required, without launching PC/GEOS from this task:

1. Open nosvg.htm and verify ordinary text and entities. Compare repeated cold
   parses using the original and modified binaries, with identical EC/NC and
   graphics settings. Record elapsed parse time and median page-load time;
   the host icon timing printed by the check is not a GEOS benchmark.
2. Open one.htm, many.htm and large.htm with graphics loading enabled. Verify
   all admitted images, source files in SP_TEMP_FILES and one final pending-count
   layout. Repeat with graphics disabled, then enable graphics. Do not expect
   a complete reformat for every imported icon.
3. Open self.htm, nested.htm, comment.htm and cdata.htm. SvgLib decides whether
   each source produces drawable output; following HTML must remain intact.
   Open broken.htm and unclosed.htm and verify recovered following HTML and
   no retained partial SVG file. Unterminated quotes/comments/CDATA consume
   to EOF: interpreting embedded markup as HTML would truncate valid input.
4. With object caching enabled, leave many.htm while imports are queued.
   Source files remain while the import thread owns a page reference. Stop or
   close the page, clear its cache entry and confirm files disappear after the
   last import finishes or is canceled.
5. With parsed-page caching enabled and graphic retention disabled, navigate
   away and back. Verify the same backing filenames are used for direct
   reimport without reparsing HTML. Evict the parsed page with cache clearing
   and confirm every source file disappears. Repeat with object caching off.
6. Close the browser normally and inspect SP_TEMP_FILES. No page-owned files
   should remain. Restart and reopen the URL: source HTML is reparsed; parsed
   text items are not restored from the persistent object-cache index.

Do not claim runtime performance, rendering or race validation from host tests.
