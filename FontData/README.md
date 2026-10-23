# Font sources and assets

The authoritative ASM/DEF sources are grouped into Berkeley, Bison, Esquire,
LED, Universi and DejaVuSC subdirectories (six SBCS families, 31 strikes).
The compiled FNTs are committed in matching Installed/FontData family
subdirectories, such as Installed/FontData/Berkeley/Berkeley.fnt. Regenerate
and commit those outputs with source changes.
Editable TrueType projects live in FontData/Ttf/CooperBlack and
FontData/Ttf/StandardSymbolPS, alongside source documentation. FontData/Ttf
also retains the authoritative license notices and font_overview.md.

## Prebuilt fonts and cleanup

The 43 ready-to-use TTFs are committed in Installed/FontData/Ttf, with their
existing filenames and flat layout. The four legacy Nimbus outline fonts are
committed in Installed/FontData/Mono, Roman, Sans and SymbolPS, each containing
its correspondingly named FNT. These binaries are prebuilt assets; their
contents, font IDs and runtime behavior are unchanged.

All 47 prebuilt binaries must survive clean. This includes cooper.ttf and
symbolps.ttf: editable SFD projects exist, but reliable export recipes have
not been established. These directories have no compilation Makefiles and
are outside the six-family bitmap build/clean list. No FontForge or export
step is required by normal builds.

Per-family and aggregate pmake clean remove only generated bitmap outputs
and their intermediates. The standalone Linux/Windows clean scripts also
exclude FNT, TTF and SFD files. Preserve prebuilt assets and source projects
when adding future cleanup rules.

Packaging selects the same 34 TTFs; the remaining nine TTFs and four Nimbus
fonts stay unselected. TTF filetree paths resolve through Installed first;
license notices still resolve from FontData/Ttf in the source tree.

## Build and check

With ROOT_DIR and the usual SDK tool environment set:

    cd "$ROOT_DIR/Installed/FontData"
    pmake all
    pmake Berkeley.fnt
    pmake check

To build one font directly:

    cd "$ROOT_DIR/Installed/FontData/Berkeley"
    pmake

The same targets work on Windows. The parent Makefile builds all six families
and retains individual targets such as Berkeley.fnt. Each family Makefile
builds only its own font. pmake clean removes outputs and known intermediates
for the current bitmap family, or all six bitmap families when run from
Installed/FontData; rebuild before committing. Running pmake install from
Installed/Tools also builds all fonts after every host tool has installed
successfully.

The handcrafted family Makefiles include shared rules from font.mk and are
independent of mkmf and geode.mk. They accept ASM, ASMFLAGS, LINK and LINKFLAGS
overrides. Normal builds use only pmake, ESP, Glue (-Of) and native shell
operations. Objects, symbol files, temporary files and final fonts stay in
their Installed/FontData family directory. Each successful tool invocation
publishes its temporary output by rename. A failed invocation preserves the
previous complete object or font and returns failure through the parent build.

Sources and SDK headers are prerequisites of both objects and fonts, avoiding
missed links when this pmake's whole-second timestamps coincide. The explicit
SDK dependency list was checked using ESP -M for all six families.

The standalone check uses core Perl modules:

    perl FontData/tests/bitmap-fonts.pl [font-directory [reference-directory]]

The font directory contains the six generated bitmap family subdirectories;
the optional reference directory contains matching flat reference FNTs.
With a reference directory, it requires exact baseline equality instead of
final hashes and Berkeley Euro checks. Without one it verifies the committed
hashes, all 31 strikes, the original DejaVuSC 10 pt strike and the intended
Berkeley changes. Intentional future
font edits require reviewed updates to the regression hashes and compiled FNTs.

## Inventory and preserved quirks

Directory and physical strike order:

- Berkeley, 0x0202: regular 9, 10, 12, 14, 18.
- Bison, 0x0a00: regular 9, 12, 14, then 13 (only character 42).
- Esquire, 0x022b: regular 10, 12, 14, 18, 9; bold 12, 10, 14, 18, 9.
- LED, 0x0600: regular 18, character range 32..94, default 48.
- Universi, 0x0201: regular 10, 12, 14, 18, 24, 9; internal name University.
- DejaVuSC, 0x022c: regular 9, 10, 12, 14, 18; the original 10 pt strike is unchanged.

