#!/bin/sh
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
for test in writer gstring shape roundrect; do
    "$cc" -std=c99 -Wall -Wextra -Werror -Wno-unknown-pragmas \
        -DPDF_HOST_TEST ${PDF_TEST_CFLAGS:-} -o "$work/${test}_test" \
        "$src/tests/${test}_test.c" "$src/pdfWriter.c" "$src/pdfShape.c" -lm
    "$work/${test}_test" "$work/$test.pdf"
    perl "$src/tests/check_pdf.pl" "$work/$test.pdf" 2
    if command -v pdfinfo >/dev/null 2>&1; then
        pdfinfo "$work/$test.pdf" > "$work/$test.info"
        test "$(sed -n 's/^Pages: *//p' "$work/$test.info")" = 2
        test "$(sed -n 's/^PDF version: *//p' "$work/$test.info")" = 1.1
    fi
    if command -v pdftoppm >/dev/null 2>&1; then
        pdftoppm -scale-to 200 -png "$work/$test.pdf" "$work/$test" 2> "$work/render.err"
        test ! -s "$work/render.err"
    fi
done
