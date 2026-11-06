/* GEOS adapter and GString translator. Kernel playback maintains attributes,
 * current position and transforms; only output primitives are serialized here.
 * No raw GString byte stream is interpreted without GrGetGStringElement.
 */
#ifdef PDF_HOST_TEST
#include "tests/geosmock.h"
#else
#include <geos.h>
#include <heap.h>
#include <graphics.h>
#include <gstring.h>
#include <font.h>
#endif
#include "pdfWriter.h"
#pragma Code ("PdfCode")

extern word _pascal PDFSTREAMWRITE(word token, void (*strategy)(void),
                                  const void *data, word size);

PdfWord PdfSink(PdfDocument *p, const void *data, PdfWord size)
{
    return PDFSTREAMWRITE(p->token, p->strategy, data, size);
}
static PdfFixed fixed(WWFixed v)
{
    return (PdfFixed)((dword)(word)v.WWF_int << 16 | v.WWF_frac);
}
static Boolean matrix(PdfDocument *p, const TransMatrix *t, PdfFixed *m)
{
    /* The first milestone uses 16.16 PDF operands. Detect, do not wrap,
     * the kernel's wider 32.16 translation values. */
    if (t->TM_e31.DWF_int < -32768L || t->TM_e31.DWF_int > 32767L ||
        t->TM_e32.DWF_int < -32768L || t->TM_e32.DWF_int > 32767L) {
        p->error = PDF_LIMIT_ERROR; return FALSE;
    }
    m[0] = fixed(t->TM_e11); m[1] = fixed(t->TM_e12);
    m[2] = fixed(t->TM_e21); m[3] = fixed(t->TM_e22);
    m[4] = (PdfFixed)((dword)t->TM_e31.DWF_int << 16 | t->TM_e31.DWF_frac);
    m[5] = (PdfFixed)((dword)t->TM_e32.DWF_int << 16 | t->TM_e32.DWF_frac);
    return TRUE;
}
MemHandle _pascal _export PDFCREATE(word token, void (*strategy)(void), word width, word height)
{
    MemHandle h;
    PdfDocument *p;
    h = MemAlloc(sizeof(PdfDocument), HF_DYNAMIC, HAF_ZERO_INIT | HAF_LOCK);
    if (!h) return 0;
    p = MemDeref(h);
    p->token = token; p->strategy = strategy; p->width = width; p->height = height;
    PdfBegin(p); PdfFlush(p);
    if (p->error) { MemFree(h); return 0; }
    MemUnlock(h); return h;
}
word _pascal _export PDFSTARTPAGE(MemHandle h)
{
    PdfDocument *p = MemLock(h);
    word error;
    PdfBeginPage(p); error = p->error; MemUnlock(h); return error;
}
word _pascal _export PDFSETTRANSFORM(MemHandle h, const TransMatrix *t)
{
    PdfDocument *p = MemLock(h);
    PdfFixed m[6];
    word error;
    if (matrix(p, t, m)) PdfPageMatrix(p, m);
    error = p->error; MemUnlock(h); return error;
}
word _pascal _export PDFENDPAGE(MemHandle h)
{
    PdfDocument *p = MemLock(h);
    word error;
    PdfEndPage(p); error = p->error; MemUnlock(h); return error;
}
word _pascal _export PDFDESTROY(MemHandle h)
{
    PdfDocument *p;
    word error;
    if (!h) return PDF_OK;
    p = MemLock(h);
    PdfFinish(p); error = p->error;
    MemFree(h); return error;
}
/* Explicit little endian decoding avoids unaligned/incorrect public OpDrawLine
 * member names (CInclude/gstring.h swaps x2/y1; its GS macro is correct). */
