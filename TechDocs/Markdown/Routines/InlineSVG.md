# Inline SVG in Html4Par

Html4Par captures inline SVG as raw source bytes instead of parsing its
contents as HTML. HypertextTransferBlockHeader.HTBH_svgSourceData owns a
byte HugeArray in the page transfer VM chain. HTMLimageData stores the
source offset and length and marks inline records with HTML_IDF_INLINE_SVG.
Copying or freeing the transfer chain also copies or frees its SVG source.

BbxBrow imports this source through ImpGraph and SvgLib using temporary
files. At most two inline imports are outstanding per text object. Each
batch admits eight images, including cache hits and failures, then pauses
for 30 ticks if more images remain. Stop and navigation cancel admission;
queued imports retain their own pending references until completion.

Unresolved inline SVG starts with zero graphic dimensions, including when
attaching a cached page. Shape-less or unsupported inline content remains
invisible. The SVG engine's supported shapes, styles and limits also apply
to external SVG; this is not a general SVG scripting or DOM implementation.

## Image resolution messages

Html4Par protocol 3.5 adds two messages at the end of HTMLTextClass:

- MSG_HTML_TEXT_RESOLVE_INLINE_SVG takes the same image index, image record
  and invalidation range as MSG_HTML_TEXT_RESOLVE_IMAGE, followed by word
  viewport width and height. It fits inline SVG before calling the existing
  resolver. Zero viewport dimensions skip fitting.
- MSG_HTML_TEXT_CLAMP_INLINE_SVG_TO_VIEWPORT takes word viewport width and
  height. It shrinks resolved inline SVG to fit, preserving aspect ratio,
  and dirties layout once for the batch. It leaves ordinary images alone.

The original image-resolution signature and existing message numbers remain
unchanged. Rebuild clients of the extended transfer/image structures. BbxBrow
uses object-cache version 2.4 to reject pages saved with the earlier layout.

## Checks

Run check_svg_scan.py and check_svg_campaign.py in
Library/Breadbox/Html4Par/htmtest. The scanner check compiles the actual SVG
scanner; the campaign check verifies configured limits and exercises the
actual cached-placeholder reset with host storage stubs. Neither runs GEOS.
The adjacent svg.htm provides an external/inline integration fixture for
manual browser checks.
