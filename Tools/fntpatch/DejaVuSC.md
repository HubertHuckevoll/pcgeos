# DejaVuSC (experimental bitmap UI font)

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

Requires Python 3 and Pillow 9.1 or newer (only on the development host):

    python3 -m pip install Pillow
    python3 Tools/fntpatch/make_DejaVuSC.py \
        /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf \
        DejaVuSC.fnt

A pre-generated 10-pt-only UI face is committed as [DejaVuSC.fnt](DejaVuSC.fnt).

Default: 8, 9, 10, 12, 14 pt; 80 dpi; GEOS characters 0x20..0xff;
one regular BSWF font with GEOS face name 'DejaVuSC'.
The installed 10 pt UI face uses an 11-pixel raster (10 * 80 / 72, rounded).
This matches Esquire 10 pt's 8-pixel capital and 6-pixel lowercase height.
80 dpi also matches the VGA16 driver's normal 800x600 mode; it is a bitmap
UI calibration, not a claim that every GEOS display uses that resolution.
The original 8 pt / 96 dpi experiment used the same raster. Its size label
has been normalized without scaling the glyphs or changing their advances.
The size label now lets ISUI use its normal header spacing.
Rendering uses FreeType's monochrome hinting through Pillow's 1-bit drawing
mode, with BASIC layout for whole-pixel advances. Thresholding an antialiased
image loses thin strokes at this size, including the euro's horizontal bars.
Characters are rasterized together on one baseline, separated by blank gaps,
then extracted into individual glyphs. Rendering them independently can shift
letters such as t and accented characters: Pillow's outline bounds and hinted
bitmap bounds do not always agree. Glyph shapes and advances are preserved.
The euro occupies 0xdb (C_EURO_CHAR / C_CURRENCY), matching Esquire and the
TrueType driver's character map. Four GEOS differences from modern MacRoman
(delta, black diamond, y acute and Y acute) are mapped explicitly.

To regenerate the reference face from the repository root:

    python3 Tools/fntpatch/make_DejaVuSC.py \
        /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf \
        Tools/fntpatch/DejaVuSC.fnt --sizes 10 --dpi 80

DejaVuSC.fnt fits DOS 8.3.

FontBuf metrics describe the raster: baseline 10, cap top 2, lowercase
height 6, underline 11 and strike-through 7. The 14-pixel font box is
retained, so descent is 4, including bottom padding. Its tallest/deepest
symbols remain inside the box. Character data and advances are unchanged.
The committed sample uses DejaVu 2.37, Pillow 12.3.0 and FreeType 2.14.3;
rasterizer versions can change the exact pixels.

For a corresponding bold source, generate a *different font file*
with a distinct GEOS face and ID:

    python3 Tools/fntpatch/make_DejaVuSC.py \
        /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf \
        DejaVuSB.fnt --name "DejaVuSC Bold" --font-id 0x7a32

The regular face uses bitmap font ID 0x022c. The ISUI2000 product branch
registers it as FID_DEJAVUSC in Include/fontID.def and CInclude/fontID.h.
This generator uses the numeric ID and does not depend on those definitions.
The bold example's 0x7a32 remains provisional; allocate a bitmap font ID
before distributing that separate face.

The ISUI2000 product branch distributes FontData/DejaVuSC.fnt and its
license notice as FontData/DejaVuSC.txt. Its product artifact is generated
from this branch's reference face. Generation and verification here need
only Tools/fntpatch/DejaVuSC.fnt, without a FontData copy.

## Inspect in Character Map

Install DejaVuSC.fnt and its license notice in USERDATA/FONT. FontControl's
[system] fontmenu and fonttool keys accept concatenated four-digit font IDs;
include 022c to expose DejaVuSC in the menu and toolbar. These explicit lists
replace the corresponding default lists, so include other desired IDs too.
Application-specific lists take precedence. More Fonts keeps its normal
outline enumeration.

Restart GEOS, open Character Map and select DejaVuSC. Edit an installed INI
only while GEOS is stopped: later saves of its live buffers can overwrite
host edits. This tooling branch does not change the runtime installation.

## Validate

Use the accompanying verifier:

    python3 Tools/fntpatch/check_DejaVuSC.py DejaVuSC.fnt

Run the bitmap regressions (integer advances, shared baselines, glyph
bounds/flags, missing glyph fallback, euro crossbars and accented y/Y) from
the repository root:

    perl Tools/fntpatch/tests/DejaVuSC.pl

Pass the regular DejaVuSansCondensed.ttf path as an optional argument to
also regenerate the 10 pt font and compare it with the reference byte for byte.

For a more detailed glyph-level check, from this branch build the existing
fntpatch host utility and run:

    fntpatch unpack DejaVuSC.fnt /tmp/DejaVuSC-unpacked
    fntpatch pack /tmp/DejaVuSC-unpacked /tmp/DejaVuSC.fnt
    cmp DejaVuSC.fnt /tmp/DejaVuSC.fnt

The fntpatch host utility only modifies bitmap pixels and fixed-size
offsets; **it cannot construct a new font or resize glyphs**. Our
generator uses its BSWF, FontBuf and CharData parsing as a format
reference, cross-checked against the Berkeley example in Tools/mkuc.

## Status / limits

- Generated and verified structurally (BSWF headers, strike offsets and
  sizes, character-table bounds, glyph bitmap lengths).
- Product integration lives on ISUI2000. Visual verification after the
  internal-name change is still required in a running GEOS build.
- GEOS's character map follows Driver/Font/TrueType/Adapter/ttcharmapper.c;
  the Apple logo at 0xF0 is deliberately missing and uses the normal "?"
  fallback. Its data offset is CHAR_NOT_EXIST (0), not CHAR_MISSING (3).
- Hinted 1-bit glyphs from TTF. No hand-tuned per-size pixel editing yet;
  a manually tuned bitmap face can still give better results at small sizes.
- No Tahoma metric-compatibility claim.
