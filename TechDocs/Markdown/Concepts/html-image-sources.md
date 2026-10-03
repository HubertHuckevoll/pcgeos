# Image source selection in Html4Par

Html4Par selects image URLs during parsing. BbxBrow's ordinary image loading,
cache, import and drawing paths receive the selected URL. Selection does not
change image geometry or create a separate picture image record.

## Parser interface

ParseAnyFileWithImageSources has the same arguments and result as ParseAnyFile,
followed by an HTMLImageSourceContext pointer. Passing a null context retains
the existing parser entry's behavior. Plain-text parsing ignores the context.
The entry is appended under the HTMLImageSources protocol minor.

HTMLImageSourceContext contains:

- view: an optr to the document's GenView, or NullOptr when unavailable.
- mimeSupported: a proc_HTMLImageMimeSupported callback, or a null pointer.

The parser sends MSG_GEN_VIEW_GET_VISIBLE_RECT to view at parse startup. It
uses right minus left as the viewport width, capped at 65535 pixels. An absent
view or a nonpositive width means unknown width. The snapshot is used throughout
the parse; there is no resize reselection.

The callback receives a null-terminated ASCII TYPE attribute and returns TRUE
when an image importer supports that MIME type. It uses the Pascal calling
convention and must be callable through ProcCallFixedOrMovable_pascal. It must
not reenter the parser. As with the existing entry points, callers must
serialize parsing. The parser does not retain the context after returning.

HTMLextra, the existing entry signatures, image records and transfer headers
remain unchanged. Legacy callers can continue using ParseAnyFile or
ParseHTMLFile. Without a MIME callback, explicitly typed SOURCE elements are
skipped; untyped sources can still match.

BbxBrow's ParseFrameHTML obtains the frame's text object and its view through
MSG_URL_FRAME_GET_TEXT_OBJ and MSG_HTML_TEXT_GET_VIEW_OBJ. Its
FrameImageMimeSupported callback checks the existing assocTypeDriver registry.
Availability follows registered drivers, including WebP and SVG when installed;
it does not guarantee that an individual image will decode successfully.

## Selection rules

For width descriptors in SRCSET, choose the smallest width at least as large
as the viewport, or the largest width if every candidate is smaller. Equal
widths retain the first candidate. Unknown viewport width retains the smallest
width choice. Existing density selection and implicit SRC at 1x remain in use.
A single bare SRCSET URL is accepted.

Inside PICTURE, the first SOURCE with a usable SRCSET, matching MEDIA and
supported TYPE supplies the following IMG URL. An absent or empty MEDIA
matches. Otherwise, MEDIA must contain one min-width or max-width expression
with a nonnegative integer pixel value, such as (max-width: 767px). ASCII
whitespace and case differences are accepted. Boundaries are inclusive.
Unknown width, invalid syntax and compound expressions do not match.
An absent or empty TYPE needs no capability check.

IMG resolution uses the pending picture source, then IMG SRCSET, then IMG SRC.
The IMG retains its attributes and events. Picture images carry HTML_IDF_PICTURE;
BbxBrow fits them to the visible width during import and on viewport shrink,
including page margin and image spacing, while preserving their aspect ratio.
Small images are not enlarged, and tall images remain vertically scrollable.
This uses the existing inline-SVG fitting messages without changing image records.
SOURCE creates no image, paragraph,
table or cell. Its selected URL is retained as a name-pool token before its
temporary attributes are freed. The first IMG consumes that token even if
image creation is skipped. Closing PICTURE, invalid nesting, unrelated markup,
non-whitespace text and parse cleanup discard pending selection. Comments and
whitespace preserve it. Synthetic tables used for IMG alignment do not affect
this cleanup.

This deliberately supports lightweight comma splitting, one width media
expression and initial URL selection only. It does not support sizes, general
media queries, DPR-aware selection, source switching after loading or resize
reselection. Cached page objects keep their selected URLs; force a fresh parse
when checking selection at another viewport width.

## Checks

Run the host-side check from the source-tree root:

```
python3 Library/Breadbox/Html4Par/htmtest/check_image_sources.py
```

The check compiles the actual selection functions, picture handlers,
ParseImage, Open_IMG and the MIME callback with host stubs for GEOS services. It exercises
srcset.htm and picture.htm at unknown, 400, 640 and 800 pixel widths with and
without WebP support. It also checks Tagesschau's eight-source ordering at
0, 400, 640, 800 and 1024 pixels and picture width fitting, spacing, extreme
margins and unchanged inline-SVG height fitting. picture.htm contains the supplied Tagesschau-shaped
markup, not a captured live page. Its JPEG/WebP fixtures use plain local filenames because BbxBrow
keeps query strings in local file paths. The numeric filenames identify the
selection cases; the small fixture images have identical dimensions.

## Swat verification

Use EC builds. In ~/swat.rc, after the application and library are available,
configure source breakpoints in this order:

```
run bbxbrow
spawn html4par
stop at /home/konstantinmeyer/pcgeos/Library/Breadbox/Html4Par/htmlpars/opentags.goc 762
stop at /home/konstantinmeyer/pcgeos/Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc 1406
```

The first line stops before Open_SOURCE retains the winning URL. If source
lines have moved, find the assignment to imageSourceState.pictureSource in
Open_SOURCE and use that line number. Once stopped, enter:

```
print imageSourceState.viewportWidth
print selectedLen
pstring -n -l [value fetch selectedLen] *selectedP
continue
```

The second breakpoint stops after URL completion and before BbxBrow tokenizes
the absolute image URL. Enter:

```
pstring *nP
continue
```

Force a fresh page parse at each width. For the Tagesschau-shaped sources,
400 pixels selects img640.webp, 640 pixels selects img768.webp, and 800
pixels uses img1280.jpg. With no registered WebP importer, the corresponding
JPEG source must win. Copy picture.htm and its image fixtures together when
checking local loading. A real captured page is required to verify website
source selection and fetching.
