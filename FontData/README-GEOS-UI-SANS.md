# Experimental GEOS UI Sans for ISUI2000

This branch includes a Windows 2000/Tahoma-inspired, DejaVu Sans Condensed
bitmap-font **experiment** under a name other than Tahoma. It is not actual
Microsoft Tahoma or Wine Tahoma. The font glyphs use the Bitstream Vera / Arev
terms included in Tools/fntpatch/LICENSE-DejaVu.txt; the font itself is not
Apache-2.0 licensed, but is permitted alongside Apache-2.0 source subject
to those notices.

The pre-generated 8 pt sample is FontData/GeosUiSans8.fnt.
The complete regular and bold fonts (8/9/10/12/14 pt) are generated using
Tools/fntpatch/make_geos_ui_sans.py from a DejaVu Sans Condensed TTF:

    python3 Tools/fntpatch/make_geos_ui_sans.py \
      /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf \
      FontData/GeosUiSans.fnt

    python3 Tools/fntpatch/make_geos_ui_sans.py \
      /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf \
      FontData/GeosUiSansBold.fnt \
      --name "GEOS UI Sans Bold" --font-id 0x7a32

A development host needs Python 3 and Pillow. Verify generated output with:

    python3 Tools/fntpatch/check_geos_ui_sans.py FontData/GeosUiSans.fnt

The host-side BSWF unpack/repack tool from fntpatch is also carried over
in Tools/fntpatch, with its build files in Installed/Tools/fntpatch
and an entry in Installed/Tools/Makefile.

WARNING: 0x7a31 and 0x7a32 are provisional font IDs. Before making the
font the system UI default, allocate collision-free font IDs and visually
verify it in a running GEOS installation (glyph spacing/baseline/clipping).
This commit does not change the ISUI2000 default font selection.
