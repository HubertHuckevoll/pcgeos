#!/bin/sh
##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     PDF Native Build Checks
# FILE:       build-native.sh
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# ROUTINES:
#     main - Compile EC and NC variants using native GEOS tools
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Build the PDF library, printer driver and test application.
#     Keep generated build products outside the source tree.
#
##############################################################################

# Build both GEOS variants without changing revision files or the source tree.
# PATH must supply wcc, esp, glue, goc. GEOS_LDF_DIR supplies built SDK .ldf files.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../../../.." && pwd)
: "${WATCOM:?Set WATCOM to an Open Watcom installation}"
: "${GEOS_LDF_DIR:=$root/Installed/Include}"
out=${1:?usage: build-native.sh absolute-output-directory}
mkdir -p "$out/nc" "$out/ec"
case "$out" in /*) ;; *) echo 'Use an absolute output directory' >&2; exit 1;; esac
for variant in nc ec; do
    defs=
    glueflags=
    if test "$variant" = ec; then defs=-DDO_ERROR_CHECKING; glueflags=-E; fi
    for unit in pdfWriter pdfShape pdfImage pdfBitmap pdfGeos; do
        wcc -zq -D__GEOS__ -D__WATCOM__ $defs -w4 -fpc -zu -of -of+ -ol \
            -s -ecc -zp1 -ei -zdp -d2 -hc -ml -i="$root/CInclude" -i="$WATCOM/h" \
            -fo="$out/$variant/$unit.obj" "$root/Library/Trans/Graphics/Vector/PDF/$unit.c"
    done
    esp $defs -I"$root/Include" -o "$out/$variant/pdfStream.obj" \
        "$root/Library/Trans/Graphics/Vector/PDF/pdfStream.asm"
    esp $defs -n print -DPROTO=PRINT_PROTO_MAJOR.PRINT_PROTO_MINOR -I"$root/Include" -I"$root/Driver/Printer/PrintCom" \
        -I"$root/Driver/Printer/PDF" -o "$out/$variant/pdfManager.obj" \
        "$root/Driver/Printer/PDF/pdfManager.asm"
    goc -cw -D__GEOS__ $defs -I"$root/CInclude" -o "$out/$variant/pdfprint.c" \
        "$root/Appl/SDK_C/PDFPrint/pdfprint.goc"
    wcc -zq -D__GEOS__ -D__WATCOM__ $defs -w4 -fpc -zu -of -of+ -ol \
        -s -ecc -zp1 -ei -zdp -d2 -hc -ml -i="$root/CInclude" -i="$WATCOM/h" \
        -fo="$out/$variant/pdfprint.obj" "$out/$variant/pdfprint.c"
    (
        cd "$out/$variant"
        mkdir -p printer
        glue -Og "$root/Library/Trans/Graphics/Vector/PDF/pdf.gp" $glueflags \
            -o pdf.geo -l -L"$GEOS_LDF_DIR" -R 1.0.0.0 -P 1.0 \
            pdfWriter.obj pdfShape.obj pdfImage.obj pdfBitmap.obj pdfGeos.obj pdfStream.obj
        glue -Og "$root/Driver/Printer/PDF/pdf.gp" $glueflags \
            -o printer/pdf.geo -L. -L"$GEOS_LDF_DIR" -R 1.0.0.0 \
            -P PRINT_PROTO_MAJOR.PRINT_PROTO_MINOR pdfManager.obj
        glue -Og "$root/Appl/SDK_C/PDFPrint/pdfprint.gp" $glueflags \
            -o pdfprint.geo -L"$GEOS_LDF_DIR" -R 1.0.0.0 -P 1.0 pdfprint.obj
    )
done
