/* Canonical row interface. No GEOS headers, compression or palette layout here. */
#ifndef PDF_IMAGE_H
#define PDF_IMAGE_H
#include "pdfWriter.h"
#define PDF_IMAGE_STENCIL1 1 /* MSB first: 1 paints current color; 0 leaves paper */
#define PDF_IMAGE_RGB24 2    /* tightly packed R,G,B bytes, top row first */
typedef struct {
    PdfWord width, height, format;
} PdfImageSpec;
typedef struct {
    PdfImageSpec spec;
    PdfWord rowBytes, rows, active;
} PdfImage;
PdfWord PdfImageRowBytes(const PdfImageSpec *spec, PdfWord *bytes);
void PdfImageBegin(PdfDocument *p, PdfImage *image, const PdfImageSpec *spec,
                   int x, int y, PdfFixed width, PdfFixed height);
void PdfImageRow(PdfDocument *p, PdfImage *image, const unsigned char *row,
                 PdfWord bytes);
void PdfImageEnd(PdfDocument *p, PdfImage *image);
#endif
