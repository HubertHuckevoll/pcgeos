/* Small vector primitives, independent of GEOS playback and document objects. */
#include "pdfWriter.h"
#ifndef PDF_HOST_TEST
#pragma Code ("PdfCode")
#endif

static void point(PdfDocument *p, PdfFixed x, PdfFixed y)
{
    PdfNumber(p, x); PdfNumber(p, y);
}

/* Multiply a nonnegative 16.16 radius by the quarter-circle control factor
 * 36195/65536. Splitting the product avoids 64-bit arithmetic on Watcom.
 * The largest intermediate is 65535*36195, which fits an unsigned dword. */
static PdfFixed control(PdfFixed radius)
{
    PdfDWord r = (PdfDWord)radius;
    return (PdfFixed)((r >> 16) * 36195UL +
                     (((r & 65535UL) * 36195UL) >> 16));
}

void PdfEllipse(PdfDocument *p, int x1, int y1, int x2, int y2, int fill)
{
    PdfFixed cx, cy, rx, ry, kx, ky, left, top, right, bottom;
    int swap;
    if (p->error) return;
    if (!p->inPage) { p->error = PDF_STATE_ERROR; return; }
    /* Inputs are signed GEOS word coordinates. Promote before all arithmetic:
     * even a full -32768..32767 bounding box must not overflow a 16-bit int. */
    if (x1 > x2) { swap = x1; x1 = x2; x2 = swap; }
    if (y1 > y2) { swap = y1; y1 = y2; y2 = swap; }
    if (x1 == x2 || y1 == y2) {
        /* Zero-area fills vanish; an outline collapses to a line/point.
         * Avoid a singular scaling matrix, including for collapsed ellipses. */
        if (!fill) {
            PdfInteger(p, x1); PdfInteger(p, y1); PdfRaw(p, "m ");
            PdfInteger(p, x2); PdfInteger(p, y2); PdfRaw(p, "l S\n");
        }
        return;
    }
    cx = (PdfFixed)x1 * 32768L + (PdfFixed)x2 * 32768L;
    cy = (PdfFixed)y1 * 32768L + (PdfFixed)y2 * 32768L;
    rx = ((PdfFixed)x2 - x1) * 32768L;
    ry = ((PdfFixed)y2 - y1) * 32768L;
    kx = control(rx); ky = control(ry);
    left = (PdfFixed)x1 * 65536L; right = (PdfFixed)x2 * 65536L;
    top = (PdfFixed)y1 * 65536L; bottom = (PdfFixed)y2 * 65536L;
    /* Construct in document coordinates. Scaling a stroked unit circle would
     * scale line width differently on each axis. Inherit the caller's CTM. */
    point(p, right, cy); PdfRaw(p, "m\n");
    point(p, right, cy + ky); point(p, cx + kx, bottom); point(p, cx, bottom);
    PdfRaw(p, "c\n");
    point(p, cx - kx, bottom); point(p, left, cy + ky); point(p, left, cy);
    PdfRaw(p, "c\n");
    point(p, left, cy - ky); point(p, cx - kx, top); point(p, cx, top);
    PdfRaw(p, "c\n");
    point(p, cx + kx, top); point(p, right, cy - ky); point(p, right, cy);
    PdfRaw(p, fill ? "c\nh f\n" : "c\nh S\n");
}