Esquire's header-size field includes the eight-byte BSWF prefix. Its 36
CTF_NO_DATA entries per strike retain nonzero offsets to empty CharData
records. Its zero-count kerning pointers retain their original positions
inside the character table. These historical values are deliberately kept.
LED's binary repertoire is wider than the old makefonts comments suggest.
No unused bytes, no-data records, fractional advances or usage fields were
normalized. The source contains checks for the SBCS structure sizes.

## Provenance and intentional changes

The implementation branch is bitmap-font-sources, based directly on master
caa9b436a7e870ca405c68c0a1ac1091f929f2a1 (fetched 2026-10-23).
Experimental references were read from fntpatch revision
d21ff9e6924ef7aa6b0fc1cf853aa5ec898a1fa3 without merging it.

The recovered FontData.zip BasePack Berkeley, Bison, LED and University
binaries exactly match master. The recovered Berkeley DEFs reproduce all
five master strikes exactly. Correcting the archived ASM name, family byte
and ordering reproduced the entire original Berkeley font exactly.

The newer Tools/mkuc Berkeley sources supply the final maintained sources
and all five Euro glyphs at 0xdb (C_EURO_CHAR/C_CURRENCY), including their
advances, bearings and bitmap dimensions. Master's FB_maxBSB/FB_maxRSB values
are restored instead of mkuc's zeros. Master's 14-point inverted question
mark is retained: it is the 180-degree rotation of the normal question mark;
mkuc changes only part of its curve. Every other glyph and font-wide metric
matches master. Euro data changes also change necessary sizes/offsets.

The other five families were reconstructed from their existing binaries;
none of their original glyphs were rerasterized. Esquire and DejaVuSC already contain Euros.
Temporary converters and the original experimental tools are not build
inputs and are not part of this branch. Additional archive families, DBCS
variants and outline conversion are outside this change.

DejaVuSC/DejaVuSC.txt retains the reference font's DejaVu/Bitstream Vera/Arev notices.
The font is not Apache-2.0 licensed. Packaging includes this DOS 8.3 notice
beside DejaVuSC.fnt. FID_DEJAVUSC is registered in both SDK font-ID headers;
no default UI font or font-menu configuration was changed.

Reference SHA-256 values:

- FontData/Berkeley.fnt: 5e06a6774f2a9fb7400e8f22a857b8a4a411ce0b638d82ef24deda15360fe2ac
- FontData/Bison.fnt: 90d08aa4fe62bf4fb413fcff0e6b467561b2410818ab321838c016b1f3ea3f25
- FontData/Esquire.fnt: bd00580f4b089aa3646f667f3f5294e47b70b47d29b431157e19e8760cc75b5f
- FontData/LED.fnt: 7af1561fbd88bc8c98935c2b5348853ac586809355fd3daf49e0626e96bbf0ca
- FontData/Universi.fnt: 862bf7ef3946863e1743ea147edaa666d5515cac7b2e663308d74a755913408c
- Tools/fntpatch/DejaVuSC.fnt: 799ec5dacdea01187b6da41198baaf2bf02c0420aaaffe8445e40be88717394e
- FontData.zip: 6db83b07a760d2af3c03bb4a8242d663533065f34d46cf03c86c4baf8070e17b
- Tools/mkuc/berkeley.asm: 56164d1e71f8bab4fd33749301c5e40fd02c28e356dfa3563d7cea2b642f78bb
- Tools/mkuc/berkeley_09.def: 4a13dea177b1b34ef0c093c07514eb9552a02b88ab96013e38c7476f5408e0d8
- Tools/mkuc/berkeley_10.def: 6d99b261c1602f604f93c40195709c696bd4ba715bed59a8254e8945135d1c06
- Tools/mkuc/berkeley_12.def: c75975dab1e84c796fce48c8d32ca5d9a310743f0d64bdcac3fec030806d63b1
- Tools/mkuc/berkeley_14.def: da419145b6425f221de5647227e6f20d6e376be8cc7200466347051c07aad116
- Tools/mkuc/berkeley_18.def: 06b45341c16c62e0b3ffaf2e94119cbe90c5fc764e944ba9992caff868218848

## Initial reconstruction validation (2026-10-23)

All six reconstructed baselines assembled byte-identically before applying
the intentional Berkeley changes. Final Bison, Esquire, LED, Universi and
DejaVuSC remain byte-identical to those references. Final Berkeley is 26427
bytes (original 26436); only the five Euro definitions and consequent layout
values differ. Its final SHA-256 is
85591ad95ca0bc48232a61a1731e3d8d81fd7548912efdf0693975041df26b10.
The other five final hashes are their reference hashes above.

