/* Include/graphics.def: 6-byte Bitmap / 20-byte CBitmap, little endian. */
#include "pdfBitmap.h"
#ifndef PDF_HOST_TEST
#pragma Code ("PdfCode")
#endif
static PdfWord wordAt(const unsigned char *b)
{ return (PdfWord)(b[0] | (PdfWord)b[1] << 8); }
PdfWord PdfBitmapParse(const unsigned char *b, PdfWord size, PdfBitmapSlice *s)
{
    PdfWord error, type;
    PdfDWord payload;
    if (size < 6) return PDF_STATE_ERROR;
    s->image.width = wordAt(b); s->image.height = wordAt(b+2);
    type = b[5];
    /* Allow simple/complex mono and RGB. Stored masks, palettes, huge handles,
     * reserved bits, compression and other formats need dedicated converters. */
    if (b[4] != 0 || (type & 0xf0)) return PDF_UNSUPPORTED;
    if ((type & 7) == 0) s->image.format = PDF_IMAGE_STENCIL1;
    else if ((type & 7) == 3) s->image.format = PDF_IMAGE_RGB24;
    else return PDF_UNSUPPORTED;
    error = PdfImageRowBytes(&s->image, &s->rowBytes);
    if (error) return error;
    s->complex = type & 8; s->dataOffset = 6;
    s->firstRow = 0; s->rows = s->image.height; s->xDpi = s->yDpi = 72;
    if (s->complex) {
        if (size < 20) return PDF_STATE_ERROR;
        s->firstRow = wordAt(b+6); s->rows = wordAt(b+8);
        s->dataOffset = wordAt(b+12); s->xDpi = wordAt(b+16); s->yDpi = wordAt(b+18);
        if (s->dataOffset < 20) return PDF_STATE_ERROR;
    }
    if (!s->xDpi || !s->yDpi || s->dataOffset > size ||
        s->firstRow > s->image.height || s->rows > s->image.height - s->firstRow)
        return PDF_STATE_ERROR;
    payload = (PdfDWord)s->rowBytes * s->rows;
    if (payload != (PdfDWord)(size - s->dataOffset)) return PDF_STATE_ERROR;
    return PDF_OK;
}
PdfWord PdfBitmapExtent(PdfWord pixels, PdfWord dpi, PdfFixed *points)
{
    PdfDWord numerator, whole, fraction;
    if (!pixels || !dpi) return PDF_STATE_ERROR;
    numerator = (PdfDWord)pixels * 72;
    whole = numerator / dpi;
    if (whole > 32767UL) return PDF_LIMIT_ERROR;
    fraction = ((numerator % dpi) << 16) / dpi;
    *points = (PdfFixed)((whole << 16) | fraction);
    return PDF_OK;
}
PdfWord PdfBitmapReaderOpen(PdfBitmapReader *r, const unsigned char *data, PdfWord size)
{
    PdfWord error = PdfBitmapParse(data, size, &r->slice);
    if (error) return error;
    r->data = data; r->offset = r->slice.dataOffset; r->row = 0;
    return PDF_OK;
}
PdfWord PdfBitmapNextRow(PdfBitmapReader *r, const unsigned char **row, PdfWord *bytes)
{
    if (r->row >= r->slice.rows) return PDF_STATE_ERROR;
    *row = r->data + r->offset; *bytes = r->slice.rowBytes;
    r->offset += r->slice.rowBytes; ++r->row;
    return PDF_OK;
}
