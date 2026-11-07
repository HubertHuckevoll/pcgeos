/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfWriter.c

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    PdfBegin       - Start PDF object output
    PdfBeginPage   - Open a page content stream
    PdfEndPage     - Close a page content stream
    PdfFinish      - Emit the page tree and cross-reference table
    PdfText        - Write PDF text operations

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Write PDF 1.1 objects and page streams without seeking.
    Buffer only small output chunks and retain object offsets.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* PDF object serialization, shared verbatim by GEOS and host regression tests.
 * Object IDs: 1 catalog, 2 pages, then the standard 14 PDF fonts;
 * each page then owns content, indirect length, page dictionary, in that order.
 */
#include "pdfWriter.h"
#ifndef PDF_HOST_TEST
#include <resource.h>
#pragma Code ("PdfCode")
typedef void _pascal PdfPointTransformCall(void *context, PdfFixed *xP,
                                          PdfFixed *yP, PdfPointTransform *callback);
#endif

static void byteOut(PdfDocument *p, unsigned char c)
{
    if (p->error) {
        return;
    }
    if (p->position == 0xffffffffUL) {
        p->error = PDF_LIMIT_ERROR;
        return;
    }

    p->buffer[p->used++] = c;
    ++p->position;
    if (p->used == PDF_BUFFER_SIZE) {
        PdfFlush(p);
    }
}

/* Commit only complete output chunks; remember stream errors in the job. */
void PdfFlush(PdfDocument *p)
{
    if (!p->error && p->used) {
        if (PdfSink(p, p->buffer, p->used)) {
            p->error = PDF_IO_ERROR;
        }
        p->used = 0;
    }
}

void PdfRaw(PdfDocument *p, const char *s)
{
    while (*s && !p->error) {
        byteOut(p, (unsigned char)*s++);
    }
}

