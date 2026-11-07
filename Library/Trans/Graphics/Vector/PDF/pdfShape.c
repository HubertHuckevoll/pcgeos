/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfShape.c

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    PdfRoundRect      - Draw rounded rectangles
    PdfEllipse        - Draw ellipses
    PdfArc            - Draw elliptical arcs
    PdfThreePointArc  - Draw arcs specified by three points
    PdfBrushSegment   - Draw brush segments

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Convert GEOS vector primitives to PDF path operators.
    Use bounded 16.16 fixed-point calculations.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Small vector primitives, independent of GEOS playback and document objects. */
#include "pdfWriter.h"
#ifdef PDF_HOST_TEST
#include <math.h>
/* Host equivalents of the kernel fixed-point primitives. */
static PdfFixed _pascal multiply(PdfFixed a, PdfFixed b)
{
    return (PdfFixed)floor((double)a * b / 65536.0);
}

static PdfFixed _pascal divide(PdfFixed a, PdfFixed b)
{
    return (PdfFixed)((double)a * 65536.0 / b);
}

static PdfFixed _pascal root(PdfFixed a)
{
    return (PdfFixed)sqrt((double)a * 65536.0);
}

static PdfFixed _pascal sine(int angle)
{
    /* GrQuickSine linearly interpolates the integer-degree sine table.
     * This caller needs only integer angles. */
    return (PdfFixed)(sin(angle * 3.14159265358979323846 / 180.0) * 65536.0);
}
#else
#include <graphics.h>
#pragma Code ("PdfCode")
#define multiply(a,b) ((PdfFixed)GrMulWWFixed((a),(b)))
#define divide(a,b) ((PdfFixed)GrUDivWWFixed((a),(b)))
#define root(a) ((PdfFixed)GrSqrRootWWFixed(a))
#define sine(a) ((PdfFixed)GrQuickSine((PdfDWord)(a) * 65536UL))
#endif

static void point(PdfDocument *p, PdfFixed x, PdfFixed y)
{
    PdfPathPoint(p, x, y);
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

/***********************************************************************
 *
 * FUNCTION:    PdfRoundRect
 *
 * DESCRIPTION: Emit a rounded rectangle path.
 *
 * PARAMETERS:  p = context; bounds, radius, fill = shape data.
 *
 * STRATEGY:    Clamp the radius and emit cubic path segments.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Use the caller's transform and clipping.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfRoundRect(PdfDocument *p, int x1, int y1, int x2, int y2,
                  PdfWord radius, int fill)
{
    PdfFixed left, top, right, bottom, r, k, il, it, ir, ib;
    PdfWord limit;
    int swap;

    if (p->error) {
        return;
    }
    if (!p->inPage) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    if (x1 > x2) {
        swap = x1;
        x1 = x2;
        x2 = swap;
    }

    if (y1 > y2) {
        swap = y1;
        y1 = y2;
        y2 = swap;
    }
    /* PrepRoundRectLow uses integer half-extents, rounding down even for
     * odd widths/heights. Clamp the unsigned word BEFORE converting to 16.16. */
    limit = (PdfWord)(((PdfFixed)x2 - x1) / 2);
    if (radius > limit) {
        radius = limit;
    }
    limit = (PdfWord)(((PdfFixed)y2 - y1) / 2);
    if (radius > limit) {
        radius = limit;
    }
    if (!radius) {
        if (fill < 0) {
            PdfPathRect(p, (PdfFixed)x1*65536L, (PdfFixed)y1*65536L,
                        (PdfFixed)x2*65536L, (PdfFixed)y2*65536L);
            return;
        }

        PdfInteger(p, x1);
        PdfInteger(p, y1);
        PdfInteger(p, (PdfFixed)x2 - x1);
        PdfInteger(p, (PdfFixed)y2 - y1);
        PdfRaw(p, fill < 0 ? "re\n" : (fill ? "re f\n" : "re S\n"));
        return;
    }

    /* Work in 16.16 document coordinates, not a scaled PDF CTM. */
    r = (PdfFixed)radius * 65536L;
    k = control(r);
    left = (PdfFixed)x1 * 65536L;
    right = (PdfFixed)x2 * 65536L;
    top = (PdfFixed)y1 * 65536L;
    bottom = (PdfFixed)y2 * 65536L;
    il = left + r;
    ir = right - r;
    it = top + r;
    ib = bottom - r;
    /* As with ellipses, emit in document coordinates so existing line width,
     * transforms and clipping remain the responsibility of the caller. */
    point(p, il, top);
    PdfRaw(p, "m\n");
    point(p, ir, top);
    PdfRaw(p, "l\n");
    point(p, ir + k, top);
    point(p, right, it - k);
    point(p, right, it);
    PdfRaw(p, "c\n");
    point(p, right, ib);
    PdfRaw(p, "l\n");
    point(p, right, ib + k);
    point(p, ir + k, bottom);
    point(p, ir, bottom);
    PdfRaw(p, "c\n");
    point(p, il, bottom);
    PdfRaw(p, "l\n");
    point(p, il - k, bottom);
    point(p, left, ib + k);
    point(p, left, ib);
    PdfRaw(p, "c\n");
    point(p, left, it);
    PdfRaw(p, "l\n");
    point(p, left, it - k);
    point(p, il - k, top);
    point(p, il, top);
    PdfRaw(p, fill < 0 ? "c\nh\n" : (fill ? "c\nh f\n" : "c\nh S\n"));
}