static word u16(const byte *b) { return (word)(b[0] | (word)b[1] << 8); }
static int s16(const byte *b) { return (sword)u16(b); }
static void point(PdfDocument *p, int x, int y, const char *op)
{
    PdfInteger(p, x); PdfInteger(p, y); PdfRaw(p, op);
}
static void attributes(PdfDocument *p, GStateHandle gs, Boolean fill)
{
    TransMatrix t;
    PdfFixed m[6];
    int i;
    if (GrGetMixMode(gs) != MM_COPY ||
        (fill ? GrGetAreaMask(gs, (DrawMask *)0) : GrGetLineMask(gs, (DrawMask *)0)) != SDM_100 ||
        (!fill && GrGetLineStyle(gs) != LS_SOLID)) {
        p->error = PDF_UNSUPPORTED; return;
    }
    GrGetTransform(gs, &t);
    PdfRaw(p, "q\n");
    if (!matrix(p, &t, m)) return;
    for (i = 0; i < 6; ++i) PdfNumber(p, m[i]);
    PdfRaw(p, "cm\n");
    PdfColor(p, fill ? GrGetAreaColor(gs) : GrGetLineColor(gs), !fill);
    if (!fill) {
        PdfNumber(p, (PdfFixed)GrGetLineWidth(gs)); PdfRaw(p, "w\n");
        PdfInteger(p, GrGetLineEnd(gs)); PdfRaw(p, "J\n");
        PdfInteger(p, GrGetLineJoin(gs)); PdfRaw(p, "j\n");
        PdfNumber(p, (PdfFixed)GrGetMiterLimit(gs)); PdfRaw(p, "M\n");
    }
}
static void text(PdfDocument *p, GStateHandle gs, int x, int y,
                 const byte *s, word count, Boolean baseline)
{
    WWFixedAsDWord size;
    word style, font, i;
    int dx;
    if (GrGetTextMask(gs, (DrawMask *)0) != SDM_100) {
        p->error = PDF_UNSUPPORTED; return;
    }
    GrGetFont(gs, &size);
    style = GrGetTextStyle(gs);
    if (style & ~(TS_BOLD | TS_ITALIC)) { p->error = PDF_UNSUPPORTED; return; }
    if (!baseline) {
        if (!(GrGetTextMode(gs) & TM_DRAW_BASE)) {
            y += (int)(GrFontMetrics(gs, GFMI_BASELINE) >> 16);
            if (GrGetTextMode(gs) & TM_DRAW_BOTTOM)
                y -= (int)(GrFontMetrics(gs, GFMI_HEIGHT) >> 16);
            else if (GrGetTextMode(gs) & TM_DRAW_ACCENT)
                y -= (int)(GrFontMetrics(gs, GFMI_ACCENT) >> 16);
        }
    }
    font = (style & TS_BOLD ? 1 : 0) + (style & TS_ITALIC ? 2 : 0);
    PdfColor(p, GrGetTextColor(gs), 0);
    /* Place characters at GEOS-measured positions so substituting a base font
     * cannot change the line breaks or move following runs. */
    for (i = 0; i < count && !p->error; ++i) {
        if (s[i] < 32 || s[i] == 0x7f || s[i] == 0xb6 || s[i] == 0xb7 ||
            s[i] == 0xb8 || s[i] == 0xdb || s[i] == 0xde || s[i] == 0xdf || s[i] == 0xf0) { p->error = PDF_UNSUPPORTED; break; }
        dx = i ? (int)GrTextWidth(gs, (const char *)s, i) : 0;
        if ((long)x + dx > 32767L) { p->error = PDF_LIMIT_ERROR; break; }
        PdfText(p, x + dx, y, (PdfFixed)size, font, s + i, 1);
    }
}
/* Wire layout defined in Include/text.def and Include/gstring.def. Not public
 * in CInclude: keep these private and byte packed (GEOS C builds use -zp1). */
