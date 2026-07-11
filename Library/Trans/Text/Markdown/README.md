# PC/GEOS Markdown Translator

This is an import-only Markdown translator for SBCS PC/GEOS Ensemble.
It appears in GeoWrite as Markdown and accepts .md and .markdown files.

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
