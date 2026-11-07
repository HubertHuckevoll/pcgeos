/* Include/graphics.def: 6-byte Bitmap / 20-byte CBitmap, little endian. */
#include "pdfBitmap.h"
#ifndef PDF_HOST_TEST
#pragma Code ("PdfCode")
#endif

static PdfWord wordAt(const unsigned char *b)
{
    return (PdfWord)(b[0] | (PdfWord)b[1] << 8);
}

/***********************************************************************
 *
 * FUNCTION:    PdfBitmapParse
 *
 * DESCRIPTION: Validate the serialized GEOS bitmap header.
 *
 * PARAMETERS:  b/size = bitmap bytes; s = output descriptor.
 *
 * STRATEGY:    Validate dimensions, palette and compression fields.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Reject invalid or unsupported layouts.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

PdfWord PdfBitmapParse(const unsigned char *b, PdfWord size, PdfBitmapSlice *s)
{
    PdfWord error, type, paletteOffset, entries;
    PdfDWord payload;

    if (size < 6) return PDF_STATE_ERROR;
    s->image.width = wordAt(b);
    s->image.height = wordAt(b+2);
    type = b[5];
    /* Palette data stays separate from rows. Huge handles and reserved bits
     * are not serialized bitmap samples. */
    if (b[4] > 2 || (type & 0xa0)) return PDF_UNSUPPORTED;
    s->compact = b[4];
    s->image.masked = (type & 0x10) != 0;
    s->image.palette = (void*)0;
    s->image.paletteEntries = 0;
    if ((type & 7) == 0) s->image.format = PDF_IMAGE_STENCIL1;
    else if ((type & 7) == 1) {
        s->image.format = PDF_IMAGE_INDEX4;
        s->image.paletteEntries = 16;
    } else if ((type & 7) == 2) {
        s->image.format = PDF_IMAGE_INDEX8;
        s->image.paletteEntries = 256;
    } else if ((type & 7) == 3) s->image.format = PDF_IMAGE_RGB24;
    else return PDF_UNSUPPORTED;
    error = PdfImageRowBytes(&s->image, &s->rowBytes);
    if (error) return error;
    s->complex = type & 8;
    s->dataOffset = 6;
    s->firstRow = 0;
    s->rows = s->image.height;
    s->xDpi = s->yDpi = 72;
    if (s->complex) {
        if (size < 20) return PDF_STATE_ERROR;
        s->firstRow = wordAt(b+6);
        s->rows = wordAt(b+8);
        s->dataOffset = wordAt(b+12);
        s->xDpi = wordAt(b+16);
        s->yDpi = wordAt(b+18);
        if (s->dataOffset < 20) return PDF_STATE_ERROR;
    }

    if (!s->xDpi || !s->yDpi || s->dataOffset > size ||
        s->firstRow > s->image.height || s->rows > s->image.height - s->firstRow)
        return PDF_STATE_ERROR;
    if (type & 0x40) {
        if (!s->complex || !s->image.paletteEntries) return PDF_UNSUPPORTED;
        paletteOffset = wordAt(b+14);
        if (paletteOffset < 20 || paletteOffset > s->dataOffset ||
            s->dataOffset - paletteOffset < 2) return PDF_STATE_ERROR;
        entries = wordAt(b+paletteOffset);
        if (!entries || entries > s->image.paletteEntries ||
            (PdfDWord)entries * 3 > (PdfWord)(s->dataOffset - paletteOffset - 2))
            return PDF_STATE_ERROR;
        s->image.paletteEntries = entries;
        s->image.palette = b + paletteOffset + 2;
    }

    payload = (PdfDWord)s->rowBytes * s->rows;
    if ((!s->compact || !s->rows) && payload != (PdfDWord)(size - s->dataOffset))
        return PDF_STATE_ERROR;
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

/* The reader retains a borrowed view; the caller owns the slice buffer. */
PdfWord PdfBitmapReaderOpen(PdfBitmapReader *r, const unsigned char *data, PdfWord size)
{
    PdfWord error = PdfBitmapParse(data, size, &r->slice);

    if (error) return error;
    r->data = data;
    r->offset = r->slice.dataOffset;
    r->row = 0;
    r->size = size;
    r->rowOffset = r->pending = r->kind = r->value = 0;
    r->distance = r->flags = r->flagBits = 0;
    return PDF_OK;
}

/* Raw rows can be returned without an intermediate copy. */
PdfWord PdfBitmapNextRow(PdfBitmapReader *r, const unsigned char **row, PdfWord *bytes)
{
    if (r->row >= r->slice.rows) return PDF_STATE_ERROR;
    if (r->slice.compact) return PDF_STATE_ERROR;
    *row = r->data + r->offset; *bytes = r->slice.rowBytes;
    r->offset += r->slice.rowBytes;
    ++r->row;
    return PDF_OK;
}