#pragma pack(1)
typedef struct {
    word count;
    WBFixed x, y, baseline;
    word limit;
    byte flags;
} PdfTextField;
typedef struct { word count; TextAttr attr; } PdfTextRun;
#pragma pack()
static void textField(PdfDocument *p, GStateHandle gs, const byte *b, word size)
{
    const PdfTextField *f;
    const PdfTextRun *r;
    word left, pos, n;
    int x, y;
    if (size < 1 + sizeof(PdfTextField)) { p->error = PDF_STATE_ERROR; return; }
    f = (const PdfTextField *)(b + 1);
    if (f->flags) { p->error = PDF_UNSUPPORTED; return; }
    left = f->count; x = f->x.WBF_int;
    y = f->y.WBF_int + f->baseline.WBF_int;
    pos = 1 + sizeof(PdfTextField);
    while (left && !p->error) {
        if (pos > size || (word)(size - pos) < (word)sizeof(PdfTextRun)) { p->error = PDF_STATE_ERROR; break; }
        r = (const PdfTextRun *)(b + pos); n = r->count;
        pos += sizeof(PdfTextRun);
        if (!n || n > left || n > size - pos) { p->error = PDF_STATE_ERROR; break; }
        GrSetTextAttr(gs, &r->attr);
        text(p, gs, x, y, b + pos, n, TRUE);
        { long next = (long)x + GrTextWidth(gs, (const char *)(b + pos), n);
          if (next > 32767L) { p->error = PDF_LIMIT_ERROR; break; }
          x = (int)next; }
        left -= n; pos += n;
    }
}
static void output(PdfDocument *p, GStateHandle gs, const byte *b, word size)
{
    word op = b[0], n, pos, i;
    XYValueAsDWord cp = GrGetCurPos(gs);
    int x = (sword)(word)cp, y = (sword)(word)(cp >> 16);
    int x2, y2;
    Boolean fill = op == GR_FILL_RECT || op == GR_FILL_RECT_TO || op == GR_FILL_POLYGON;
    attributes(p, gs, fill);
    switch (op) {
    case GR_DRAW_LINE:
        if (size != 9) goto bad;
        point(p, s16(b+1), s16(b+3), "m "); point(p, s16(b+5), s16(b+7), "l S\n"); break;
    case GR_DRAW_LINE_TO:
        if (size != 5) goto bad;
        point(p, x, y, "m "); point(p, s16(b+1), s16(b+3), "l S\n"); break;
    case GR_DRAW_HLINE: case GR_DRAW_VLINE:
        if (size != 7) goto bad;
        x = s16(b+1); y = s16(b+3); x2 = x; y2 = y;
        if (op == GR_DRAW_HLINE) x2 = s16(b+5); else y2 = s16(b+5);
        point(p, x, y, "m "); point(p, x2, y2, "l S\n"); break;
    case GR_DRAW_HLINE_TO: case GR_DRAW_VLINE_TO:
        if (size != 3) goto bad;
        x2 = x; y2 = y;
        if (op == GR_DRAW_HLINE_TO) x2 = s16(b+1); else y2 = s16(b+1);
        point(p, x, y, "m "); point(p, x2, y2, "l S\n"); break;
    case GR_DRAW_RECT: case GR_FILL_RECT:
        if (size != 9) goto bad;
        x = s16(b+1); y = s16(b+3); b += 4;
        /* FALLTHROUGH */
    case GR_DRAW_RECT_TO: case GR_FILL_RECT_TO:
        if ((op == GR_DRAW_RECT_TO || op == GR_FILL_RECT_TO) && size != 5) goto bad;
        x2 = s16(b+1); y2 = s16(b+3);
        PdfInteger(p, x); PdfInteger(p, y);
        PdfInteger(p, (long)x2 - x); PdfInteger(p, (long)y2 - y);
        PdfRaw(p, fill ? "re f\n" : "re S\n"); break;
    case GR_DRAW_CURVE: case GR_DRAW_CURVE_TO:
        pos = 1;
        if (op == GR_DRAW_CURVE) {
            if (size != 17) goto bad;
            x = s16(b+1); y = s16(b+3); pos = 5;
        } else if (size != 13) goto bad;
        point(p, x, y, "m ");
        for (i = 0; i < 3; ++i, pos += 4) point(p, s16(b+pos), s16(b+pos+2), "");
        PdfRaw(p, "c S\n"); break;
    case GR_DRAW_POLYLINE: case GR_DRAW_POLYGON: case GR_FILL_POLYGON:
        if (size < (fill ? 4 : 3)) goto bad;
        n = u16(b+1); pos = fill ? 4 : 3;
        if (!n || n > (size - pos) / 4 || size - pos != n * 4) goto bad;
        for (i = 0; i < n; ++i, pos += 4)
            point(p, s16(b+pos), s16(b+pos+2), i ? "l " : "m ");
        PdfRaw(p, fill ? (b[3] ? "h f\n" : "h f*\n") :
                        (op == GR_DRAW_POLYGON ? "h S\n" : "S\n")); break;
    case GR_DRAW_TEXT:
        if (size < 7 || u16(b+5) != size - 7) goto bad;
        text(p, gs, s16(b+1), s16(b+3), b+7, u16(b+5), FALSE); break;
    case GR_DRAW_TEXT_CP:
        if (size < 3 || u16(b+1) != size - 3) goto bad;
        text(p, gs, x, y, b+3, u16(b+1), FALSE); break;
    case GR_DRAW_CHAR:
        if (size != 6) goto bad;
        text(p, gs, s16(b+2), s16(b+4), b+1, 1, FALSE); break;
    case GR_DRAW_CHAR_CP:
        if (size != 2) goto bad;
        text(p, gs, x, y, b+1, 1, FALSE); break;
    case GR_DRAW_TEXT_FIELD:
        textField(p, gs, b, size); break;
    default:
        p->error = PDF_UNSUPPORTED;
    }
    PdfRaw(p, "Q\n"); return;
bad:
    p->error = PDF_STATE_ERROR;
}
word _pascal _export PDFGSTRING(MemHandle h, GStateHandle string, word flags)
{
    PdfDocument *p = MemLock(h);
    GStateHandle gs = GrCreateState(0);
    MemHandle element = 0;
    byte *b;
    word size, last, result = GSRT_FAULT, depth = 0;
    byte clipped[32];
    byte op;
    (void)flags; /* PDL contract always ends at a physical page boundary. */
    if (!p->inPage || !p->transformed) p->error = PDF_STATE_ERROR;
    clipped[0] = 0;
    PdfRaw(p, "q\n");
    while (!p->error) {
        op = GrGetGStringElement(gs, string, 0, (void *)0, &size);
        if (!size) { p->error = PDF_STATE_ERROR; break; }
        if (op == GR_END_GSTRING || op == GR_NEW_PAGE) {
            if (op == GR_NEW_PAGE) GrSetGStringPos(string, GSSPT_SKIP_1, 0);
            result = op == GR_NEW_PAGE ? GSRT_NEW_PAGE : GSRT_COMPLETE; break;
        }
        if (op == GR_SAVE_STATE) {
            if (depth == 31) { p->error = PDF_LIMIT_ERROR; break; }
            clipped[++depth] = 0; PdfRaw(p, "q\n");
        } else if (op == GR_RESTORE_STATE) {
            if (!depth) { p->error = PDF_STATE_ERROR; break; }
            --depth; PdfRaw(p, "Q\n");
        } else if (op == GR_SET_CLIP_RECT) {
            byte rect[11];
            word combine, i;
            PointWWFixed corner;
            int x1, y1, x2, y2, x, y;
            if (size != sizeof(rect)) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, rect, &size);
            combine = u16(rect + 1);
            if (combine != PCT_INTERSECTION) {
                /* Replacing a parent scope's clip needs replaying its stack.
                 * Reject that uncommon case until arbitrary paths are added. */
                for (i = 0; i < depth; ++i) if (clipped[i]) break;
                if (i != depth || combine == PCT_UNION || combine > PCT_INTERSECTION) {
                    p->error = PDF_UNSUPPORTED; break;
                }
                PdfRaw(p, "Q q\n"); clipped[depth] = 0;
            }
            if (combine != PCT_NULL) {
                x1 = s16(rect+3); y1 = s16(rect+5);
                x2 = s16(rect+7); y2 = s16(rect+9);
                for (i = 0; i < 4; ++i) {
                    x = (i == 1 || i == 2) ? x2 : x1;
                    y = (i >= 2) ? y2 : y1;
                    GrTransformWWFixed(gs, (dword)(word)x << 16,
                                       (dword)(word)y << 16, &corner);
                    PdfNumber(p, fixed(corner.PF_x)); PdfNumber(p, fixed(corner.PF_y));
                    PdfRaw(p, i ? "l " : "m ");
                }
                PdfRaw(p, "h W n\n"); clipped[depth] = 1;
            }
        } else if (op >= GR_BEGIN_PATH || op == GR_ESCAPE ||
                   op == GR_SET_CUSTOM_LINE_STYLE || op == GR_SET_CUSTOM_AREA_PATTERN ||
                   op == GR_SET_CUSTOM_TEXT_PATTERN || op == GR_SET_AREA_PATTERN ||
                   op == GR_SET_TEXT_PATTERN) {
            p->error = PDF_UNSUPPORTED; break;
        }
        if (op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F) {
            if (size > 32760) { p->error = PDF_LIMIT_ERROR; break; }
            element = MemAlloc(size, HF_DYNAMIC, HAF_LOCK);
            if (!element) { p->error = PDF_LIMIT_ERROR; break; }
            b = MemDeref(element);
            GrGetGStringElement(gs, string, size, b, &size);
            output(p, gs, b, size);
            MemFree(element); element = 0;
            if (p->error) break;
        }
        result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
        if (result != GSRT_ONE && result != GSRT_COMPLETE) { p->error = PDF_STATE_ERROR; break; }
    }
    if (depth) p->error = PDF_STATE_ERROR;
    PdfRaw(p, "Q\n");
    if (p->error) result = GSRT_FAULT;
    GrDestroyState(gs); MemUnlock(h); return result;
}
