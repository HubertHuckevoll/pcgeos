# GEOS UI Sans (experimental bitmap UI font)

Goal: a compact Windows 2000/Tahoma-inspired bitmap font for PC/GEOS without
redistributing proprietary Microsoft Tahoma or Wine Tahoma (LGPL-2.1+).

## Source and licensing

This **is not Tahoma**, nor pixel/metric-compatible with Tahoma. It is generated
from **DejaVu Sans Condensed**, which shares Bitstream Vera ancestry with
Wine Tahoma. DejaVu's Bitstream Vera / Arev notices are included in
[LICENSE-DejaVu.txt](LICENSE-DejaVu.txt). The DejaVu font itself remains
under those terms: **do not label the generated glyphs Apache-2.0**.
It is permitted to redistribute the resulting font alongside
Apache-2.0 software provided the original copyright/license notices
are retained. Keep the generated font name distinct from Tahoma and
the protected source names. The converter source can be used under
the repository's Apache-2.0 terms.

DejaVu source and license: https://dejavu-fonts.github.io/

## Generate

Requires Python 3 and Pillow (only on the development host):

    python3 -m pip install Pillow
    python3 Tools/fntpatch/make_geos_ui_sans.py \
        /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf \
        GeosUiSans.fnt

A pre-generated 8-pt-only sample is committed as [GeosUiSans8.fnt](GeosUiSans8.fnt).

Default: 8, 9, 10, 12, 14 pt; 96 dpi; MacRoman 0x20..0xff;
one regular BSWF font with GEOS face name 'GEOS UI Sans'.
The normal 8 pt UI face is 11 pixels at 96 dpi.
For a corresponding bold source, generate a *different font file*
with a distinct GEOS face and ID:

    python3 Tools/fntpatch/make_geos_ui_sans.py \
        /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf \
        GeosUiSansBold.fnt --name "GEOS UI Sans Bold" --font-id 0x7a32

**Important:** the font IDs 0x7a31 / 0x7a32 are *provisional experimental*
values, not registered PC/GEOS IDs. Check existing IDs and agree on proper
IDs before making a UI default or distributing an integrated build.

## Validate

Use the accompanying verifier:

    python3 Tools/fntpatch/check_geos_ui_sans.py GeosUiSans.fnt

For a more detailed glyph-level check, from this branch build the existing
fntpatch host utility and run:

    fntpatch unpack GeosUiSans.fnt /tmp/geos-ui-sans-unpacked
    fntpatch pack /tmp/geos-ui-sans-unpacked /tmp/GeosUiSans-roundtrip.fnt
    cmp GeosUiSans.fnt /tmp/GeosUiSans-roundtrip.fnt

The fntpatch branch's tool only modifies bitmap pixels and fixed-size
offsets; **it cannot construct a new font or resize glyphs**. Our
generator uses its BSWF, FontBuf and CharData parsing as a format
reference, cross-checked against the Berkeley example in Tools/mkuc.

## Status / limits

- Generated and verified structurally (BSWF headers, strike offsets and
  sizes, character-table bounds, glyph bitmap lengths).
- Not yet installed/tested in a running GEOS build; especially
  UI text height, baseline, clipping, and line spacing require visual testing.
- MacRoman is used, matching the Berkeley character table; the Apple logo
  at 0xF0 is deliberately missing. GEOS-specific symbols may need remapping.
- 1-bit glyphs, threshold rasterized from TTF. No hand-tuned hinting or
  per-size pixel editing yet.
- No Tahoma metric-compatibility claim.
