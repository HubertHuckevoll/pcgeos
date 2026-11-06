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
    else return PDF_UNSUPPORTED;
    if (n > 65535UL) return PDF_LIMIT_ERROR;
    *bytes = (PdfWord)n;
    return PDF_OK;
}
void PdfImageBegin(PdfDocument *p, PdfImage *im, const PdfImageSpec *spec,
                   int x, int y, PdfFixed width, PdfFixed height)
{
    PdfWord bytes, error;
    if (p->error) return;
    if (!p->inPage || p->imageOpen || width <= 0 || height <= 0) {
        p->error = PDF_STATE_ERROR; return;
    }
    error = PdfImageRowBytes(spec, &bytes);
    if (error) { p->error = error; return; }
    im->spec = *spec; im->rowBytes = bytes; im->rows = 0; im->active = 1;
    p->imageOpen = 1;
    /* PDF samples start at the top of image space (y=1). GEOS y increases
     * downward. Separate translation avoids computing y+height in 16.16. */
    PdfRaw(p, "q\n1 0 0 1 "); PdfInteger(p, x); PdfInteger(p, y); PdfRaw(p, "cm\n");
    PdfNumber(p, width); PdfRaw(p, "0 0 "); PdfNumber(p, -height);
    PdfRaw(p, "0 "); PdfNumber(p, height); PdfRaw(p, "cm\nBI /W ");
    PdfUnsigned(p, spec->width); PdfRaw(p, " /H "); PdfUnsigned(p, spec->height);
    if (spec->format == PDF_IMAGE_STENCIL1)
        PdfRaw(p, " /IM true /BPC 1 /D [1 0]");
    else PdfRaw(p, " /CS /RGB /BPC 8");
    PdfRaw(p, " /F /AHx\nID\n");
}
void PdfImageRow(PdfDocument *p, PdfImage *im, const unsigned char *row,
                 PdfWord bytes)
{
    char encoded[65];
    PdfWord n, i, at = 0;
    unsigned char c;
    if (p->error) return;
    if (!p->imageOpen || !im->active || im->rows >= im->spec.height ||
        bytes != im->rowBytes || !row) { p->error = PDF_STATE_ERROR; return; }
    while (at < bytes && !p->error) {
        n = (PdfWord)(bytes - at); if (n > 32) n = 32;
        for (i = 0; i < n; ++i) {
            c = row[at + i];
            encoded[2*i] = (char)((c >> 4) < 10 ? '0' + (c >> 4) : 'A' + (c >> 4) - 10);
            encoded[2*i+1] = (char)((c & 15) < 10 ? '0' + (c & 15) : 'A' + (c & 15) - 10);
        }
        encoded[2*n] = 0; PdfRaw(p, encoded); at += n;
    }
    PdfRaw(p, "\n"); ++im->rows;
}
void PdfImageEnd(PdfDocument *p, PdfImage *im)
{
    if (p->error) return;
    if (!p->imageOpen || !im->active || im->rows != im->spec.height) {
        p->error = PDF_STATE_ERROR; return;
    }
    PdfRaw(p, ">\nEI\nQ\n"); im->active = 0; p->imageOpen = 0;
}
