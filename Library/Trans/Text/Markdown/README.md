# PC/GEOS Markdown Translator

This is a Markdown import and export translator for SBCS PC/GEOS Ensemble.
It appears in GeoWrite as Markdown and accepts .md files.

The importer reads UTF-8 source text. An initial UTF-8 BOM is ignored. Unicode
characters are mapped through the installed HTML character mapper; malformed
UTF-8 and characters without an SBCS GEOS mapping become ?.

Supported Markdown is deliberately small:

- ATX headings from # through ######
- bold, italic, and inline code
- flat unordered and ordered lists
- block quotes
- horizontal rules
- links rendered as label (url)

Export is optimized for documents produced by this importer. It writes UTF-8
and conservatively recovers headings, isolated bold and italic runs, inline
code, and the importer's bullet and ordered-list prefixes. Formatting that
cannot be represented safely is written as plain text. Converted links,
and horizontal-rule text remain visible text rather than being guessed back
into lost structure. The importer's italic quoted-paragraph wrapper is
recognized and exported with `> ` again.

Heading levels 1 through 6 use the point-size selector's standard 24, 18, 14,
12, 10, and 9 point sizes. Existing documents imported with older translator
versions must be imported again to acquire these sizes.

Unmatched delimiters are imported literally. Nested blocks, tables, fenced
code blocks, and full CommonMark behavior are not supported. A logical input
line longer than 2043 decoded characters fails the import rather than being
truncated.

Build from Installed/Library/Trans/Text/Markdown:

    mkmf
    pmake depend
    pmake -L 4 full

The Ensemble product file tree installs markdown.geo in library/impex.

ATTENTION: DBCS PC/GEOS is not supported. The parser is byte-oriented; a
wide-character parser is required before enabling it for DBCS builds.