void PdfUnsigned(PdfDocument *p, PdfDWord v)
{
    char digits[10];
    int n = 0;

    do {
        digits[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    while (n) {
        byteOut(p, (unsigned char)digits[--n]);
    }
}

void PdfInteger(PdfDocument *p, PdfFixed v)
{
    PdfDWord n = (PdfDWord)v;

    if (v < 0) {
        byteOut(p, '-');
        n = 0UL - n;
    }

    PdfUnsigned(p, n);
    byteOut(p, ' ');
}

void PdfNumber(PdfDocument *p, PdfFixed v)
{
    PdfDWord mag, frac;
    int i;

    mag = (PdfDWord)v;
    if (v < 0) {
        byteOut(p, '-');
        mag = 0UL - mag;
    }

    PdfUnsigned(p, mag >> 16);
    frac = mag & 65535UL;
    if (frac) {
        byteOut(p, '.');
        /* Five decimal places, truncate. Never floating point or exponent. */
        for (i = 0; i < 5 && frac; ++i) {
            frac *= 10;
            byteOut(p, (unsigned char)('0' + (frac >> 16)));
            frac &= 65535UL;
        }
    }

    byteOut(p, ' ');
}

/* Xref offsets are recorded at object start, before any buffered bytes. */
static void object(PdfDocument *p, PdfWord id)
{
    if (id >= PDF_MAX_OBJECTS) {
        p->error = PDF_LIMIT_ERROR;
        return;
    }

    p->offsets[id] = p->position;
    PdfUnsigned(p, id);
    PdfRaw(p, " 0 obj\n");
}

static void reference(PdfDocument *p, PdfWord id)
{
    PdfUnsigned(p, id);
    PdfRaw(p, " 0 R ");
}

/* Retained geometry supplies a native point-transform callback. Ordinary
 * writer primitives use their existing caller CTM and leave it unset. */
void _pascal PdfPathPoint(PdfDocument *p, PdfFixed x, PdfFixed y)
{
    if (p->pathTransform) {
#ifdef PDF_HOST_TEST
        p->pathTransform(p, &x, &y);
#else
        /* Movable code pointers contain virtual segments, not CPU segments. */
        ((PdfPointTransformCall *)ProcCallFixedOrMovable_pascal)(
            p, &x, &y, p->pathTransform);
#endif
    }
    PdfNumber(p, x);
    PdfNumber(p, y);
}

void _pascal PdfPathRect(PdfDocument *p, PdfFixed x1, PdfFixed y1, PdfFixed x2, PdfFixed y2)
{
    PdfPathPoint(p, x1, y1);
    PdfRaw(p, "m ");
    PdfPathPoint(p, x2, y1);
    PdfRaw(p, "l ");
    PdfPathPoint(p, x2, y2);
    PdfRaw(p, "l ");
    PdfPathPoint(p, x1, y2);
    PdfRaw(p, "l h\n");
}

/***********************************************************************
 *
 * FUNCTION:    PdfBegin
 *
 * DESCRIPTION: Write the initial PDF header and objects.
 *
 * PARAMETERS:  p = document context.
 *
 * STRATEGY:    Write the PDF header and fixed shared objects.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Remember object offsets without seeking.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfBegin(PdfDocument *p)
{
    PdfWord i;

    p->position = 0;
    p->used = 0;
    p->pages = 0;
    p->error = 0;
    p->inPage = 0;
    p->finished = 0;
    p->transformed = 0;
    p->imageOpen = 0;

    if (!p->width || !p->height) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    PdfRaw(p, "%PDF-1.1\n%\200\201\202\203\n");
    object(p, 1);
    PdfRaw(p, "<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");

    /* Standard Type 1 font objects are shared by every page. */
    for (i = 0; i < PDF_FONT_COUNT; ++i) {
        object(p, (PdfWord)(3 + i));
        PdfRaw(p, "<< /Type /Font /Subtype /Type1 /BaseFont /");
        if (i < 4) {
            PdfRaw(p, "Helvetica");
        } else if (i < 8) {
            PdfRaw(p, "Times");
        } else if (i < 12) {
            PdfRaw(p, "Courier");
        } else {
            PdfRaw(p, i == PDF_FONT_SYMBOL ? "Symbol" : "ZapfDingbats");
        }
        if (i < 12) {
            if (i == 4) {
                PdfRaw(p, "-Roman");
            } else if ((i & 3) == 1) {
                PdfRaw(p, "-Bold");
            } else if ((i & 3) == 2) {
                PdfRaw(p, i < 8 && i >= 4 ? "-Italic" : "-Oblique");
            } else if ((i & 3) == 3) {
                PdfRaw(p, i < 8 && i >= 4 ? "-BoldItalic" : "-BoldOblique");
            }
            PdfRaw(p, " /Encoding /MacRomanEncoding");
        }

        PdfRaw(p, " >>\nendobj\n");
    }
}

/***********************************************************************
 *
 * FUNCTION:    PdfBeginPage
 *
 * DESCRIPTION: Begin a physical page content stream.
 *
 * PARAMETERS:  p = document context.
 *
 * STRATEGY:    Open the content stream and clip to physical paper.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Requires a valid document state.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfBeginPage(PdfDocument *p)
{
    PdfWord id;

    if (p->error) {
        return;
    }
    if (p->inPage || p->finished) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    if (p->pages == PDF_MAX_PAGES) {
        p->error = PDF_LIMIT_ERROR;
        return;
    }

    id = (PdfWord)(PDF_FIRST_PAGE_OBJECT + 3 * p->pages);
    object(p, id);
    PdfRaw(p, "<< /Length ");
    reference(p, (PdfWord)(id + 1));
    PdfRaw(p, ">>\nstream\n");
    p->contentStart = p->position;

    /* A fresh page starts with a clean transformation state. */
    p->inPage = 1;
    p->transformed = 0;
    PdfRaw(p, "q\n1 0 0 -1 0 ");
    PdfUnsigned(p, p->height);
    PdfRaw(p, " cm\n");
    /* Physical paper boundary also clips rotated/tiled document pages. */
    PdfRaw(p, "0 0 ");
    PdfUnsigned(p, p->width);
    PdfRaw(p, " ");
    PdfUnsigned(p, p->height);
    PdfRaw(p, " re W n\n");
}

void PdfPageMatrix(PdfDocument *p, const PdfFixed *m)
{
    int i;

    if (!p->inPage || p->transformed) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    for (i = 0; i < 6; ++i) {
        p->pageMatrix[i] = m[i];
    }
    p->transformed = 1;
}

void PdfApplyPageMatrix(PdfDocument *p)
{
    int i;

    if (!p->inPage || !p->transformed) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    for (i = 0; i < 6; ++i) {
        PdfNumber(p, p->pageMatrix[i]);
    }
    PdfRaw(p, "cm\n");
}