/***********************************************************************
 *
 * FUNCTION:    PdfEllipse
 *
 * DESCRIPTION: Emit an ellipse.
 *
 * PARAMETERS:  p = context; bounds, fill = shape data.
 *
 * STRATEGY:    Approximate the ellipse with cubic curves.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Handle collapsed bounds separately.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfEllipse(PdfDocument *p, int x1, int y1, int x2, int y2, int fill)
{
    PdfFixed cx, cy, rx, ry, kx, ky, left, top, right, bottom;
    int swap;

    if (p->error) {
        return;
    }
    if (!p->inPage) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    /* Inputs are signed GEOS word coordinates. Promote before all arithmetic:
     * even a full -32768..32767 bounding box must not overflow a 16-bit int. */
    if (x1 > x2) {
        swap = x1;
        x1 = x2;
        x2 = swap;
    }

    if (y1 > y2) {
        swap = y1;
        y1 = y2;
        y2 = swap;
    }

    if (x1 == x2 || y1 == y2) {
        /* Zero-area fills vanish; an outline collapses to a line/point.
         * Avoid a singular scaling matrix, including for collapsed ellipses. */
        if (fill <= 0) {
            point(p, (PdfFixed)x1*65536L, (PdfFixed)y1*65536L);
            PdfRaw(p, "m ");
            point(p, (PdfFixed)x2*65536L, (PdfFixed)y2*65536L);
            PdfRaw(p, fill < 0 ? "l\n" : "l S\n");
        }

        return;
    }

    cx = (PdfFixed)x1 * 32768L + (PdfFixed)x2 * 32768L;
    cy = (PdfFixed)y1 * 32768L + (PdfFixed)y2 * 32768L;
    rx = ((PdfFixed)x2 - x1) * 32768L;
    ry = ((PdfFixed)y2 - y1) * 32768L;
    kx = control(rx);
    ky = control(ry);
    left = (PdfFixed)x1 * 65536L;
    right = (PdfFixed)x2 * 65536L;
    top = (PdfFixed)y1 * 65536L;
    bottom = (PdfFixed)y2 * 65536L;
    /* Construct in document coordinates. Scaling a stroked unit circle would
     * scale line width differently on each axis. Inherit the caller's CTM. */
    point(p, right, cy);
    PdfRaw(p, "m\n");
    point(p, right, cy + ky);
    point(p, cx + kx, bottom);
    point(p, cx, bottom);
    PdfRaw(p, "c\n");
    point(p, cx - kx, bottom);
    point(p, left, cy + ky);
    point(p, left, cy);
    PdfRaw(p, "c\n");
    point(p, left, cy - ky);
    point(p, cx - kx, top);
    point(p, cx, top);
    PdfRaw(p, "c\n");
    point(p, cx + kx, top);
    point(p, right, cy - ky);
    point(p, right, cy);
    PdfRaw(p, fill < 0 ? "c\nh\n" : (fill ? "c\nh f\n" : "c\nh S\n"));
}

