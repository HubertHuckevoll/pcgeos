/* GEOS adapter and GString translator. Kernel playback maintains attributes,
 * current position and transforms; only output primitives are serialized here.
 * No raw GString byte stream is interpreted without GrGetGStringElement.
 */
#ifdef PDF_HOST_TEST
#include "tests/geosmock.h"
#else
#include <geos.h>
#include <ec.h>
#include <heap.h>
#include <system.h>
#include <graphics.h>
#include <gstring.h>
#include <font.h>
#include <fontID.h>
#include <char.h>
#endif
#include "pdfWriter.h"
#include "pdfBitmap.h"
#pragma Code ("PdfCode")

extern word _pascal PDFSTREAMWRITE(word token, void (*strategy)(void),
                                  const void *data, word size);

extern dword _pascal PDFTEXTWIDTHFIXED(GStateHandle gs, const char *textP, word count);
extern void _pascal PDFGETDASH(GStateHandle gs, byte *dashP);
/* The kernel C entry returns packed PatternInfo in AX. Watcom's struct
 * return convention would instead dereference AX as a result pointer. */
extern word _pascal GRGETTEXTPATTERN(GStateHandle gs, MemHandle *patternH,
                                   word *patternSize);

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
static void _pascal nativePath(PdfDocument *p, GStateHandle gs, word type, int paint);
static void _pascal clipPaths(PdfDocument *p, GStateHandle gs)
{
    nativePath(p, gs, GPT_WIN_CLIP, 2);
    if (!p->error) nativePath(p, gs, GPT_CLIP, 2);
}
static void _pascal lineDash(PdfDocument *p, GStateHandle gs, PdfFixed width)
{
    byte dash[12];
    word i, factor;
    if (GrGetLineStyle(gs) == LS_SOLID) { PdfRaw(p, "[] 0 d\n"); return; }
    PDFGETDASH(gs, dash);
    if (!dash[0] || dash[0] > 5 || dash[1] > 127 || width < 0) {
        p->error = PDF_STATE_ERROR; return;
    }
    /* ATTENTION: a PDF hairline has device-dependent width. Use SvgLib's
     * 1/16-point dash scale until a target-resolution policy is available. */
    if (!width) width = 4096;
    PdfRaw(p, "[");
    for (i = 0; i < (word)dash[0] * 2 + 1; ++i) {
        factor = i == dash[0] * 2 ? dash[1] : dash[2+i];
        if ((!factor && i < dash[0] * 2) ||
            (factor && width > 0x7fffffffL / factor)) {
            p->error = PDF_LIMIT_ERROR; return;
        }
        if (i == dash[0] * 2) PdfRaw(p, "] ");
        PdfNumber(p, width * factor);
    }
    PdfRaw(p, "d\n");
}
static void attributes(PdfDocument *p, GStateHandle gs, Boolean fill,
                       Boolean textOutput)
{
    TransMatrix t;
    PdfFixed m[6], width;
    word drawMask = SDM_100;
    int i;
    if (!textOutput) {
        drawMask = fill ? GrGetAreaMask(gs, (DrawMask *)0) : GrGetLineMask(gs, (DrawMask *)0);
        if (drawMask != SDM_0 && (GrGetMixMode(gs) != MM_COPY ||
            drawMask != SDM_100)) {
            p->error = PDF_UNSUPPORTED; return;
        }
    }
    GrGetTransform(gs, &t);
    PdfRaw(p, "q\n");
    /* Keep operand validation and kernel pen updates for invisible shapes. */
    if (drawMask == SDM_0) PdfRaw(p, "0 0 0 0 re W n\n");
    if (!matrix(p, &t, m)) return;
    for (i = 0; i < 6; ++i) PdfNumber(p, m[i]);
    PdfRaw(p, "cm\n");
    if (!textOutput) PdfColor(p, fill ? GrGetAreaColor(gs) : GrGetLineColor(gs), !fill);
    if (!fill && !textOutput) {
        width = (PdfFixed)GrGetLineWidth(gs);
        PdfNumber(p, width); PdfRaw(p, "w\n");
        if (drawMask != SDM_0) lineDash(p, gs, width);
        PdfInteger(p, GrGetLineEnd(gs)); PdfRaw(p, "J\n");
        PdfInteger(p, GrGetLineJoin(gs)); PdfRaw(p, "j\n");
        PdfNumber(p, (PdfFixed)GrGetMiterLimit(gs)); PdfRaw(p, "M\n");
    }
}
/* GEOS mathematical characters absent from PDF MacRomanEncoding. The
 * Symbol byte values are the existing EPS greekMapTab mapping. */
