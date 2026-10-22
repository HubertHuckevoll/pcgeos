# DejaVuSC for PC/GEOS Ensemble

DejaVuSC.fnt is the bitmap UI face selected by ISUI2000. Its internal name
is DejaVuSC, its font ID is 0x022c (FID_DEJAVUSC), and its only strike is
10 pt. The 11-pixel raster has 8-pixel capitals, 6-pixel lowercase letters
and a 14-pixel font box. Its glyphs, advances and metrics are preserved.

The product installs DejaVuSC.fnt and DejaVuSC.txt in USERDATA/FONT.
DejaVuSC.txt contains the DejaVu / Bitstream Vera / Arev redistribution
notices and must accompany the font. The font is not Apache-2.0 licensed.

## Provenance

The generator, verifier and reference font live on the fntpatch branch.

- Generator commit: 3943247357cdfdf8aadf0da968f486e9656974c6
- Source: DejaVu Sans Condensed 2.37, regular TTF
- Rasterizer: Pillow 12.3.0 with FreeType 2.14.3
- Parameters: 10 pt at 80 dpi, hinted monochrome
- SHA-256: 799ec5dacdea01187b6da41198baaf2bf02c0420aaaffe8445e40be88717394e

From a worktree at that generator commit, reproduce the artifact with:

    python3 Tools/fntpatch/make_DejaVuSC.py \
        /path/to/DejaVuSansCondensed.ttf /tmp/DejaVuSC.fnt \
        --sizes 10 --dpi 80
    python3 Tools/fntpatch/check_DejaVuSC.py /tmp/DejaVuSC.fnt
    cmp Tools/fntpatch/DejaVuSC.fnt /tmp/DejaVuSC.fnt

The product artifact must be byte-identical to that reference. Product
builds use the committed artifact and do not require the generator or Pillow.

## Manual rollout

The repository migration does not update an existing runtime installation.
With GEOS stopped:

- Install the matching rebuilt ConfigUI geode through the normal product or
  Swat deployment procedure.
- Copy DejaVuSC.fnt and DejaVuSC.txt into the runtime's USERDATA/FONT directory.
- Set [ui] fontid and editableTextFontID to DejaVuSC.
- Set [system] editableTextFontID to DejaVuSC.
- Use [ui] fontsize = 10 and editableTextFontsize = 10.

Restart GEOS after those updates. INI contents are cached while GEOS runs;
host edits made before shutdown can be overwritten by a subsequent save.
Select DejaVuSC in Character Map to inspect the installed font.