/* Normalize with guard bits before squaring, including thin ellipses. */
static void _pascal normalize(PdfFixed x, PdfFixed y, PdfFixed *xP, PdfFixed *yP)
{
    PdfFixed largest, length;
    int negativeX = x < 0, negativeY = y < 0;

    if (x == (-2147483647L - 1) || y == (-2147483647L - 1)) {
        x /= 2;
        y /= 2;
    }

    if (negativeX) {
        x = -x;
    }
    if (negativeY) {
        y = -y;
    }
    largest = x > y ? x : y;
    if (!largest) {
        *xP = *yP = 0;
        return;
    }
    while (largest > 4194304L) {
        x >>= 1;
        y >>= 1;
        largest >>= 1;
    }
    while (largest < 2097152L) {
        x <<= 1;
        y <<= 1;
        largest <<= 1;
    }

    length = root(multiply(x, x) + multiply(y, y));
    x = divide(x, length);
    y = divide(y, length);
    if (x > 65536L) {
        x = 65536L;
    }
    if (y > 65536L) {
        y = 65536L;
    }
    *xP = negativeX ? -x : x; *yP = negativeY ? -y : y;
}

/* GEOS angles describe a ray from the center, not the ellipse parameter. */
static void _pascal arcVector(PdfFixed rx, PdfFixed ry, int angle,
                              PdfFixed *xP, PdfFixed *yP)
{
    int quadrant = angle / 90;

    if (!(angle % 90)) {
        *xP = quadrant == 0 ? 65536L : (quadrant == 2 ? -65536L : 0);
        *yP = quadrant == 1 ? 65536L : (quadrant == 3 ? -65536L : 0);
        return;
    }

    normalize(multiply(ry, sine((angle + 90) % 360)),
              multiply(rx, sine(angle)), xP, yP);
}

static PdfFixed _pascal unit(PdfFixed v)
{
    return v < -65536L ? -65536L : (v > 65536L ? 65536L : v);
}

static PdfFixed _pascal coordinate(PdfDocument *p, PdfFixed base, PdfFixed delta)
{
    if ((delta > 0 && base > 0x7fffffffL - delta) ||
        (delta < 0 && base < (-2147483647L - 1) - delta)) {
            p->error = PDF_LIMIT_ERROR;
        return 0;
    }

    return base + delta;
}

/* Both arc forms split at axes, so their cubic controls stay in the bounds. */
static void _pascal arcPiece(PdfDocument *p, PdfFixed cx, PdfFixed cy,
                             PdfFixed rx, PdfFixed ry, PdfFixed x, PdfFixed y,
                             PdfFixed nx, PdfFixed ny, int direction,
                             const PdfFixed *endP)
{
    PdfFixed dot, cross, k, px, py;

    dot = multiply(x, nx) + multiply(y, ny);
    cross = (multiply(x, ny) - multiply(y, nx)) * direction;
    if (dot < 0) {
        dot = 0;
    }
    if (dot > 65536L) {
        dot = 65536L;
    }
    if (cross < 0) {
        cross = 0;
    }
    if (cross > 65536L) {
        cross = 65536L;
    }
    /* k = 4/3 tan(delta/4), delta <= 90 degrees.
     * ATTENTION: quarter-cubic approximation, as for PdfEllipse.
     * Subdivide further if a smaller radial error is required. */
    k = divide(cross, 65536L + dot + root(131072L + dot * 2));
    k = ((k * 4 + 1) / 3) * direction;
    px = coordinate(p, cx, multiply(rx, unit(x - multiply(k, y))));
    py = coordinate(p, cy, -multiply(ry, unit(y + multiply(k, x))));
    point(p, px, py);
    px = coordinate(p, cx, multiply(rx, unit(nx + multiply(k, ny))));
    py = coordinate(p, cy, -multiply(ry, unit(ny - multiply(k, nx))));
    point(p, px, py);
    if (endP) {
        point(p, endP[0], endP[1]);
    } else {
        px = coordinate(p, cx, multiply(rx, nx));
        py = coordinate(p, cy, -multiply(ry, ny));
        point(p, px, py);
    }

    PdfRaw(p, "c\n");
}

