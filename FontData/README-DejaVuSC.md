# Experimental DejaVuSC for ISUI2000

This branch includes a Windows 2000/Tahoma-inspired, DejaVu Sans Condensed
bitmap-font **experiment** under a name other than Tahoma. It is not actual
Microsoft Tahoma or Wine Tahoma. The font glyphs use the Bitstream Vera / Arev
terms included in Tools/fntpatch/LICENSE-DejaVu.txt; the font itself is not
Apache-2.0 licensed, but is permitted alongside Apache-2.0 source subject
to those notices.

The pre-generated 10 pt reference is Tools/fntpatch/DejaVuSC.fnt. Its 11-pixel
raster is calibrated at 80 dpi to match Esquire 10 pt's capital/lowercase
height. It retains the original 8 pt experiment's glyphs and advances,
with corrected GEOS metrics and size label.
The reference and a separate bold face can be generated using
Tools/fntpatch/make_DejaVuSC.py from a DejaVu Sans Condensed TTF:

    python3 Tools/fntpatch/make_DejaVuSC.py \
      /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf \
      Tools/fntpatch/DejaVuSC.fnt --sizes 10 --dpi 80

    python3 Tools/fntpatch/make_DejaVuSC.py \
      /usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf \
      Tools/fntpatch/DejaVuSB.fnt \
      --name "DejaVuSC Bold" --font-id 0x7a32

Omitting --sizes generates 8/9/10/12/14 pt strikes. A development host
needs Python 3 and Pillow. Verify generated output with:

    python3 Tools/fntpatch/check_DejaVuSC.py Tools/fntpatch/DejaVuSC.fnt

The host-side BSWF unpack/repack tool from fntpatch is also carried over
in Tools/fntpatch, with its build files in Installed/Tools/fntpatch
and an entry in Installed/Tools/Makefile.

The regular face uses numeric bitmap font ID 0x022c. The ISUI2000 product
branch registers FID_DEJAVUSC in its SDK headers and packages its generated
font and license notice in USERDATA/FONT. This branch's generator and tests
have no dependency on the product artifact or its headers. The bold
example's 0x7a32 remains provisional.

Use --sizes 10 --dpi 80 to reproduce the committed reference. Run
perl Tools/fntpatch/tests/DejaVuSC.pl, optionally followed by the source TTF
path, to verify the reference and its reproducibility. See
Tools/fntpatch/DejaVuSC.md for rasterizer versions, metrics and limitations.
