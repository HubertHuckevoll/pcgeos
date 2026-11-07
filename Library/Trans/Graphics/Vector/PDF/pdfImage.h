/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfImage.h

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    PdfImageSpec - Canonical pixel format and geometry
    PdfImage     - Active inline image state

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Declare the format-neutral PDF image-row interface.
    Scanline data and mask storage remain caller-owned.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Canonical row interface. No GEOS headers, compression or palette layout here. */
#ifndef PDF_IMAGE_H
#define PDF_IMAGE_H
#include "pdfWriter.h"
#define PDF_IMAGE_STENCIL1 1 /* MSB first: 1 paints current color; 0 leaves paper */
#define PDF_IMAGE_RGB24 2    /* tightly packed R,G,B bytes, top row first */
#define PDF_IMAGE_INDEX4 3   /* high nibble first, unused low nibble ignored */
#define PDF_IMAGE_INDEX8 4
typedef struct {
    PdfWord width, height, format;
    PdfWord paletteEntries;
    const unsigned char *palette; /* borrowed RGB triples; masked images retain until End */
    PdfWord masked; /* canonical row starts with ceil(width/8) coverage bytes */
} PdfImageSpec;
typedef struct {
    PdfImageSpec spec;
    PdfWord rowBytes, rows, active, rowOffset;
    PdfWord maskBytes, tileLeft;
    unsigned char *maskP;
} PdfImage;
PdfWord PdfImageRowBytes(const PdfImageSpec *spec, PdfWord *bytes);
void PdfImageBegin(PdfDocument *p, PdfImage *image, const PdfImageSpec *spec,
                   int x, int y, PdfFixed width, PdfFixed height);
/* maskP is caller-owned ceil(width/8) storage, valid through End. */
void PdfImageBeginMasked(PdfDocument *p, PdfImage *image, const PdfImageSpec *spec,
                         int x, int y, PdfFixed width, PdfFixed height, unsigned char *maskP);
void PdfImageRow(PdfDocument *p, PdfImage *image, const unsigned char *row,
                 PdfWord bytes);
void PdfImageRowPart(PdfDocument *p, PdfImage *image, const unsigned char *data,
                     PdfWord bytes);
void PdfImageEnd(PdfDocument *p, PdfImage *image);
#endif