/***********************************************************************
 *
 * FUNCTION:    PdfArc
 * DESCRIPTION: Append or paint a bounded GEOS elliptical arc.
 * PARAMETERS:  p = context; bounds and angles = arc data.
 *              fill=-1 appends geometry, 0 strokes, 1 fills; optional
 *              startP receives the subpath start in two fixed coordinates.
 * STRATEGY:    Approximate the selected elliptical arc.
 *              cubic tangents without an inverse-trig approximation.
 *
 ***********************************************************************/
/***********************************************************************
 *
 * FUNCTION:    PdfArc
 *
 * DESCRIPTION: Emit an elliptical arc.
 *
 * PARAMETERS:  p = context; bounds and angles = arc data.
 *
 * STRATEGY:    Approximate the selected elliptical arc.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Some degenerate shapes cannot be represented.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfArc(PdfDocument *p, int x1, int y1, int x2, int y2,
             int start, int end, PdfWord close, int fill, PdfFixed *startP)
{
    PdfFixed cx, cy, rx, ry, x, y, nx, ny;
    int swap, next, left, step;

    if (p->error) {
        return;
    }
    if (!p->inPage || close > 2 || (fill > 0 && !close)) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    if (x1 > x2) {
        swap = x1;
        x1 = x2;
        x2 = swap;
    }

    if (y1 > y2) {
        swap = y1;
        y1 = y2;
        y2 = swap;
    }

    cx = (PdfFixed)x1 * 32768L + (PdfFixed)x2 * 32768L;
    cy = (PdfFixed)y1 * 32768L + (PdfFixed)y2 * 32768L;
    rx = ((PdfFixed)x2 - x1) * 32768L;
    ry = ((PdfFixed)y2 - y1) * 32768L;
    start %= 360;
    if (start < 0) {
        start += 360;
    }
    end %= 360;
    if (end < 0) {
        end += 360;
    }
    left = end - start;
    if (left <= 0) {
        left += 360;
    }
    arcVector(rx, ry, start, &x, &y);
    if (startP) {
        startP[0] = cx + multiply(rx, x);
        startP[1] = cy - multiply(ry, y);
    }

    point(p, cx + multiply(rx, x), cy - multiply(ry, y));
    PdfRaw(p, "m\n");
    while (left && !p->error) {
        step = 90 - start % 90;
        if (step > left) {
            step = left;
        }
        next = (start + step) % 360;
        arcVector(rx, ry, next, &nx, &ny);
        arcPiece(p, cx, cy, rx, ry, x, y, nx, ny, 1, (void*)0);
        x = nx;
        y = ny;
        start = next;
        left -= step;
    }

    if (close == 2) {
        point(p, cx, cy);
        PdfRaw(p, "l\n");
    }

    if (close) {
        PdfRaw(p, "h\n");
    }
    if (fill >= 0) {
        PdfRaw(p, fill ? "f\n" : "S\n");
    }
}

static PdfDWord _pascal magnitude(PdfFixed v)
{
    return v < 0 ? 0UL - (PdfDWord)v : (PdfDWord)v;
}

static PdfDWord _pascal gcd(PdfDWord a, PdfDWord b)
{
    PdfDWord r;

    while (b) {
        r = a % b;
        a = b;
        b = r;
    }

    return a;
}

/* Exact collinearity, without overflowing products of 32-bit differences. */
static int _pascal collinear(const PdfFixed *vP)
{
    PdfDWord a, b, c, d, g;
    int sign1, sign2;

    a = vP[2] >= vP[0] ? (PdfDWord)vP[2] - vP[0] : (PdfDWord)vP[0] - vP[2];
    b = vP[3] >= vP[1] ? (PdfDWord)vP[3] - vP[1] : (PdfDWord)vP[1] - vP[3];
    c = vP[4] >= vP[0] ? (PdfDWord)vP[4] - vP[0] : (PdfDWord)vP[0] - vP[4];
    d = vP[5] >= vP[1] ? (PdfDWord)vP[5] - vP[1] : (PdfDWord)vP[1] - vP[5];
    if ((!a && !b) || (!c && !d)) {
        return 1;
    }
    sign1 = (vP[2] < vP[0]) != (vP[3] < vP[1]);
    sign2 = (vP[4] < vP[0]) != (vP[5] < vP[1]);
    g = gcd(a, b);
    a /= g;
    b /= g;
    g = gcd(c, d);
    c /= g;
    d /= g;
    return a == c && b == d && (!a || !b || sign1 == sign2);
}

