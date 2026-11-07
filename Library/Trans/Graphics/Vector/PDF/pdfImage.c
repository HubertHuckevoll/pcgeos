/* PDF 1.1 inline images: bounded ASCIIHex output, no full-image allocation. */
#include "pdfImage.h"
#ifndef PDF_HOST_TEST
#pragma Code ("PdfCode")
#endif
PdfWord PdfImageRowBytes(const PdfImageSpec *spec, PdfWord *bytes)
{
    PdfDWord n;
    if (!spec->width || !spec->height) return PDF_STATE_ERROR;
    if (spec->format == PDF_IMAGE_STENCIL1) n = ((PdfDWord)spec->width + 7) / 8;
    else if (spec->format == PDF_IMAGE_RGB24) n = (PdfDWord)spec->width * 3;
    else if (spec->format == PDF_IMAGE_INDEX4) n = ((PdfDWord)spec->width + 1) / 2;
    else if (spec->format == PDF_IMAGE_INDEX8) n = spec->width;
    else return PDF_UNSUPPORTED;
    if (spec->masked) n += ((PdfDWord)spec->width + 7) / 8;
    if (n > 65535UL) return PDF_LIMIT_ERROR;
    *bytes = (PdfWord)n;
    return PDF_OK;
}

static void imageHex(PdfDocument *p, const unsigned char *data, PdfWord bytes)
{
    char encoded[65];
    PdfWord n, i, at = 0;
    unsigned char c;
    while (at < bytes && !p->error) {
        n = (PdfWord)(bytes - at);
        if (n > 32) n = 32;
        for (i = 0; i < n; ++i) {
            c = data[at + i];
            encoded[2*i] = (char)((c >> 4) < 10 ? '0' + (c >> 4) : 'A' + (c >> 4) - 10);
            encoded[2*i+1] = (char)((c & 15) < 10 ? '0' + (c & 15) : 'A' + (c & 15) - 10);
        }
        encoded[2*n] = 0;
        PdfRaw(p, encoded);
        at += n;
    }
}
/* Keep raster coordinates small: masked tiles have at most 1024 pixels.
 * Separate decimal reciprocals preserve precision without 64-bit arithmetic. */
static void inverse(PdfDocument *p, PdfWord divisor)
{
    char number[13];
    PdfDWord remainder = 1;
    PdfWord i;
    if (divisor == 1) { PdfRaw(p, "1 "); return; }
    number[0] = '0';
    number[1] = '.';
    for (i = 0; i < 10; ++i) {
        remainder *= 10;
        number[i+2] = (char)('0' + remainder / divisor);
        remainder %= divisor;
    }
    number[12] = 0;
    PdfRaw(p, number);
    PdfRaw(p, " ");
}

static void imageHeader(PdfDocument *p, const PdfImageSpec *specP, PdfWord width, PdfWord height)
{
    PdfWord paletteSize, i;
    PdfRaw(p, "BI /W ");
    PdfUnsigned(p, width);
    PdfRaw(p, " /H ");
    PdfUnsigned(p, height);
    if (specP->format == PDF_IMAGE_STENCIL1) PdfRaw(p, " /IM true /BPC 1 /D [1 0]");
    else if (specP->format == PDF_IMAGE_RGB24) PdfRaw(p, " /CS /RGB /BPC 8");
    else {
        paletteSize = specP->format == PDF_IMAGE_INDEX4 ? 16 : 256;
        PdfRaw(p, " /CS [/Indexed /DeviceRGB ");
        PdfUnsigned(p, paletteSize - 1);
        PdfRaw(p, " <");
        imageHex(p, specP->palette, specP->paletteEntries * 3);
        /* The GEOS viewer precomputes every 2^BPC lookup. */
        for (i = specP->paletteEntries; i < paletteSize && !p->error; ++i) PdfRaw(p, "000000");
        PdfRaw(p, ">] /BPC ");
        PdfUnsigned(p, specP->format == PDF_IMAGE_INDEX4 ? 4 : 8);
    }
    PdfRaw(p, " /F /AHx\nID\n");
}