/***********************************************************************
 *
 * FUNCTION:    PdfEndPage
 *
 * DESCRIPTION: Close the physical page content stream.
 *
 * PARAMETERS:  p = document context.
 *
 * STRATEGY:    Close the content stream and emit a page dictionary.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Flush can report stream failure.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfEndPage(PdfDocument *p)
{
    PdfWord id, i;
    PdfDWord size;

    if (p->error) {
        return;
    }
    if (!p->inPage || p->imageOpen) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    id = (PdfWord)(PDF_FIRST_PAGE_OBJECT + 3 * p->pages);
    PdfRaw(p, "Q\n");
    size = p->position - p->contentStart;
    PdfRaw(p, "endstream\nendobj\n");
    object(p, (PdfWord)(id + 1));
    PdfUnsigned(p, size);
    PdfRaw(p, "\nendobj\n");
    object(p, (PdfWord)(id + 2));
    PdfRaw(p, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ");
    PdfUnsigned(p, p->width);
    PdfRaw(p, " ");
    PdfUnsigned(p, p->height);
    PdfRaw(p, "] /Resources << /ProcSet [/PDF /Text /ImageB /ImageC /ImageI] /Font << ");
    for (i = 0; i < PDF_FONT_COUNT; ++i) {
        PdfRaw(p, "/F");
        PdfUnsigned(p, i);
        PdfRaw(p, " ");
        reference(p, (PdfWord)(3 + i));
    }

    PdfRaw(p, ">> >> /Contents ");
    reference(p, id);
    PdfRaw(p, ">>\nendobj\n");
    ++p->pages;
    p->inPage = 0;
    PdfFlush(p); /* Bound latency and detect a failed stream at each page. */
}

/***********************************************************************
 *
 * FUNCTION:    PdfFinish
 *
 * DESCRIPTION: Write the PDF cross-reference table and trailer.
 *
 * PARAMETERS:  p = document context.
 *
 * STRATEGY:    Write the page tree, xref offsets and trailer.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Page count and object ID ranges are bounded.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfFinish(PdfDocument *p)
{
    PdfWord i, total;
    PdfDWord xref, divisor;

    if (p->error) {
        return;
    }
    if (p->inPage || p->finished || !p->pages) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    object(p, 2);
    PdfRaw(p, "<< /Type /Pages /Count ");
    PdfUnsigned(p, p->pages);
    PdfRaw(p, " /Kids [");
    for (i = 0; i < p->pages; ++i)
        reference(p, (PdfWord)(PDF_FIRST_PAGE_OBJECT + 3 * i + 2));
    PdfRaw(p, "] >>\nendobj\n");

    /* Xref offsets refer to the serialized stream, not buffer positions. */
    xref = p->position;
    total = (PdfWord)(PDF_FIRST_PAGE_OBJECT + 3 * p->pages);
    PdfRaw(p, "xref\n0 ");
    PdfUnsigned(p, total);
    PdfRaw(p, "\n0000000000 65535 f \n");
    for (i = 1; i < total; ++i) {
        for (divisor = 1000000000UL; divisor; divisor /= 10)
            byteOut(p, (unsigned char)('0' + p->offsets[i] / divisor % 10));
        PdfRaw(p, " 00000 n \n");
    }

    PdfRaw(p, "trailer\n<< /Size ");
    PdfUnsigned(p, total);
    PdfRaw(p, " /Root 1 0 R >>\nstartxref\n");
    PdfUnsigned(p, xref);
    PdfRaw(p, "\n%%EOF\n");
    PdfFlush(p);
    p->finished = 1;
}

void PdfColor(PdfDocument *p, PdfDWord rgb, int stroke)
{
    int i;
    /* GEOS RGBColorAsDWord stores red in the lowest byte. */
    for (i = 0; i < 3; ++i) {
        PdfNumber(p, (PdfFixed)(((rgb & 255UL) * 65536UL) / 255));
        rgb >>= 8;
    }

    PdfRaw(p, stroke ? "RG\n" : "rg\n");
}

void PdfText(PdfDocument *p, PdfFixed x, PdfFixed y, PdfFixed size,
             PdfWord font, const unsigned char *s, PdfWord count)
{
    PdfWord i;
    unsigned char c;
    PdfRaw(p, "BT /F");
    PdfUnsigned(p, font);
    PdfRaw(p, " ");
    PdfNumber(p, size);
    PdfRaw(p, "Tf 1 0 0 -1 ");
    PdfNumber(p, x);
    PdfNumber(p, y);
    PdfRaw(p, "Tm (");

    for (i = 0; i < count; ++i) {
        c = s[i];
        if (c == '(' || c == ')' || c == '\\') {
            byteOut(p, '\\');
        }
        if (c < 32 || c >= 127) {
            byteOut(p, '\\');
            byteOut(p, (unsigned char)('0' + (c >> 6)));
            byteOut(p, (unsigned char)('0' + ((c >> 3) & 7)));
            byteOut(p, (unsigned char)('0' + (c & 7)));
        } else byteOut(p, c);
    }

    PdfRaw(p, ") Tj ET\n");
}
