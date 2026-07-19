# Manual fixtures

Import sample.md and utf8.md through GeoWrite's Import dialog. Compare the
result with expected.txt; the UTF-8 fixture must retain supported characters
and preserve unmatched Markdown delimiters.

Import torture.md for a visual boundary test. It covers supported syntax,
delimiter and prefix edge cases, and intentionally unsupported nested blocks,
tables, fences, HTML, and extensions. It is not a golden-output fixture. Its
last three probe lines are exactly 2042, 2043, and 2044 ASCII characters; the
first two should import and the last should report TE_IMPORT_ERROR.

The image section in torture.md uses checked-in PNG, JPEG, and GIF files
through relative paths. All three should render in the document. The
unsupported local file, missing file, URL, absolute path, and malformed image
syntax should remain visible as literal Markdown.

To verify content-based recognition, temporarily copy sample.png to
renamed.jpg beside sample.md and import a scratch file containing
`![renamed PNG](renamed.jpg)`. It must render. Create a plain-text file named
not-image.png beside the scratch file and reference it as an image; that line
must remain literal. These temporary files are not fixtures and should not be
committed.

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

For graphic export, import the PNG, JPEG, and GIF references in torture.md,
then export the document. Each occurrence must produce a sibling PNG and a
Markdown reference in document order, including repeated graphics and two
graphics on one line. Import the exported Markdown again and verify all PNGs
render. Resize or transform one graphic before export and verify its PNG uses
the displayed dimensions and appearance.

Export to a non-current directory with a long, punctuation-heavy Markdown
name. Verify every generated filename is uppercase ASCII DOS 8.3, every link
matches the filename case exactly, relative links resolve beside the Markdown
file, and exporting again replaces the same PNGs without changing the links.
Insert page-number and date fields and verify they remain
`[image]` without consuming an image number.

For failure cleanup, test an invalid graphic VM chain, a zero-sized graphic, a
read-only or full output location, and forced bitmap-allocation failure. Export
must return an error, remove the current incomplete PNG, and leave subsequent
exports able to create their sidecars normally.
