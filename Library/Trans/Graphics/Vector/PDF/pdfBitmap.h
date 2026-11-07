/* GEOS bitmap source adapter. It validates storage independently of PDF syntax.
 * Decompression belongs here; source flags must not reach the PDF serializer. */
#ifndef PDF_BITMAP_H
#define PDF_BITMAP_H
#include "pdfImage.h"
#define PDF_BITMAP_CHUNK 128
#define PDF_BITMAP_HISTORY 1024
#define PDF_BITMAP_WORKSPACE (PDF_BITMAP_HISTORY + PDF_BITMAP_CHUNK)
typedef struct {
    PdfImageSpec image;
    PdfWord firstRow, rows, rowBytes, dataOffset, xDpi, yDpi, complex, compact;
} PdfBitmapSlice;
/* NextRow borrows uncompressed canonical samples. NextChunk decodes compressed
 * samples with caller-owned workspace and no complete scanline allocation. */
typedef struct {
    PdfBitmapSlice slice;
    const unsigned char *data;
    PdfWord offset, row, size, rowOffset, pending, kind, value, distance, flags, flagBits;
} PdfBitmapReader;
PdfWord PdfBitmapParse(const unsigned char *data, PdfWord size, PdfBitmapSlice *slice);
PdfWord PdfBitmapExtent(PdfWord pixels, PdfWord dpi, PdfFixed *points);
PdfWord PdfBitmapReaderOpen(PdfBitmapReader *reader, const unsigned char *data, PdfWord size);
PdfWord PdfBitmapNextRow(PdfBitmapReader *reader, const unsigned char **row, PdfWord *bytes);
/* Compressed input only. PackBits needs PDF_BITMAP_CHUNK workspace bytes, LZG
 * needs PDF_BITMAP_WORKSPACE. The borrowed chunk never crosses a scanline. */
PdfWord PdfBitmapNextChunk(PdfBitmapReader *reader, unsigned char *workspace,
                           const unsigned char **chunk, PdfWord *bytes);
#endif