/* Guard fixed-point division against overflow before computing the result. */
static PdfFixed _pascal quotient(PdfDocument *p, PdfFixed a, PdfFixed b)
{
    PdfDWord result, numerator = magnitude(a), denominator = magnitude(b);

    if (!denominator || numerator / denominator >= 32768UL) {
        p->error = PDF_LIMIT_ERROR;
        return 0;
    }

    result = divide(numerator, denominator);
    return (a < 0) != (b < 0) ? -(PdfFixed)result : (PdfFixed)result;
}

/* Restore coordinates after the three-point arc normalization. */
static PdfFixed _pascal unscale(PdfDocument *p, PdfFixed v, int shift)
{
    PdfDWord m = magnitude(v);

    if (shift > 0) {
        if (m > (0x7fffffffUL >> shift)) {
            p->error = PDF_LIMIT_ERROR;
            return 0;
        }

        m <<= shift;
    } else m >>= -shift;
    return v < 0 ? -(PdfFixed)m : (PdfFixed)m;
}

/* Append a circular interval in the selected direction, splitting at axes. */
static void _pascal circleInterval(PdfDocument *p, PdfFixed cx, PdfFixed cy,
                                   PdfFixed radius, PdfFixed x, PdfFixed y,
                                   PdfFixed nx, PdfFixed ny, int direction,
                                   const PdfFixed *endP)
{
    PdfFixed ax, ay, cross, dot, remaining;
    int i, last;

    for (i = 0; i < 5 && !p->error; ++i) {
        if (direction > 0) {
            ax = y < 0 ? 65536L : (y > 0 ? -65536L : 0);
            ay = !y ? (x > 0 ? 65536L : -65536L) : 0;
            if (x > 0 && y > 0) {
                ax = 0;
                ay = 65536L;
            }

            if (x < 0 && y < 0) {
                ax = 0;
                ay = -65536L;
            }
        } else {
            ax = y < 0 ? -65536L : (y > 0 ? 65536L : 0);
            ay = !y ? (x > 0 ? -65536L : 65536L) : 0;
            if (x < 0 && y > 0) {
                ax = 0;
                ay = 65536L;
            }

            if (x > 0 && y < 0) {
                ax = 0;
                ay = -65536L;
            }
        }

        cross = (multiply(x, ny) - multiply(y, nx)) * direction;
        dot = multiply(x, nx) + multiply(y, ny);
        remaining = (multiply(nx, ay) - multiply(ny, ax)) * direction;
        last = cross >= 0 && dot >= 0 && remaining >= 0;
        if (last) {
            ax = nx;
            ay = ny;
        }

        arcPiece(p, cx, cy, radius, radius, x, y, ax, ay, direction,
                 last ? endP : (void*)0);
        if (last) {
            return;
        }
        x = ax;
        y = ay;
    }

    if (!p->error) {
        p->error = PDF_STATE_ERROR;
    }
}

