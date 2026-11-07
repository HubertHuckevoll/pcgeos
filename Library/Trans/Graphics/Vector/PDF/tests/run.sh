#!/bin/sh
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
perl "$src/Tests/check-native-boundary.pl"
for test in writer gstring shape roundrect bitmap path; do
    "$cc" -std=c99 -Wall -Wextra -Werror -Wno-unknown-pragmas \
        -DPDF_HOST_TEST ${PDF_TEST_CFLAGS:-} -o "$work/${test}_test" \
        "$src/tests/${test}_test.c" "$src/pdfWriter.c" "$src/pdfShape.c" \
        "$src/pdfImage.c" "$src/pdfBitmap.c" -lm
    "$work/${test}_test" "$work/$test.pdf"
    perl "$src/tests/check_pdf.pl" "$work/$test.pdf" 2
    if command -v pdfinfo >/dev/null 2>&1; then
        pdfinfo "$work/$test.pdf" > "$work/$test.info"
        test "$(sed -n 's/^Pages: *//p' "$work/$test.info")" = 2
        test "$(sed -n 's/^PDF version: *//p' "$work/$test.info")" = 1.1
    fi
    if test "$test" = gstring && command -v gs >/dev/null 2>&1; then
        gs -q -dNOPAUSE -dBATCH -sDEVICE=txtwrite \
            -sOutputFile="$work/math.txt" "$work/gstring.pdf"
        perl -0777 -e 'local $/; $_=<>; /a\s*\xE2\x89\xA4\s*b/ or die "Symbol math glyph missing\n"' "$work/math.txt"
    fi
    if command -v pdftoppm >/dev/null 2>&1; then
        pdftoppm -scale-to 200 -png "$work/$test.pdf" "$work/$test" 2> "$work/render.err"
        test ! -s "$work/render.err"
        if test "$test" = path; then
            pdftoppm -r 72 "$work/path.pdf" "$work/path-pixels" 2> "$work/render.err"
            test ! -s "$work/render.err"
            perl "$src/tests/check_path_pixels.pl" "$work/path-pixels-1.ppm" "$work/path-pixels-2.ppm"
        fi
        if test "$test" = bitmap; then
            pdftoppm -r 72 -f 1 -singlefile "$work/bitmap.pdf" "$work/bitmap-pixels" 2> "$work/render.err"
            test ! -s "$work/render.err"
            perl "$src/tests/check_bitmap_pixels.pl" "$work/bitmap-pixels.ppm"
        fi
    fi
done