/* Packet kinds: input literals, a repeated byte, a backwards match, row end.
 * Every source read and output extent is checked before copying any bytes. */
/***********************************************************************
 *
 * FUNCTION:    packet
 *
 * DESCRIPTION: Decode a bounded bitmap packet.
 *
 * PARAMETERS:  readerP = row decoder.
 *
 * STRATEGY:    Decode one bounded compression packet.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Reject input/output overruns.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static PdfWord packet(PdfBitmapReader *readerP)
{
    PdfWord c, count, distance = 0;

    readerP->kind = 0;
    if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
    if (readerP->slice.compact == 1) {
        c = readerP->data[readerP->offset++];
        count = c < 128 ? c + 1 : 257 - c;
        if (c >= 128) {
            if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
            readerP->kind = 1;
            readerP->value = readerP->data[readerP->offset++];
        }
    } else  {
        if (!readerP->flagBits) {
            readerP->flags = readerP->data[readerP->offset++];
            readerP->flagBits = 8;
            if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
        }

        c = readerP->flags & 128;
        readerP->flags <<= 1;
        --readerP->flagBits;
        if (c) count = 1;
        else {
            c = readerP->data[readerP->offset++];
            if (c & 128) {
                readerP->kind = 2;
                count = 3;
                distance = c & 127;
            } else if (c & 64) {
                count = c & 31;
                if (c & 32) {
                    if (!count) {
                        readerP->kind = 3;
                        return PDF_OK;
                    }

                    readerP->kind = 1;
                    readerP->value = 0;
                } else if (!count)  {
                    if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
                    count = readerP->data[readerP->offset++];
                }
            } else  {
                if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
                distance = (c & 3) * 256 + readerP->data[readerP->offset++];
                count = c >> 2;
                if (!count) {
                    if (readerP->offset >= readerP->size) return PDF_STATE_ERROR;
                    count = readerP->data[readerP->offset++];
                }

                readerP->kind = 2;
            }
        }
    }

    if (count > readerP->slice.rowBytes - readerP->rowOffset ||
        (readerP->kind == 0 && count > readerP->size - readerP->offset) ||
        (readerP->kind == 2 && count && (!distance || distance > readerP->rowOffset)))
        return PDF_STATE_ERROR;
    readerP->pending = count;
    readerP->distance = distance;
    return PDF_OK;
}

/***********************************************************************
 *
 * FUNCTION:    PdfBitmapNextChunk
 *
 * DESCRIPTION: Read a decoded chunk of the current bitmap row.
 *
 * PARAMETERS:  readerP = decoder; chunkP/bytesP = outputs.
 *
 * STRATEGY:    Return the next decoded row chunk.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Use only the bounded workspace.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

PdfWord PdfBitmapNextChunk(PdfBitmapReader *readerP, unsigned char *workspaceP,
                           const unsigned char **chunkP, PdfWord *bytesP)
{
    PdfWord count = 0, error;
    unsigned char c, *outP;

    if (!workspaceP || !readerP->slice.compact || readerP->row >= readerP->slice.rows) return PDF_STATE_ERROR;
    outP = workspaceP + (readerP->slice.compact == 2 ? PDF_BITMAP_HISTORY : 0);
    while (count < PDF_BITMAP_CHUNK) {
        if (!readerP->pending) {
            error = packet(readerP);
            if (error || readerP->kind == 3) return PDF_STATE_ERROR;
            if (!readerP->pending) continue;
        }

        if (readerP->kind == 0) c = readerP->data[readerP->offset++];
        else if (readerP->kind == 1) c = (unsigned char)readerP->value;
        else c = workspaceP[(readerP->rowOffset - readerP->distance) & (PDF_BITMAP_HISTORY - 1)];
        if (readerP->slice.compact == 2) workspaceP[readerP->rowOffset & (PDF_BITMAP_HISTORY - 1)] = c;
        outP[count++] = c;
        ++readerP->rowOffset;
        --readerP->pending;
        if (readerP->rowOffset == readerP->slice.rowBytes) {
            if (readerP->slice.compact == 2) {
                do {
                    error = packet(readerP);
                    if (error) return error;
                } while (readerP->kind != 3);
            }

            ++readerP->row;
            readerP->rowOffset = readerP->flagBits = 0;
            if (readerP->row == readerP->slice.rows && readerP->offset != readerP->size) return PDF_STATE_ERROR;
            break;
        }
    }

    *chunkP = outP; *bytesP = count;
    return PDF_OK;
}
