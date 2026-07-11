# Manual fixtures

Import sample.md and utf8.md through GeoWrite's Import dialog. Compare the
result with expected.txt; the UTF-8 fixture must retain supported characters
and preserve unmatched Markdown delimiters.

To test malformed UTF-8, create invalid-utf8.md from invalid-utf8.hex as raw
bytes. It contains c3 28, which must import as ?( without aborting.

Repeat sample.md after converting its line endings to CRLF. It must not gain
blank paragraphs. A line of 2044 ASCII characters must report an import error,
not truncate or split the line.

For export, create the attributed text described by export-source.txt, export
it as Markdown, and compare it byte-for-byte with the UTF-8, CRLF-terminated
export-expected.md. Import the result again and verify that the headings,
isolated inline styles, quote prefix, and list prefixes match the source
document. Other unsafe and ambiguous formatting must remain visible plain
text.