/***********************************************************************
 *
 * FUNCTION:    PdfThreePointArc
 * DESCRIPTION: Paint a circular arc through three fractional GEOS points.
 * PARAMETERS:  p = context; pointsP = three points.
 * STRATEGY:    Fit bounded fixed-point curve geometry.
 *              two intervals through point2, using the shared arc cubics.
 *              Collinear points form a line, as in the native kernel.
 * CAVEATS:     ATTENTION: the fit and emitted operands use 16.16. A circle
 *              outside that range, or a non-collinear determinant lost at
 *              that precision, fails with PDF_LIMIT_ERROR. A wider native
 *              fixed-point fitter can extend this without changing playback.
 *
 ***********************************************************************/
/***********************************************************************
 *
 * FUNCTION:    PdfThreePointArc
 *
 * DESCRIPTION: Emit a curve through three points.
 *
 * PARAMETERS:  p = context; pointsP = three points.
 *
 * STRATEGY:    Fit bounded fixed-point curve geometry.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Out-of-range points report PDF_LIMIT_ERROR.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfThreePointArc(PdfDocument *p, const PdfFixed *pointsP, PdfWord close, int fill)
{
    PdfFixed d[4], ux, uy, vx, vy, cross, s, t, ox, oy, cx, cy, radius;
    PdfFixed x, y, mx, my, nx, ny;
    PdfDWord largest = 0, m;
    int shift = 0, i, direction;

    if (p->error) {
        return;
    }
    if (!p->inPage || close > 2 || (fill > 0 && !close)) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    if (collinear(pointsP)) {
        point(p, pointsP[0], pointsP[1]);
        PdfRaw(p, "m ");
        point(p, pointsP[4], pointsP[5]);
        PdfRaw(p, "l\n");
        if (close) {
            PdfRaw(p, "h\n");
        }
        if (fill >= 0) {
            PdfRaw(p, fill ? "f\n" : "S\n");
        }
        return;
    }

    for (i = 0; i < 4; ++i) {
        m = pointsP[i+2] >= pointsP[i%2] ? (PdfDWord)pointsP[i+2] - pointsP[i%2] :
                                                   (PdfDWord)pointsP[i%2] - pointsP[i+2];
        if (m > largest) {
            largest = m;
        }
    }
    while (largest > 1048576UL) {
        largest >>= 1;
        ++shift;
    }
    while (largest < 524288UL) {
        largest <<= 1;
        --shift;
    }

    for (i = 0; i < 4; ++i) {
        m = pointsP[i+2] >= pointsP[i%2] ? (PdfDWord)pointsP[i+2] - pointsP[i%2] :
                                                   (PdfDWord)pointsP[i%2] - pointsP[i+2];
        m = shift > 0 ? m >> shift : m << -shift;
        d[i] = pointsP[i+2] < pointsP[i%2] ? -(PdfFixed)m : (PdfFixed)m;
    }

    ux = d[0];
    uy = d[1];
    vx = d[2];
    vy = d[3];
    cross = multiply(ux, vy) - multiply(uy, vx);
    direction = cross < 0 ? 1 : -1; /* PDF construction uses mathematical Y. */
    s = (multiply(ux, ux) + multiply(uy, uy)) / 2;
    t = (multiply(vx, vx) + multiply(vy, vy)) / 2;
    ox = quotient(p, multiply(s, vy) - multiply(t, uy), cross);
    oy = quotient(p, multiply(t, ux) - multiply(s, vx), cross);
    if (p->error) {
        return;
    }
    normalize(-ox, oy, &x, &y);
    radius = magnitude(x) >= magnitude(y) ? quotient(p, -ox, x) : quotient(p, oy, y);
    radius = unscale(p, radius, shift);
    cx = coordinate(p, pointsP[0], unscale(p, ox, shift));
    cy = coordinate(p, pointsP[1], unscale(p, oy, shift));
    mx = coordinate(p, ux, -ox);
    my = coordinate(p, oy, -uy);
    nx = coordinate(p, vx, -ox);
    ny = coordinate(p, oy, -vy);
    if (p->error) {
        return;
    }
    normalize(mx, my, &mx, &my);
    normalize(nx, ny, &nx, &ny);
    point(p, pointsP[0], pointsP[1]);
    PdfRaw(p, "m\n");
    circleInterval(p, cx, cy, radius, x, y, mx, my, direction, pointsP+2);
    circleInterval(p, cx, cy, radius, mx, my, nx, ny, direction, pointsP+4);
    if (close == 2) {
        point(p, cx, cy);
        PdfRaw(p, "l\n");
    }

    if (close) {
        PdfRaw(p, "h\n");
    }
    if (fill >= 0) {
        PdfRaw(p, fill ? "f\n" : "S\n");
    }
}

