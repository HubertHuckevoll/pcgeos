/* GEOS bitmap source adapter. It validates storage independently of PDF syntax.
 * Future palette/decompression converters belong here, producing canonical rows
 * for pdfImage.h; source flags must never leak into the PDF serializer. */
#ifndef PDF_BITMAP_H
#define PDF_BITMAP_H
#include "pdfImage.h"
typedef struct {
    PdfImageSpec image;
    PdfWord firstRow, rows, rowBytes, dataOffset, xDpi, yDpi, complex;
} PdfBitmapSlice;
/* Source iterator: today NextRow returns a zero-copy view. Later decoders can
 * keep compaction/palette state here and return a bounded converted scanline. */
typedef struct {
    PdfBitmapSlice slice;
    const unsigned char *data;
    PdfWord offset, row;
} PdfBitmapReader;
PdfWord PdfBitmapParse(const unsigned char *data, PdfWord size, PdfBitmapSlice *slice);
PdfWord PdfBitmapExtent(PdfWord pixels, PdfWord dpi, PdfFixed *points);
PdfWord PdfBitmapReaderOpen(PdfBitmapReader *reader, const unsigned char *data, PdfWord size);
PdfWord PdfBitmapNextRow(PdfBitmapReader *reader, const unsigned char **row, PdfWord *bytes);
#endif
