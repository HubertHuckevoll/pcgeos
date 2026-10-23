# Font sources and prebuilt assets: implementation and acceptance

## Fixed decisions

This supersedes the earlier planning draft. The implementation uses branch
bitmap-font-sources directly from freshly fetched origin/master, with no
fntpatch or ISUI2000 merge. The original checkout and local configuration
edits are preserved in their existing worktree.

Six family ASM files and 27 strike DEF files are grouped into one subdirectory
per family under FontData: Berkeley, Bison, Esquire, LED, Universi and DejaVuSC.
The six compiled FNTs are committed in matching Installed/FontData family
subdirectories. Five superseded source-root bitmap binaries are removed;
outline FNTs and TTFs retain their contents in prebuilt asset directories.

The handcrafted aggregate and family Makefiles, shared font.mk rules and
Tools Makefile changes are the explicit user-authorized exception to the
AGENTS.md generation rule. There is no mkmf dependency, dependencies.mk or
permanent converter. Normal builds use pmake, ESP, Glue and native shell
operations.

## Prebuilt font placement

Keep all 43 TTF binaries committed under Installed/FontData/Ttf, with existing
filenames and a flat binary layout. Keep Mono.fnt, Roman.fnt, Sans.fnt and
SymbolPS.fnt in corresponding family directories under Installed/FontData.
Treat these 47 files as prebuilt assets, including TTFs with editable projects.

Keep the CooperBlack and StandardSymbolPS SFD/info projects directly under
FontData/Ttf, with no additional source directory. License notices, provenance
and font_overview.md remain in FontData/Ttf. Preserve every relocated file's
bytes and the current 34 selected TTFs, nine unselected TTFs and four disabled
Nimbus entries. Update disabled Nimbus paths without enabling them.

Add no compilation Makefiles or export dependencies for prebuilt assets.
Keep them outside the generated bitmap build/clean lists; sources, notices,
documentation and all prebuilt binaries must survive cleaning. Source
reconstruction, archive imports and reproducible TTF exports are separate work.

## Sources and intentional changes

Preserve original IDs, names, strike ordering, metrics, glyph data, missing
records and unused fields. Prove exact reconstruction of all six references
before intentional changes. Pin master, experimental inputs and the archive
by revision/hash; the FontData README records those references and results.

Use the recovered Berkeley DEFs for the exact pre-change baseline. Use the
newer mkuc ASM/DEF sources for the final maintained Berkeley sources, keeping
all five existing Euro definitions, including their advances and geometry.
Restore master's font-wide maximum bounds and retain its correct 14-point
inverted question mark. Other than the Euros and consequent layout values,
Berkeley must match master.

Reconstruct Bison, Esquire, LED, Universi and DejaVuSC without rerasterizing.
Preserve Bison's single-character 13-point strike, University's internal name,
LED's actual shipped repertoire and Esquire's historical header/no-data quirks.
Preserve the original DejaVuSC 10-point raster, name, ID and licensing.

## Build and packaging contract

From Installed/FontData, support the default/all target, individual FNT
targets, clean and check. Each matching family directory has a Makefile
for independent builds and cleaning. Keep generated files in those family
directories and share common rules through font.mk.
Assemble/link temporary files and replace complete outputs only on success.
Track source, SDK and tool prerequisites; retain source/header dependencies
on link targets because this pmake uses whole-second timestamps.

The Tools install target builds fonts after all host tool installation
targets succeed. Real prerequisites establish ordering; checked command
chaining propagates failures. Perl is confined to the explicit check target.

Use matching FontData/family/font.fnt filetree paths, resolved through
Installed first. Package DejaVuSC and its DOS 8.3 license notice. Register FID_DEJAVUSC as
0x022c in both SDK headers without changing other IDs or UI defaults.

## Acceptance and exclusions

Keep one standalone core-Perl regression check with optional output and exact
reference directories. Validate all six containers and 27 strikes, names,
IDs/styles, character and bitmap bounds, defaults, no-data records, metrics,
kerning fields, final hashes, unchanged Berkeley glyphs and exact mkuc Euros.
Reject malformed in-memory inputs. Inspect Euros at native and enlarged sizes.

Verify independent and aggregate builds, clean rebuilds of committed outputs,
unchanged no-op builds, one-family DEF dependencies, shared-header invalidation,
missing-output recovery, partial-output failures and failure propagation,
Linux parallel execution and a full tools install. Verify actual packaging
resolution and copied bytes without starting GEOS.

Preserve existing line endings, including imported mixed endings. Review the
diff ignoring end-of-line whitespace. Exclude temporary converters/logs,
experimental tooling, additional font families, DBCS, outline conversion,
font-driver changes and unrelated UI/configuration work. Validate prebuilt
relocations with before/after hashes, unchanged packaging selection and copied
bytes, plus preservation through aggregate and per-family bitmap cleaning.

The FontData README contains the executed validation report and final hashes.
Native Windows execution and runtime font loading remain explicitly unverified;
PC/GEOS must not be launched for these tests.