/* VidCom's DDA groups horizontal/vertical pixel runs. Brush coverage extends
 * right/down, independently of line width, dashes, joins and end caps. */
/***********************************************************************
 *
 * FUNCTION:    PdfBrushSegment
 *
 * DESCRIPTION: Render a device brush segment.
 *
 * PARAMETERS:  p = context; endpoints and brush size = pixels.
 *
 * STRATEGY:    Emit the filled pixel footprint.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              The caller chooses device coordinate scale.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

void PdfBrushSegment(PdfDocument *p, PdfFixed x1, PdfFixed y1,
                      PdfFixed x2, PdfFixed y2, PdfWord width, PdfWord height)
{
    PdfFixed dx, dy, major, minor, error, at, run, end, minorAt;
    PdfFixed left, top, runWidth, runHeight;
    int alongX, majorSign, minorSign, bump;

    if (p->error) {
        return;
    }
    if (!p->inPage || !width || !height || width > 128 || height > 128) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    /* Coordinates come from signed 16.16 physical points at the device DPI.
     * This bound also keeps doubled DDA differences safely inside 32 bits. */
    if (magnitude(x1) > 32768UL*PDF_DEVICE_DPI/72+1 ||
        magnitude(y1) > 32768UL*PDF_DEVICE_DPI/72+1 ||
        magnitude(x2) > 32768UL*PDF_DEVICE_DPI/72+1 ||
        magnitude(y2) > 32768UL*PDF_DEVICE_DPI/72+1) {
            p->error = PDF_LIMIT_ERROR;
        return;
    }

    dx = x2 >= x1 ? x2-x1 : x1-x2;
    dy = y2 >= y1 ? y2-y1 : y1-y2;
    alongX = dx >= dy;
    major = alongX ? dx : dy;
    minor = alongX ? dy : dx;
    at = run = alongX ? x1 : y1;
    end = alongX ? x2 : y2;
    minorAt = alongX ? y1 : x1;
    majorSign = end >= at ? 1 : -1;
    minorSign = (alongX ? y2 >= y1 : x2 >= x1) ? 1 : -1;
    error = minor*2-major;
    while (!p->error) {
        /* Native ties depend on dominant-axis direction so reversing a line
         * keeps the same covered pixels (vidcomLine.asm:DDA_X/DDA_Y). */
        bump = error > 0 || (!error && majorSign > 0);
        if (bump || at == end || !minor) {
            if (!minor) {
                at = end;
            }
            left = alongX ? (run < at ? run : at) : minorAt;
            top = alongX ? minorAt : (run < at ? run : at);
            runWidth = width + (alongX ? (at >= run ? at-run : run-at) : 0);
            runHeight = height + (alongX ? 0 : (at >= run ? at-run : run-at));
            PdfInteger(p, left);
            PdfInteger(p, top);
            PdfInteger(p, runWidth);
            PdfInteger(p, runHeight);
            PdfRaw(p, "re f\n");
            if (at == end) {
                break;
            }
            run = at + majorSign;
            minorAt += minorSign;
            error -= major*2;
        }

        at += majorSign;
        error += minor*2;
    }
}