static word _pascal textCharacter(byte source, byte *encodedP, word font)
{
    switch (source) {
    case C_NONBRKHYPHEN: *encodedP = '-'; return font;
    case 0xad: *encodedP = 0xb9; return PDF_FONT_SYMBOL;
    case 0xb0: *encodedP = 0xa5; return PDF_FONT_SYMBOL;
    case 0xb2: *encodedP = 0xa3; return PDF_FONT_SYMBOL;
    case 0xb3: *encodedP = 0xb3; return PDF_FONT_SYMBOL;
    case 0xb6: *encodedP = 0x64; return PDF_FONT_SYMBOL;
    case 0xb7: *encodedP = 0x53; return PDF_FONT_SYMBOL;
    case 0xb8: *encodedP = 0x50; return PDF_FONT_SYMBOL;
    case 0xb9: *encodedP = 0x70; return PDF_FONT_SYMBOL;
    case 0xba: *encodedP = 0xf2; return PDF_FONT_SYMBOL;
    case 0xbd: *encodedP = 0x57; return PDF_FONT_SYMBOL;
    case 0xc3: *encodedP = 0xd6; return PDF_FONT_SYMBOL;
    case 0xc5: *encodedP = 0xbb; return PDF_FONT_SYMBOL;
    case 0xc6: *encodedP = 0x44; return PDF_FONT_SYMBOL;
    case 0xd7: *encodedP = 0xe0; return PDF_FONT_SYMBOL;
    default:
        *encodedP = source;
        if (source < 32 || source == 0x7f || source == 0xdb ||
            source == 0xde || source == 0xdf || source == 0xf0) return 0xffff;
        return font;
    }
}
/* Checked addition also keeps fractional pen/run advances inside 16.16. */
static Boolean _pascal addFixed(PdfDocument *p, PdfFixed a, PdfFixed b, PdfFixed *sumP)
{
    if ((b > 0 && a > 0x7fffffffL - b) ||
        (b < 0 && a < (-2147483647L - 1) - b)) {
        p->error = PDF_LIMIT_ERROR; return FALSE;
    }
    *sumP = a + b; return TRUE;
}
static PdfFixed _pascal text(PdfDocument *p, GStateHandle gs, PdfFixed x, PdfFixed y,
                             const byte *s, word count, Boolean baseline, word limit)
{
    WWFixedAsDWord size;
    word style, font, i, drawMask, fontID, glyphFont, patternSize, mode;
    MemHandle patternH;
    word pattern;
    byte encoded, glyph, pair[2];
    PdfFixed advance = 0, previous = 0, width, kern, origin, offset, thickness, fontBase;
    Boolean visible;

    drawMask = GrGetTextMask(gs, (DrawMask *)0);
    visible = drawMask != SDM_0;
    if (visible && (drawMask != SDM_100 || GrGetMixMode(gs) != MM_COPY)) {
        p->error = PDF_UNSUPPORTED; return 0;
    }
    pattern = GRGETTEXTPATTERN(gs, &patternH, &patternSize);
    if (((byte)pattern == PT_CUSTOM_HATCH || (byte)pattern == PT_CUSTOM_BITMAP) && patternH)
        MemFree(patternH);
    if (visible && (byte)pattern != PT_SOLID) { p->error = PDF_UNSUPPORTED; return 0; }
    fontID = GrGetFont(gs, &size);
    style = GrGetTextStyle(gs);
    if (visible && (style & ~(TS_BOLD | TS_ITALIC | TS_UNDERLINE | TS_STRIKE_THRU))) { p->error = PDF_UNSUPPORTED; return 0; }
    mode = GrGetTextMode(gs);
    if (!baseline && !(mode & TM_DRAW_BASE)) {
        offset = (PdfFixed)GrFontMetrics(gs, GFMI_BASELINE);
        if (mode & TM_DRAW_BOTTOM) offset -= (PdfFixed)GrFontMetrics(gs, GFMI_HEIGHT);
        else if (mode & TM_DRAW_ACCENT) offset -= (PdfFixed)GrFontMetrics(gs, GFMI_ACCENT);
        if (!addFixed(p, y, offset, &y)) return 0;
    }
    font = (style & TS_BOLD ? 1 : 0) + (style & TS_ITALIC ? 2 : 0);
    switch (fontID & 0x0e00) {
    case FG_SERIF: font += 4; break;
    case FG_MONO: font += 8; break;
    case FG_SYMBOL:
        if ((fontID & 0x0fff) == (FID_PS_SYMBOL & 0x0fff)) font = PDF_FONT_SYMBOL;
        else if ((fontID & 0x0fff) == 0x0801 || (fontID & 0x0fff) == 0x0802)
            font = PDF_FONT_DINGBATS;
        else if (visible) { p->error = PDF_UNSUPPORTED; return 0; }
        break;
    }
    if (visible) PdfColor(p, GrGetTextColor(gs), 0);
    /* Only one- and two-character native width queries are needed. The pair
     * difference includes incoming pair kerning without remeasuring prefixes.
     * Widths retain native space padding, track kerning and 1/256 fractions. */
    for (i = 0; i < count && s[i] && !p->error; ++i) {
        glyph = s[i];
        if (glyph == C_OPTHYPHEN) {
            /* A one-character width query would mistake an internal soft
             * hyphen for the end of the run. Hidden ones have no advance. */
            if (!(mode & TM_DRAW_OPTIONAL_HYPHENS) ||
                (i + 1 < count && s[i+1])) {
                previous = 0; continue;
            }
            glyph = '-';
        }
        width = (PdfFixed)PDFTEXTWIDTHFIXED(gs, (const char *)(s+i), 1);
        if (width < 0) { p->error = PDF_LIMIT_ERROR; break; }
        kern = 0;
        if (i) {
            pair[0] = s[i-1]; pair[1] = s[i];
            kern = (PdfFixed)PDFTEXTWIDTHFIXED(gs, (const char *)pair, 2);
            if (kern < 0) { p->error = PDF_LIMIT_ERROR; break; }
            if (!addFixed(p, kern, -previous, &kern) ||
                !addFixed(p, kern, -width, &kern)) break;
        }
        if (!addFixed(p, advance, kern, &advance) ||
            !addFixed(p, x, advance, &origin)) break;
        if (visible) {
            glyphFont = textCharacter(glyph, &encoded, font);
            if (glyphFont == 0xffff) { p->error = PDF_UNSUPPORTED; break; }
            /* VidCom KernChar applies track kerning before painting, including
             * the first glyph. Single width minus bare glyph width also keeps
             * GEOS space padding at the same side of the space character. */
            offset = (PdfFixed)GrCharWidth(gs, glyph);
            if (offset < 0) { p->error = PDF_LIMIT_ERROR; break; }
            if (!addFixed(p, width, -offset, &offset) ||
                !addFixed(p, origin, offset, &origin)) break;
            PdfText(p, origin, y, (PdfFixed)size, glyphFont, &encoded, 1);
        }
        if (!addFixed(p, advance, width, &advance)) break;
        previous = width;
    }
    if (visible && !p->error && advance > 0 &&
        (style & (TS_UNDERLINE | TS_STRIKE_THRU))) {
        if (!addFixed(p, x, advance, &origin)) return advance;
        /* GDFS_limit caps decoration only; the text pen keeps its advance. */
        if (limit != 0xffff && origin > (PdfFixed)limit * 65536L)
            origin = (PdfFixed)limit * 65536L;
        if (origin > x) {
            thickness = (PdfFixed)GrFontMetrics(gs, GFMI_UNDER_THICKNESS);
            fontBase = (PdfFixed)GrFontMetrics(gs, GFMI_BASELINE);
            if (thickness < 0 || fontBase < 0) {
                p->error = PDF_LIMIT_ERROR; return advance;
            }
            /* Native DrawOneBar uses the same thickness for both styles,
             * with positions relative to the top of the font, not baseline. */
            for (i = TS_UNDERLINE; i <= TS_STRIKE_THRU && !p->error; i <<= 1) {
                if ((style & i) && thickness) {
                    offset = (PdfFixed)GrFontMetrics(gs,
                        i == TS_UNDERLINE ? GFMI_UNDER_POS : GFMI_STRIKE_POS);
                    if (!addFixed(p, offset, -fontBase, &offset) ||
                        !addFixed(p, y, offset, &offset)) break;
                    PdfNumber(p, x); PdfNumber(p, offset);
                    PdfNumber(p, origin - x); PdfNumber(p, thickness);
                    PdfRaw(p, "re f\n");
                }
            }
        }
    }
    return advance;
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
/* ESP TextAttr ends with word alignment; packed C TextAttr has no padding. */
typedef struct { word count; TextAttr attr; byte padding; } PdfTextRun;
#pragma pack()
static void textField(PdfDocument *p, GStateHandle gs, const byte *b, word size)
{
    const PdfTextField *f;
    const PdfTextRun *r;
    word left, pos, n;
    PdfFixed x, y, advance;
    if (size < 1 + sizeof(PdfTextField)) { p->error = PDF_STATE_ERROR; return; }
    f = (const PdfTextField *)(b + 1);
    left = f->count;
    x = (PdfFixed)f->x.WBF_int * 65536L + (word)f->x.WBF_frac * 256L;
    y = (PdfFixed)f->y.WBF_int * 65536L + (word)f->y.WBF_frac * 256L;
    advance = (PdfFixed)f->baseline.WBF_int * 65536L + (word)f->baseline.WBF_frac * 256L;
    if (!addFixed(p, y, advance, &y)) return;
    pos = 1 + sizeof(PdfTextField);
    while (left && !p->error) {
        if (pos > size || (word)(size - pos) < (word)sizeof(PdfTextRun)) { p->error = PDF_STATE_ERROR; break; }
        r = (const PdfTextRun *)(b + pos); n = r->count;
        pos += sizeof(PdfTextRun);
        if (!n || n > left || n > size - pos) { p->error = PDF_STATE_ERROR; break; }
        GrSetTextAttr(gs, &r->attr);
        advance = text(p, gs, x, y, b + pos, n, TRUE, f->limit);
        if (!addFixed(p, x, advance, &x)) break;
        left -= n; pos += n;
    }
    /* HF_AUTO_HYPHEN is the only defined flag. GrDrawTextField draws the
     * extra hyphen separately, using the last run's attributes and limit. */
    if (!p->error && (f->flags & 0x01))
        text(p, gs, x, y, (const byte *)"-", 1, TRUE, f->limit);
}
static PdfFixed _pascal operandFixed(const byte *b)
{
    return (PdfFixed)((dword)u16(b) | (dword)u16(b+2) << 16);
}
static void _pascal fixedPoint(PdfDocument *p, PdfFixed x, PdfFixed y, const char *op)
{
    PdfNumber(p, x); PdfNumber(p, y); PdfRaw(p, op);
}
/* Validate captured geometry before kernel playback as well as at painting.
 * A path may be defined without ever being painted. */
static word _pascal geometrySize(const byte *b, word size)
{
    word expected = 0, header, count;
    if (!size) return PDF_STATE_ERROR;
    switch (b[0]) {
    case GR_DRAW_LINE: case GR_DRAW_RECT: case GR_FILL_RECT:
    case GR_DRAW_ELLIPSE: case GR_FILL_ELLIPSE:
    case GR_DRAW_REL_LINE_TO: expected = 9; break;
    case GR_DRAW_LINE_TO: case GR_DRAW_RECT_TO: case GR_FILL_RECT_TO:
        expected = 5; break;
    case GR_DRAW_HLINE: case GR_DRAW_VLINE:
    case GR_DRAW_ROUND_RECT_TO: case GR_FILL_ROUND_RECT_TO: expected = 7; break;
    case GR_DRAW_HLINE_TO: case GR_DRAW_VLINE_TO: expected = 3; break;
    case GR_DRAW_ROUND_RECT: case GR_FILL_ROUND_RECT: expected = 11; break;
    case GR_DRAW_CURVE: expected = 17; break;
    case GR_DRAW_CURVE_TO: expected = 13; break;
    case GR_DRAW_REL_CURVE_TO: expected = 25; break;
    case GR_DRAW_POLYLINE: case GR_DRAW_POLYGON: case GR_FILL_POLYGON:
    case GR_DRAW_SPLINE: case GR_DRAW_SPLINE_TO:
        header = b[0] == GR_FILL_POLYGON ? 4 : 3;
        if (size < header) return PDF_STATE_ERROR;
        count = u16(b+1);
        if (!count || count > (size-header)/4 || size-header != count*4 ||
            (header == 4 && b[3] > 1)) return PDF_STATE_ERROR;
        if (b[0] == GR_DRAW_SPLINE && (count < 4 || (count-1)%3)) return PDF_STATE_ERROR;
        if (b[0] == GR_DRAW_SPLINE_TO && (count < 3 || count%3)) return PDF_STATE_ERROR;
        return PDF_OK;
    default: return PDF_UNSUPPORTED;
    }
    return size == expected ? PDF_OK : PDF_STATE_ERROR;
}
static void output(PdfDocument *p, GStateHandle gs, const byte *b, word size, Boolean path)
{
    word op = b[0], n, pos, i;
    PointWWFixed textPen;
    XYValueAsDWord cp = GrGetCurPos(gs);
    int x = (sword)(word)cp, y = (sword)(word)(cp >> 16);
    int x2, y2;
    PdfFixed fx, fy, baseX, baseY;
    Boolean fill = op == GR_FILL_RECT || op == GR_FILL_RECT_TO ||
                   op == GR_FILL_POLYGON || op == GR_FILL_ELLIPSE ||
                   op == GR_FILL_ROUND_RECT || op == GR_FILL_ROUND_RECT_TO;
    if (!path) {
        PdfRaw(p, "q\n");
        clipPaths(p, gs);
        if (op == GR_DRAW_PATH || op == GR_FILL_PATH) {
            if (size != (op == GR_DRAW_PATH ? 1 : 2) ||
                (op == GR_FILL_PATH && b[1] > 1)) goto bad;
            nativePath(p, gs, GPT_CURRENT, op == GR_DRAW_PATH ? -1 : b[1]);
            PdfRaw(p, "Q\n"); return;
        }
        attributes(p, gs, fill, op >= GR_DRAW_CHAR && op <= GR_DRAW_TEXT_FIELD);
    }
    switch (op) {
    case GR_REL_MOVE_TO: case GR_MOVE_TO_WWFIXED: case GR_DRAW_REL_LINE_TO:
        if (size != 9) goto bad;
        GrGetCurPosWWFixed(gs, &textPen);
        baseX = fixed(textPen.PF_x); baseY = fixed(textPen.PF_y);
        fx = operandFixed(b+1); fy = operandFixed(b+5);
        if (op != GR_MOVE_TO_WWFIXED &&
            (!addFixed(p, baseX, fx, &fx) || !addFixed(p, baseY, fy, &fy))) break;
        if (op == GR_DRAW_REL_LINE_TO && !path) fixedPoint(p, baseX, baseY, "m ");
        fixedPoint(p, fx, fy, op == GR_DRAW_REL_LINE_TO ? (path ? "l\n" : "l S\n") : "m\n");
        break;
    case GR_DRAW_REL_CURVE_TO:
        if (size != 25) goto bad;
        GrGetCurPosWWFixed(gs, &textPen);
        baseX = fixed(textPen.PF_x); baseY = fixed(textPen.PF_y);
        if (!path) fixedPoint(p, baseX, baseY, "m ");
        for (i = 0; i < 3; ++i) {
            if (!addFixed(p, baseX, operandFixed(b+1+i*8), &fx) ||
                !addFixed(p, baseY, operandFixed(b+5+i*8), &fy)) break;
            fixedPoint(p, fx, fy, "");
        }
        PdfRaw(p, path ? "c\n" : "c S\n"); break;
    case GR_DRAW_SPLINE: case GR_DRAW_SPLINE_TO:
        if (geometrySize(b, size)) goto bad;
        n = u16(b+1); pos = 3;
        if (op == GR_DRAW_SPLINE) {
            point(p, s16(b+pos), s16(b+pos+2), "m "); pos += 4; --n;
        } else if (!path) point(p, x, y, "m ");
        for (i = 0; i < n; ++i, pos += 4) {
            point(p, s16(b+pos), s16(b+pos+2), "");
            if (i%3 == 2) PdfRaw(p, "c\n");
        }
        if (!path) PdfRaw(p, "S\n");
        break;
    case GR_MOVE_TO:
        if (!path || size != 5) goto bad;
        point(p, s16(b+1), s16(b+3), "m\n"); break;
    case GR_CLOSE_SUB_PATH:
        if (!path || size != 1) goto bad;
        PdfRaw(p, "h\n"); break;
    case GR_DRAW_LINE:
        if (size != 9) goto bad;
        point(p, s16(b+1), s16(b+3), "m "); point(p, s16(b+5), s16(b+7), path ? "l\n" : "l S\n"); break;
    case GR_DRAW_LINE_TO:
        if (size != 5) goto bad;
        if (!path) point(p, x, y, "m ");
        point(p, s16(b+1), s16(b+3), path ? "l\n" : "l S\n"); break;
    case GR_DRAW_HLINE: case GR_DRAW_VLINE:
        if (size != 7) goto bad;
        x = s16(b+1); y = s16(b+3); x2 = x; y2 = y;
        if (op == GR_DRAW_HLINE) x2 = s16(b+5); else y2 = s16(b+5);
        point(p, x, y, "m "); point(p, x2, y2, path ? "l\n" : "l S\n"); break;
    case GR_DRAW_HLINE_TO: case GR_DRAW_VLINE_TO:
        if (size != 3) goto bad;
        x2 = x; y2 = y;
        if (op == GR_DRAW_HLINE_TO) x2 = s16(b+1); else y2 = s16(b+1);
        if (!path) point(p, x, y, "m ");
        point(p, x2, y2, path ? "l\n" : "l S\n"); break;
    case GR_DRAW_RECT: case GR_FILL_RECT:
        if (size != 9) goto bad;
        x = s16(b+1); y = s16(b+3); b += 4;
        /* FALLTHROUGH */
    case GR_DRAW_RECT_TO: case GR_FILL_RECT_TO:
        if ((op == GR_DRAW_RECT_TO || op == GR_FILL_RECT_TO) && size != 5) goto bad;
        x2 = s16(b+1); y2 = s16(b+3);
        PdfInteger(p, x); PdfInteger(p, y);
        PdfInteger(p, (long)x2 - x); PdfInteger(p, (long)y2 - y);
        PdfRaw(p, path ? "re\n" : (fill ? "re f\n" : "re S\n")); break;
    case GR_DRAW_ROUND_RECT: case GR_FILL_ROUND_RECT:
        if (size != 11) goto bad;
        PdfRoundRect(p, s16(b+3), s16(b+5), s16(b+7), s16(b+9), u16(b+1), path ? -1 : fill);
        break;
    case GR_DRAW_ROUND_RECT_TO: case GR_FILL_ROUND_RECT_TO:
        if (size != 7) goto bad;
        PdfRoundRect(p, x, y, s16(b+3), s16(b+5), u16(b+1), path ? -1 : fill);
        break;
    case GR_DRAW_ELLIPSE: case GR_FILL_ELLIPSE:
        if (size != 9) goto bad;
        PdfEllipse(p, s16(b+1), s16(b+3), s16(b+5), s16(b+7), path ? -1 : fill);
        break;
    case GR_DRAW_CURVE: case GR_DRAW_CURVE_TO:
        pos = 1;
        if (op == GR_DRAW_CURVE) {
            if (size != 17) goto bad;
            x = s16(b+1); y = s16(b+3); pos = 5;
        } else if (size != 13) goto bad;
        if (!path || op == GR_DRAW_CURVE) point(p, x, y, "m ");
        for (i = 0; i < 3; ++i, pos += 4) point(p, s16(b+pos), s16(b+pos+2), "");
        PdfRaw(p, path ? "c\n" : "c S\n"); break;
    case GR_DRAW_POLYLINE: case GR_DRAW_POLYGON: case GR_FILL_POLYGON:
        if (size < (fill ? 4 : 3)) goto bad;
        n = u16(b+1); pos = fill ? 4 : 3;
        if (!n || n > (size - pos) / 4 || size - pos != n * 4) goto bad;
        for (i = 0; i < n; ++i, pos += 4)
            point(p, s16(b+pos), s16(b+pos+2), i ? "l " : "m ");
        if (fill && b[3] > 1) goto bad;
        if (path) PdfRaw(p, op == GR_DRAW_POLYLINE ? "\n" : "h\n");
        else PdfRaw(p, fill ? (b[3] ? "h f\n" : "h f*\n") :
                             (op == GR_DRAW_POLYGON ? "h S\n" : "S\n")); break;
    case GR_DRAW_TEXT:
        if (path) { p->error = PDF_UNSUPPORTED; break; }
        if (size < 7 || u16(b+5) != size - 7) goto bad;
        text(p, gs, (PdfFixed)s16(b+1)*65536L, (PdfFixed)s16(b+3)*65536L, b+7, u16(b+5), FALSE, 0xffff); break;
    case GR_DRAW_TEXT_CP:
        if (path) { p->error = PDF_UNSUPPORTED; break; }
        if (size < 3 || u16(b+1) != size - 3) goto bad;
        GrGetCurPosWWFixed(gs, &textPen);
        text(p, gs, fixed(textPen.PF_x), fixed(textPen.PF_y), b+3, u16(b+1), FALSE, 0xffff); break;
    case GR_DRAW_CHAR:
        if (path) { p->error = PDF_UNSUPPORTED; break; }
        if (size != 6) goto bad;
        text(p, gs, (PdfFixed)s16(b+2)*65536L, (PdfFixed)s16(b+4)*65536L, b+1, 1, FALSE, 0xffff); break;
    case GR_DRAW_CHAR_CP:
        if (path) { p->error = PDF_UNSUPPORTED; break; }
        if (size != 2) goto bad;
        GrGetCurPosWWFixed(gs, &textPen);
        text(p, gs, fixed(textPen.PF_x), fixed(textPen.PF_y), b+1, 1, FALSE, 0xffff); break;
    case GR_DRAW_TEXT_FIELD:
        if (path) { p->error = PDF_UNSUPPORTED; break; }
        textField(p, gs, b, size); break;
    default:
        p->error = PDF_UNSUPPORTED;
    }
    if (!path) PdfRaw(p, "Q\nQ\n");
    return;
bad:
    p->error = PDF_STATE_ERROR;
}

/***********************************************************************
 *
 * FUNCTION:    nativePath
 * DESCRIPTION: Serialize a copied native path. The kernel owns the live path;
 *              this routine owns only the snapshot and one current element.
 * PARAMETERS:  paint = -1 stroke, 0/1 fill rule, 2 clipping.
 * STRATEGY:    GrGetPath returns transformed GString sections. Replay their
 *              transforms/pen in a separate null-window state, but skip the
 *              path delimiters so geometry is emitted without recapturing it.
 *
 ***********************************************************************/
static void _pascal nativePath(PdfDocument *p, GStateHandle gs, word type, int paint)
{
    MemHandle pathH = 0, elementH = 0;
    GStateHandle source = 0, playback = 0;
    byte *pathP, *elementP;
    TransMatrix transform;
    PdfFixed values[6], previousMatrix[6];
    PointWWFixed subStart, pen;
    word op, size, result, last, i, rule = 0, sections = 0;
    Boolean open = FALSE, complete = FALSE, more, to, changed;
    Boolean subpath = FALSE, matrixKnown = FALSE;

    if (p->error || !GrTestPath(gs, type)) return;
    pathH = GrGetPath(gs, type);
    if (!pathH) { p->error = PDF_LIMIT_ERROR; return; }
    pathP = MemLock(pathH);
    source = GrLoadGString(PtrToSegment(pathP), GST_PTR, PtrToOffset(pathP));
    if (!source) { p->error = PDF_LIMIT_ERROR; goto cleanup; }
    playback = GrCreateState(0);
    if (!playback) { p->error = PDF_LIMIT_ERROR; goto cleanup; }
    PdfRaw(p, "n\n");
    result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
    if (result != GSRT_ONE && result != GSRT_COMPLETE) p->error = PDF_STATE_ERROR;
    while (!p->error && result != GSRT_COMPLETE) {
        op = GrGetGStringElement(playback, source, 0, (void*)0, &size);
        if (!size || size > 32760) {
            p->error = size ? PDF_LIMIT_ERROR : PDF_STATE_ERROR; break;
        }
        if (op == GR_END_GSTRING) { complete = TRUE; break; }
        elementH = MemAlloc(size, HF_DYNAMIC, HAF_ZERO_INIT | HAF_LOCK);
        if (!elementH) { p->error = PDF_LIMIT_ERROR; break; }
        elementP = MemDeref(elementH);
        GrGetGStringElement(playback, source, size, elementP, &size);
        if (op == GR_BEGIN_PATH) {
            if (open || size != 5 || u16(elementP+1) > PCT_INTERSECTION) {
                p->error = PDF_STATE_ERROR;
            } else {
                /* Intersection sections become successive PDF clip paths.
                 * ATTENTION: Boolean unions need native region conversion;
                 * retain an explicit failure until that converter is added. */
                if (sections && paint != -1 && (elementP[3] & 3) != PCT_INTERSECTION)
                    p->error = PDF_UNSUPPORTED;
                rule = (elementP[3] & 0x10) ? !!(elementP[3] & 0x20) : (paint == 1);
                ++sections; open = TRUE;
                GrSaveState(playback);
            }
            GrSetGStringPos(source, GSSPT_SKIP_1, 0);
        } else if (op == GR_END_PATH) {
            if (!open || size != 1) { p->error = PDF_STATE_ERROR; break; }
            GrRestoreState(playback);
            open = FALSE;
            GrSetGStringPos(source, GSSPT_SKIP_1, 0);
            op = GrGetGStringElement(playback, source, 0, (void*)0, &size);
            more = op != GR_END_GSTRING;
            if (paint == 2 || (paint >= 0 && more))
                PdfRaw(p, rule ? "W n\n" : "W* n\n");
            /* GrGetPath changed each saved SetTransform to ApplyTransform.
             * Each section's saved matrix is absolute, not cumulative. */
            GrSetNullTransform(playback);
            subpath = matrixKnown = FALSE;
        } else if ((op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F) ||
                   op == GR_MOVE_TO || op == GR_CLOSE_SUB_PATH ||
                   op == GR_REL_MOVE_TO || op == GR_MOVE_TO_WWFIXED) {
            GrGetTransform(playback, &transform);
            if (matrix(p, &transform, values)) {
                PdfRaw(p, "q\n");
                for (i = 0; i < 6; ++i) PdfNumber(p, values[i]);
                PdfRaw(p, "cm\n");
                changed = !matrixKnown;
                for (i = 0; i < 6; ++i) {
                    if (matrixKnown && values[i] != previousMatrix[i]) changed = TRUE;
                    previousMatrix[i] = values[i];
                }
                matrixKnown = TRUE;
                to = op == GR_DRAW_LINE_TO || op == GR_DRAW_HLINE_TO ||
                     op == GR_DRAW_VLINE_TO || op == GR_DRAW_REL_LINE_TO ||
                     op == GR_DRAW_CURVE_TO || op == GR_DRAW_REL_CURVE_TO ||
                     op == GR_DRAW_SPLINE_TO;
                if (to && (!subpath || changed)) {
                    GrGetCurPosWWFixed(playback, &subStart);
                    fixedPoint(p, fixed(subStart.PF_x), fixed(subStart.PF_y), "m\n");
                    subpath = TRUE;
                }
                output(p, playback, elementP, size, TRUE);
                if (op == GR_CLOSE_SUB_PATH && subpath)
                    GrMoveToWWFixed(playback, fixed(subStart.PF_x), fixed(subStart.PF_y));
                else if (op == GR_DRAW_LINE || op == GR_DRAW_CURVE ||
                         op == GR_DRAW_POLYLINE || op == GR_DRAW_SPLINE) {
                    i = op == GR_DRAW_POLYLINE || op == GR_DRAW_SPLINE ? 3 : 1;
                    subStart.PF_x.WWF_int = s16(elementP+i); subStart.PF_x.WWF_frac = 0;
                    subStart.PF_y.WWF_int = s16(elementP+i+2); subStart.PF_y.WWF_frac = 0;
                    subpath = TRUE;
                } else if (op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F && !to)
                    subpath = FALSE;
                PdfRaw(p, "Q\n");
            }
            result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
            if (op == GR_MOVE_TO || op == GR_REL_MOVE_TO || op == GR_MOVE_TO_WWFIXED) {
                GrGetCurPosWWFixed(playback, &pen); subStart = pen; subpath = TRUE;
            }
        } else if (op >= GR_APPLY_ROTATION && op <= GR_RESTORE_TRANSFORM) {
            result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
        } else p->error = PDF_UNSUPPORTED;
        MemFree(elementH); elementH = 0;
        if (result != GSRT_ONE && result != GSRT_COMPLETE) p->error = PDF_STATE_ERROR;
    }
    if (result == GSRT_COMPLETE) complete = TRUE;
    if ((!complete || open || !sections) && !p->error) p->error = PDF_STATE_ERROR;
    if (!p->error && paint != 2) {
        /* The path is already in page coordinates. Apply the painting matrix
         * only now, so it affects stroke width without moving the path again. */
        attributes(p, gs, paint >= 0, FALSE);
        PdfRaw(p, paint < 0 ? "S\n" : (rule ? "f\n" : "f*\n"));
        PdfRaw(p, "Q\n");
    }
cleanup:
    if (elementH) MemFree(elementH);
    if (playback) GrDestroyState(playback);
    if (source) GrDestroyGString(source, 0, GSKT_LEAVE_DATA);
    if (pathH) MemFree(pathH);
}

/* A bitmap is one logical output element with zero or more follow-on slices.
 * Kernel bitmap playback consumes those slices via a callback, so we must
 * advance them explicitly instead of calling GrDrawGStringAtCP on the bitmap.
 * Only the serialized slice is retained; no image or extra scanline buffer. */
static void bitmap(PdfDocument *p, GStateHandle gs, GStateHandle string, byte op)
{
    PdfBitmapSlice s, first;
    PdfBitmapReader reader;
    PdfImage image;
    TransMatrix t;
    PdfFixed m[6], width, height;
    MemHandle block = 0;
    byte *b;
    const byte *row;
    word size, prefix, i, error, rowBytes;
    XYValueAsDWord cp = GrGetCurPos(gs);
    int x = (sword)(word)cp, y = (sword)(word)(cp >> 16);
    Boolean initial = TRUE, fill = op == GR_FILL_BITMAP || op == GR_FILL_BITMAP_CP;
    if (GrGetMixMode(gs) != MM_COPY || GrGetAreaMask(gs, (DrawMask *)0) != SDM_100) {
        p->error = PDF_UNSUPPORTED; return;
    }
    while (!p->error) {
        GrGetGStringElement(gs, string, 0, (void *)0, &size);
        if (!size) { p->error = PDF_STATE_ERROR; break; }
        if (size > 32760) { p->error = PDF_LIMIT_ERROR; break; }
        block = MemAlloc(size, HF_DYNAMIC, HAF_LOCK);
        if (!block) { p->error = PDF_LIMIT_ERROR; break; }
        b = MemDeref(block);
        GrGetGStringElement(gs, string, size, b, &size);
        prefix = initial && (op == GR_DRAW_BITMAP || op == GR_FILL_BITMAP) ? 7 : 3;
        if (size < prefix || b[0] != (initial ? op : GSE_BITMAP_SLICE) ||
            u16(b + prefix - 2) != size - prefix) { p->error = PDF_STATE_ERROR; break; }
        error = PdfBitmapReaderOpen(&reader, b + prefix, (word)(size - prefix));
        if (error) { p->error = error; break; }
        s = reader.slice;
        if (initial) {
            if (s.firstRow) { p->error = PDF_STATE_ERROR; break; }
            if (fill && s.image.format != PDF_IMAGE_STENCIL1) { p->error = PDF_UNSUPPORTED; break; }
            first = s;
            if (prefix == 7) { x = s16(b+1); y = s16(b+3); }
            error = PdfBitmapExtent(s.image.width, s.xDpi, &width);
            if (!error) error = PdfBitmapExtent(s.image.height, s.yDpi, &height);
            if (error) { p->error = error; break; }
            GrGetTransform(gs, &t);
            if (!matrix(p, &t, m)) break;
            PdfRaw(p, "q\n");
            clipPaths(p, gs);
            for (i = 0; i < 6; ++i) PdfNumber(p, m[i]);
            PdfRaw(p, "cm\n");
            /* GEOS DrawBitmap's mono foreground is black; FillBitmap uses
             * area color. In both cases zero source bits remain transparent. */
            if (s.image.format == PDF_IMAGE_STENCIL1)
                PdfColor(p, fill ? GrGetAreaColor(gs) : 0, 0);
            PdfImageBegin(p, &image, &s.image, x, y, width, height);
            if (prefix == 7) GrMoveTo(gs, x, y);
        } else if (!s.complex || !s.rows || s.firstRow != image.rows ||
                   s.image.width != first.image.width || s.image.height != first.image.height ||
                   s.image.format != first.image.format || s.xDpi != first.xDpi || s.yDpi != first.yDpi) {
            p->error = PDF_STATE_ERROR; break;
        }
        for (i = 0; i < s.rows && !p->error; ++i) {
            error = PdfBitmapNextRow(&reader, &row, &rowBytes);
            if (error) p->error = error;
            else PdfImageRow(p, &image, row, rowBytes);
        }
        MemFree(block); block = 0;
        if (p->error) break;
        GrSetGStringPos(string, GSSPT_SKIP_1, 0);
        if (image.rows == image.spec.height) {
            PdfImageEnd(p, &image); PdfRaw(p, "Q\n"); break;
        }
        if (!first.complex) { p->error = PDF_STATE_ERROR; break; }
        initial = FALSE;
    }
    if (block) MemFree(block);
}
word _pascal _export PDFGSTRING(MemHandle h, GStateHandle string, word flags)
{
    PdfDocument *p = MemLock(h);
    GStateHandle gs = GrCreateState(0);
    MemHandle element = 0;
    byte *b;
    word size, last, result = GSRT_FAULT, depth = 0, n;
    Boolean definingPath = FALSE;
    byte pattern[3], control[15];
    byte op = 0;
    (void)flags; /* PDL contract always ends at a physical page boundary. */
    if (!p->inPage || !p->transformed) p->error = PDF_STATE_ERROR;
    PdfRaw(p, "q\n");
    /* Prime playback before extracting an element: establishes the kernel's
     * default transform at origin, including when the first output is a bitmap.
     * No element is ready yet, so GSC_ONE stops BEFORE the first operation. */
    result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
    if (result != GSRT_ONE && result != GSRT_COMPLETE) p->error = PDF_STATE_ERROR;
    while (!p->error && result != GSRT_COMPLETE) {
        op = GrGetGStringElement(gs, string, 0, (void *)0, &size);
        if (!size) { p->error = PDF_STATE_ERROR; break; }
        if (op == GR_END_GSTRING || op == GR_NEW_PAGE) {
            if (op == GR_NEW_PAGE) GrSetGStringPos(string, GSSPT_SKIP_1, 0);
            result = op == GR_NEW_PAGE ? GSRT_NEW_PAGE : GSRT_COMPLETE; break;
        }
        if (op == GR_DRAW_BITMAP || op == GR_DRAW_BITMAP_CP ||
            op == GR_FILL_BITMAP || op == GR_FILL_BITMAP_CP) {
            if (definingPath) { p->error = PDF_UNSUPPORTED; break; }
            bitmap(p, gs, string, op);
            continue;
        }
        if (op == GR_SAVE_STATE) {
            if (depth == 31) { p->error = PDF_LIMIT_ERROR; break; }
            ++depth; PdfRaw(p, "q\n");
        } else if (op == GR_RESTORE_STATE) {
            if (!depth) { p->error = PDF_STATE_ERROR; break; }
            --depth; PdfRaw(p, "Q\n");
        } else if (op == GR_BEGIN_PATH) {
            if (definingPath || size != 5) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+1) > PCT_INTERSECTION) { p->error = PDF_STATE_ERROR; break; }
            definingPath = u16(control+1) != PCT_NULL;
        } else if (op == GR_END_PATH) {
            if (size != 1) { p->error = PDF_STATE_ERROR; break; }
            definingPath = FALSE;
        } else if (op == GR_CLOSE_SUB_PATH) {
            if (!definingPath || size != 1) { p->error = PDF_STATE_ERROR; break; }
        } else if (op == GR_SET_CLIP_RECT || op == GR_SET_WIN_CLIP_RECT) {
            if (definingPath || size != 11) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+1) > PCT_INTERSECTION) { p->error = PDF_STATE_ERROR; break; }
        } else if (op == GR_SET_CLIP_PATH || op == GR_SET_WIN_CLIP_PATH) {
            if (definingPath || size != 4) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+2) > PCT_INTERSECTION ||
                (u16(control+2) != PCT_NULL && control[1] > 1)) {
                p->error = PDF_STATE_ERROR; break;
            }
        } else if (op == GR_SET_LINE_STYLE) {
            if (size != 3) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, control, &size);
            if (control[1] > LS_DASHDDOT || control[2] > 127 ||
                (control[1] != LS_SOLID && control[2] >
                    (control[1] == LS_DOTTED ? 3 : 8))) {
                p->error = PDF_STATE_ERROR; break;
            }
        } else if (op == GR_SET_CUSTOM_LINE_STYLE) {
            if (size < 7 || size > sizeof(control)) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, control, &size);
            n = u16(control+3);
            if (!n || n > 5 || size != 5 + n * 2 || u16(control+1) > 127 ||
                u16(control+1) > (byte)(control[5] + control[6])) {
                p->error = PDF_STATE_ERROR; break;
            }
            for (n = 5; n < size; ++n) if (!control[n]) p->error = PDF_STATE_ERROR;
            if (p->error) break;
        } else if (op == GR_SET_AREA_PATTERN || op == GR_SET_TEXT_PATTERN) {
            if (size != sizeof(pattern)) { p->error = PDF_STATE_ERROR; break; }
            GrGetGStringElement(gs, string, size, pattern, &size);
            /* PT_SOLID ignores the data byte; playback maintains the GState. */
            if (pattern[1] != PT_SOLID) { p->error = PDF_UNSUPPORTED; break; }
        } else if (op >= GR_BEGIN_PATH || op == GR_ESCAPE ||
                   op == GR_SET_CUSTOM_AREA_PATTERN ||
                   op == GR_SET_CUSTOM_TEXT_PATTERN) {
            p->error = PDF_UNSUPPORTED; break;
        }
        if (op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F) {
            if (size > 32760) { p->error = PDF_LIMIT_ERROR; break; }
            element = MemAlloc(size, HF_DYNAMIC, HAF_LOCK);
            if (!element) { p->error = PDF_LIMIT_ERROR; break; }
            b = MemDeref(element);
            GrGetGStringElement(gs, string, size, b, &size);
            if (definingPath) p->error = geometrySize(b, size);
            else output(p, gs, b, size, FALSE);
            /* Keep a rejected record alive for the EC warning below. */
            if (p->error) break;
            MemFree(element); element = 0;
        }
        result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
        if (result != GSRT_ONE && result != GSRT_COMPLETE) { p->error = PDF_STATE_ERROR; break; }
        /* COMPLETE restores the kernel transform and rewinds the source.
         * Stop here; another extraction would repeat the document forever. */
    }
    if ((depth || definingPath) && !p->error) p->error = PDF_STATE_ERROR;
    PdfRaw(p, "Q\n");
    if (p->error) {
#ifndef PDF_HOST_TEST
        EC_WARNING(0x5044); /* PDF translation failed; inspect op and p->error. */
#endif
        result = GSRT_FAULT;
    }
    if (element) MemFree(element);
    /* An unfinished definition still owns a kernel path GString. GrEndPath
     * releases it and restores the saved GState before GrDestroyState. */
    if (definingPath) GrEndPath(gs);
    GrDestroyState(gs); MemUnlock(h); return result;
}