static int covered(const PdfImage *imageP, PdfWord pixel)
{
    return !imageP->maskBytes || (imageP->maskP[pixel/8] & (128 >> (pixel & 7)));
}
/***********************************************************************
 *
 * FUNCTION:    imageTile
 *
 * DESCRIPTION: Encode one inline PDF image tile.
 *
 * PARAMETERS:  p = context; imageP = row and mask state.
 *
 * STRATEGY:    Write one indexed or masked tile.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Keep tile buffers bounded.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static void imageTile(PdfDocument *p, PdfImage *imageP)
{
    PdfWord offset, bytes, pixel, pixels, x = 0, start, any = 0;
    offset = imageP->rowOffset - imageP->maskBytes;
    bytes = imageP->rowBytes - imageP->rowOffset;
    if (imageP->spec.format == PDF_IMAGE_RGB24) {
        if (bytes > 126) bytes = 126;
        pixel = offset / 3;
        pixels = bytes / 3;
    } else {
        if (bytes > 128) bytes = 128;
        pixel = offset;
        pixels = bytes;
        if (imageP->spec.format == PDF_IMAGE_STENCIL1) { pixel *= 8; pixels *= 8; }
        else if (imageP->spec.format == PDF_IMAGE_INDEX4) { pixel *= 2; pixels *= 2; }
        if (pixels > imageP->spec.width - pixel) pixels = imageP->spec.width - pixel;
    }
    imageP->tileLeft = bytes;
    PdfRaw(p, "q 1 0 0 1 ");
    PdfInteger(p, pixel);
    PdfInteger(p, imageP->rows);
    PdfRaw(p, "cm\n");
    while (x < pixels && !p->error) {
        while (x < pixels && !covered(imageP, pixel+x)) ++x;
        start = x;
        while (x < pixels && covered(imageP, pixel+x)) ++x;
        if (x > start) {
            PdfInteger(p, start);
            PdfRaw(p, "0 ");
            PdfInteger(p, x-start);
            PdfRaw(p, "1 re\n");
            any = 1;
        }
    }
    if (!any) PdfRaw(p, "0 0 0 0 re\n");
    PdfRaw(p, "W n\n");
    PdfInteger(p, pixels);
    PdfRaw(p, "0 0 -1 0 1 cm\n");
    imageHeader(p, &imageP->spec, pixels, 1);
}
/***********************************************************************
 *
 * FUNCTION:    imageBegin
 *
 * DESCRIPTION: Start an inline PDF image.
 *
 * PARAMETERS:  p = context; im = image state; spec = format.
 *
 * STRATEGY:    Initialize image geometry and inline PDF header.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Reject invalid image dimensions or format.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static void imageBegin(PdfDocument *p, PdfImage *im, const PdfImageSpec *spec,
                       int x, int y, PdfFixed width, PdfFixed height, unsigned char *maskP)
{
    PdfWord bytes, error;
    if (p->error) return;
    if (!p->inPage || p->imageOpen || width <= 0 || height <= 0 ||
        (spec->masked && !maskP)) { p->error = PDF_STATE_ERROR; return; }
    error = PdfImageRowBytes(spec, &bytes);
    if (error) { p->error = error; return; }
    if ((spec->format == PDF_IMAGE_INDEX4 || spec->format == PDF_IMAGE_INDEX8) &&
        (!spec->palette || !spec->paletteEntries ||
         spec->paletteEntries > (spec->format == PDF_IMAGE_INDEX4 ? 16 : 256))) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    im->spec = *spec;
    im->rowBytes = bytes;
    im->rows = 0;
    im->active = 1;
    im->rowOffset = im->tileLeft = 0;
    im->maskP = maskP;
    im->maskBytes = spec->masked ? (PdfWord)(((PdfDWord)spec->width + 7) / 8) : 0;
    p->imageOpen = 1;
    PdfRaw(p, "q\n1 0 0 1 ");
    PdfInteger(p, x);
    PdfInteger(p, y);
    PdfRaw(p, "cm\n");
    if (im->maskBytes) {
        PdfNumber(p, width);
        PdfRaw(p, "0 0 ");
        PdfNumber(p, height);
        PdfRaw(p, "0 0 cm\n");
        inverse(p, spec->width);
        PdfRaw(p, "0 0 ");
        inverse(p, spec->height);
        PdfRaw(p, "0 0 cm\n");
    } else {
        PdfNumber(p, width);
        PdfRaw(p, "0 0 ");
        PdfNumber(p, -height);
        PdfRaw(p, "0 ");
        PdfNumber(p, height);
        PdfRaw(p, "cm\n");
        imageHeader(p, spec, spec->width, spec->height);
        im->spec.palette = (void*)0;
    }
}

void PdfImageBegin(PdfDocument *p, PdfImage *im, const PdfImageSpec *spec,
                   int x, int y, PdfFixed width, PdfFixed height)
{
    imageBegin(p, im, spec, x, y, width, height, (void*)0);
}

void PdfImageBeginMasked(PdfDocument *p, PdfImage *im, const PdfImageSpec *spec,
                         int x, int y, PdfFixed width, PdfFixed height, unsigned char *maskP)
{
    imageBegin(p, im, spec, x, y, width, height, maskP);
}

void PdfImageRow(PdfDocument *p, PdfImage *im, const unsigned char *row,
                 PdfWord bytes)
{
    if (p->error) return;
    if (!p->imageOpen || !im->active || bytes != im->rowBytes || im->rowOffset) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    PdfImageRowPart(p, im, row, bytes);
}
/***********************************************************************
 *
 * FUNCTION:    PdfImageRowPart
 *
 * DESCRIPTION: Encode a partial bitmap scanline.
 *
 * PARAMETERS:  p = context; im = row state; row/bytes = input.
 *
 * STRATEGY:    Validate and encode part of a scanline.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Invalid row bounds set the PDF error.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfImageRowPart(PdfDocument *p, PdfImage *im, const unsigned char *row,
                     PdfWord bytes)
{
    PdfWord i, index, pixel, offset, n;
    if (p->error) return;
    if (!p->imageOpen || !im->active || im->rows >= im->spec.height ||
        !bytes || bytes > im->rowBytes - im->rowOffset || !row) { p->error = PDF_STATE_ERROR; return; }
    if (im->rowOffset < im->maskBytes) {
        n = im->maskBytes - im->rowOffset;
        if (n > bytes) n = bytes;
        for (i = 0; i < n; ++i) im->maskP[im->rowOffset+i] = row[i];
        im->rowOffset += n;
        row += n;
        bytes -= n;
        if (!bytes) return;
    }
    offset = im->rowOffset - im->maskBytes;
    if (im->spec.format == PDF_IMAGE_INDEX4 || im->spec.format == PDF_IMAGE_INDEX8) {
        for (i = 0; i < bytes; ++i) {
            pixel = offset + i;
            if (im->spec.format == PDF_IMAGE_INDEX4) pixel *= 2;
            index = im->spec.format == PDF_IMAGE_INDEX4 ? row[i] >> 4 : row[i];
            if (index >= im->spec.paletteEntries && covered(im, pixel)) { p->error = PDF_STATE_ERROR; return; }
            if (im->spec.format == PDF_IMAGE_INDEX4 && pixel + 1 < im->spec.width &&
                (row[i] & 15) >= im->spec.paletteEntries && covered(im, pixel+1)) {
                p->error = PDF_STATE_ERROR;
                return;
            }
        }
    }
    if (im->maskBytes) {
        while (bytes && !p->error) {
            if (!im->tileLeft) imageTile(p, im);
            n = im->tileLeft;
            if (n > bytes) n = bytes;
            imageHex(p, row, n);
            row += n;
            bytes -= n;
            im->tileLeft -= n;
            im->rowOffset += n;
            if (!im->tileLeft) PdfRaw(p, "\n>\nEI\nQ\n");
        }
    } else { imageHex(p, row, bytes); im->rowOffset += bytes; }
    if (im->rowOffset == im->rowBytes) {
        if (!im->maskBytes) PdfRaw(p, "\n");
        ++im->rows;
        im->rowOffset = 0;
    }
}

void PdfImageEnd(PdfDocument *p, PdfImage *im)
{
    if (p->error) return;
    if (!p->imageOpen || !im->active || im->rows != im->spec.height || im->rowOffset || im->tileLeft) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    PdfRaw(p, im->maskBytes ? "Q\n" : ">\nEI\nQ\n");
    im->active = 0;
    p->imageOpen = 0;
    im->spec.palette = (void*)0;
    im->maskP = (void*)0;
}