Passed on Linux with the existing Open Watcom SDK environment:

- ESP/Glue reconstruction of all six baselines and all 27 strikes.
- Structural/default/missing-data checks, exact final hashes, Berkeley
  non-Euro glyph/metric comparisons, and four malformed-input rejection cases.
- Exact comparison with mkuc's five Euro definitions, plus native-size and
  enlarged visual inspection of the original, mkuc and final glyphs.
- Independent builds of each font, clean aggregate build and unchanged no-op.
- A DEF edit rebuilding only its family; a shared header edit rebuilding all.
- Missing FNT recovery without reassembling its existing object.
- Assembler/linker partial-output failures preserving the previous complete
  objects/FNTs, including nonzero propagation through the tools-install target.
- Linux parallel builds with pmake -C -J 4 -L 4.
- Full Installed/Tools pmake install from an empty host-artifact build tree,
  followed by a second successful install using the final font Makefile.
- Actual FindInstalledFile/SendFile resolution and byte-identical packaging
  of six fonts and the license into a temporary destination.

The product filetree uses matching FontData/family/font.fnt paths; Installed
precedes the source root in the existing resolver. The old source-root bitmap
FNTs were removed so they cannot conceal missing build outputs. The separate
prebuilt outline/TTF relocation preserves their contents exactly. Existing
edited files retain their line endings; imported mkuc files retain mixed
historical LF/CRLF endings.

After introducing the mirrored Installed family directories and individual
Makefiles, independent clean builds, aggregate and parallel checks, unchanged
rebuilds, family/shared-rule invalidation, missing-output recovery and failure
propagation were rechecked. The tools font-install target and actual packaging
helpers also passed with the nested paths. All six FNTs remain byte-identical.

The prebuilt relocation was checked separately:

- All 43 TTFs, four Nimbus FNTs and four relocated source-project files retain
  their original SHA-256 hashes. No TTF/FNT binaries remain under FontData.
- Actual packaging helpers resolve all 47 prebuilt binaries from Installed.
  The same 34 TTFs and four notices package byte-identically; nine TTFs and
  four Nimbus fonts remain unselected.
- All prebuilt assets, both SFD/info projects, license notices and the overview
  survive cleaning from each bitmap family and from the aggregate directory.
- Aggregate/parallel rebuilds pass the 27-strike regression check. All six
  generated bitmap FNTs also retain their previous hashes.
- The standalone Linux clean dry-run and Windows cleanup-pattern inspection
  exclude every relocated font and source-project file. No cleanup scripts
  or build targets were changed for the prebuilt assets.

Native Windows execution and GEOS runtime loading were not tested. The Linux
tools install cross-built the existing Windows host tools, which does not
establish native Windows test coverage. No PC/GEOS instance was launched,
and no full product image was built for this font-only validation.

## Additional DejaVuSC sizes

DejaVuSC now matches Berkeley and Esquire's regular sizes: 9, 10, 12, 14
and 18 pt. The original ISUI2000 10 pt strike is byte-identical, including
its metrics, advances and glyphs. The other four strikes were generated
from DejaVu Sans Condensed 2.37 using the original generator at revision
3943247357cdfdf8aadf0da968f486e9656974c6, Tools/fntpatch/make_DejaVuSC.py.
The generator lives on the fntpatch branch, as documented by
ISUI2000:FontData/README-DejaVuSC.md; no tool branches were merged.

The source TTF comes from the upstream dejavu-fonts-ttf-2.37 release:
https://github.com/dejavu-fonts/dejavu-fonts/releases/tag/version_2_37
Pillow 12.3.0 with FreeType 2.14.3 reproduces the original rasterizer.
From a checkout containing that generator, regenerate the reference with:

    python3 Tools/fntpatch/make_DejaVuSC.py /path/to/DejaVuSansCondensed.ttf \
        /tmp/DejaVuSC.fnt --sizes 9,10,12,14,18 --dpi 80
    python3 Tools/fntpatch/check_DejaVuSC.py /tmp/DejaVuSC.fnt

The editable sources remain dejavusc.asm and one DEF per size. Normal
builds require only ESP/Glue. The resulting 26609-byte FNT must match the
reference generated above; SHA-256:
c4d2118f39492cddf76616513fbe3d4fec5788e8e2961bd52cec93fb3f2d0f27.
The Perl check covers all 31 strikes and explicitly protects the original
DejaVuSC 10 pt strike in addition to checking the new complete font hash.
