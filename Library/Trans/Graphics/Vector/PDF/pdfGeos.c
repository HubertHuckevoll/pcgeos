/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfGeos.c

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    PDFCREATE       - Create a PDF job context
    PDFSTARTPAGE    - Begin a physical page
    PDFSETTRANSFORM - Set the page transformation
    PDFGSTRING      - Translate a GEOS graphics string
    PDFENDPAGE      - Close the current page
    PDFDESTROY      - Finish and release the job

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Translate GEOS GString records into PDF drawing operations.
    Use the kernel to maintain the graphics state and transforms.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

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
#include <lmem.h>
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
extern word _pascal PDFGENCHAR(GStateHandle gs, word character);
extern sdword _pascal PDFSCRIPTY(GStateHandle gs);
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

/* Convert the GEOS transform once; reject coefficients outside PDF 16.16. */
static Boolean matrix(PdfDocument *p, const TransMatrix *t, PdfFixed *m)
{
    /* The first milestone uses 16.16 PDF operands. Detect, do not wrap,
     * the kernel's wider 32.16 translation values. */
    if (t->TM_e31.DWF_int < -32768L || t->TM_e31.DWF_int > 32767L ||
        t->TM_e32.DWF_int < -32768L || t->TM_e32.DWF_int > 32767L) {
            p->error = PDF_LIMIT_ERROR;
        return FALSE;
    }

    m[0] = fixed(t->TM_e11);
    m[1] = fixed(t->TM_e12);
    m[2] = fixed(t->TM_e21);
    m[3] = fixed(t->TM_e22);
    m[4] = (PdfFixed)((dword)t->TM_e31.DWF_int << 16 | t->TM_e31.DWF_frac);
    m[5] = (PdfFixed)((dword)t->TM_e32.DWF_int << 16 | t->TM_e32.DWF_frac);
    return TRUE;
}

/***********************************************************************
 *
 * FUNCTION:    PDFCREATE
 *
 * DESCRIPTION: Create the per-job PDF document context.
 *
 * PARAMETERS:  token/strategy = spooler stream; width/height = page size.
 *
 * STRATEGY:    Allocate a movable per-job context and write the PDF header.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Release the context if output fails.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

MemHandle _pascal _export PDFCREATE(word token, void (*strategy)(void), word width, word height)
{
    MemHandle h;
    PdfDocument *p;

    h = MemAlloc(sizeof(PdfDocument), HF_DYNAMIC, HAF_ZERO_INIT | HAF_LOCK);
    if (!h) {
        return 0;
    }
    p = MemDeref(h);
    p->token = token;
    p->strategy = strategy;
    p->width = width;
    p->height = height;
    PdfBegin(p);
    PdfFlush(p);
    if (p->error) {
        MemFree(h);
        return 0;
    }

    MemUnlock(h);
    return h;
}

/***********************************************************************
 *
 * FUNCTION:    PDFSTARTPAGE
 *
 * DESCRIPTION: Begin a physical PDF page.
 *
 * PARAMETERS:  h = context handle.
 *
 * STRATEGY:    Begin the page and return any writer error.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              The caller retains the handle.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

word _pascal _export PDFSTARTPAGE(MemHandle h)
{
    PdfDocument *p = MemLock(h);
    word error;
    PdfBeginPage(p);

    error = p->error;
    MemUnlock(h);
    return error;
}

/***********************************************************************
 *
 * FUNCTION:    PDFSETTRANSFORM
 *
 * DESCRIPTION: Store the spooler page matrix.
 *
 * PARAMETERS:  h = context; t = GEOS page matrix.
 *
 * STRATEGY:    Convert and validate the 16.16 PDF matrix.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Reject translations outside the supported range.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

word _pascal _export PDFSETTRANSFORM(MemHandle h, const TransMatrix *t)
{
    PdfDocument *p = MemLock(h);
    PdfFixed m[6];
    word error;

    if (matrix(p, t, m)) {
        PdfPageMatrix(p, m);
    }
    error = p->error;
    MemUnlock(h);
    return error;
}

/***********************************************************************
 *
 * FUNCTION:    PDFENDPAGE
 *
 * DESCRIPTION: Finish one physical PDF page.
 *
 * PARAMETERS:  h = context handle.
 *
 * STRATEGY:    Close the current page.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              The caller retains the handle.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

word _pascal _export PDFENDPAGE(MemHandle h)
{
    PdfDocument *p = MemLock(h);
    word error;
    PdfEndPage(p);

    error = p->error;
    MemUnlock(h);
    return error;
}

/***********************************************************************
 *
 * FUNCTION:    PDFDESTROY
 *
 * DESCRIPTION: Finish output and free the context.
 *
 * PARAMETERS:  h = context handle, or zero.
 *
 * STRATEGY:    Finalize the PDF and release the context.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Final output can fail.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

word _pascal _export PDFDESTROY(MemHandle h)
{
    PdfDocument *p;
    word error;

    if (!h) {
        return PDF_OK;
    }
    p = MemLock(h);
    PdfFinish(p);
    error = p->error;
    if (p->deviceH) {
        GrDestroyState(p->deviceH);
    }
    MemFree(h);
    return error;
}

/* Explicit little endian decoding avoids unaligned/incorrect public OpDrawLine
 * member names (CInclude/gstring.h swaps x2/y1; its GS macro is correct). */
static word u16(const byte *b)
{
    return (word)(b[0] | (word)b[1] << 8);
}

static int s16(const byte *b)
{
    return (sword)u16(b);
}

static void point(PdfDocument *p, int x, int y, const char *op)
{
    PdfPathPoint(p, (PdfFixed)x*65536L, (PdfFixed)y*65536L);
    PdfRaw(p, op);
}

static void _pascal nativePath(PdfDocument *p, GStateHandle gs, word type, int paint);
static void _pascal glyphPath(PdfDocument *p, GStateHandle gs, word character,
                              PdfFixed x, PdfFixed y);
static void _pascal clipPaths(PdfDocument *p, GStateHandle gs)
{
    nativePath(p, gs, GPT_WIN_CLIP, 2);
    if (!p->error) {
        nativePath(p, gs, GPT_CLIP, 2);
    }
}

/* Translate the GState's byte dash factors into PDF dash lengths. */
static void _pascal lineDash(PdfDocument *p, GStateHandle gs, PdfFixed width)
{
    byte dash[12];
    word i, factor;

    if (GrGetLineStyle(gs) == LS_SOLID) {
        PdfRaw(p, "[] 0 d\n");
        return;
    }

    PDFGETDASH(gs, dash);
    if (!dash[0] || dash[0] > 5 || dash[1] > 127 || width < 0) {
        p->error = PDF_STATE_ERROR;
        return;
    }
    /* ATTENTION: a PDF hairline has device-dependent width. Use SvgLib's
     * 1/16-point dash scale until a target-resolution policy is available. */
    if (!width) {
        width = 4096;
    }
    PdfRaw(p, "[");
    for (i = 0; i < (word)dash[0] * 2 + 1; ++i) {
        factor = i == dash[0] * 2 ? dash[1] : dash[2+i];
        if ((!factor && i < dash[0] * 2) ||
            (factor && width > 0x7fffffffL / factor)) {
                p->error = PDF_LIMIT_ERROR;
            return;
        }

        if (i == dash[0] * 2) {
            PdfRaw(p, "] ");
        }
        PdfNumber(p, width * factor);
    }

    PdfRaw(p, "d\n");
}

/* Establish a separate PDF graphics state for each painted element. */
static void attributes(PdfDocument *p, GStateHandle gs, Boolean fill,
                       Boolean textOutput, Boolean transformOutput)
{
    TransMatrix t;
    PdfFixed m[6], width;
    word drawMask = SDM_100;
    int i;

    if (!textOutput) {
        drawMask = fill ? GrGetAreaMask(gs, (void*)0) : GrGetLineMask(gs, (void*)0);
        if (drawMask != SDM_0 && (GrGetMixMode(gs) != MM_COPY ||
            drawMask != SDM_100)) {
                p->error = PDF_UNSUPPORTED;
#ifndef PDF_HOST_TEST
            EC_WARNING(0x5049); /* PDF_DRAW_MODE_UNSUPPORTED. */
#endif
            return;
        }
    }

    GrGetTransform(gs, &t);
    PdfRaw(p, "q\n");
    /* Keep operand validation and kernel pen updates for invisible shapes. */
    if (drawMask == SDM_0) {
        PdfRaw(p, "0 0 0 0 re W n\n");
    }
    if (transformOutput) {
        if (!matrix(p, &t, m)) {
            return;
        }
        PdfApplyPageMatrix(p);
        for (i = 0; i < 6; ++i) {
            PdfNumber(p, m[i]);
        }
        PdfRaw(p, "cm\n");
    }

    if (!textOutput) {
        PdfColor(p, fill ? GrGetAreaColor(gs) : GrGetLineColor(gs), !fill);
    }
    if (!fill && !textOutput) {
        width = (PdfFixed)GrGetLineWidth(gs);
        PdfNumber(p, width);
        PdfRaw(p, "w\n");
        if (drawMask != SDM_0) {
            lineDash(p, gs, width);
        }
        PdfInteger(p, GrGetLineEnd(gs));
        PdfRaw(p, "J\n");
        PdfInteger(p, GrGetLineJoin(gs));
        PdfRaw(p, "j\n");
        PdfNumber(p, (PdfFixed)GrGetMiterLimit(gs));
        PdfRaw(p, "M\n");
    }
}

/* GEOS mathematical characters absent from PDF MacRomanEncoding. The
 * Symbol byte values are the existing EPS greekMapTab mapping. */
static word _pascal textCharacter(byte source, byte *encodedP, word font)
{
    switch (source) {
    case C_NONBRKHYPHEN:
        *encodedP = '-';
    return font;
    case 0xad:
        *encodedP = 0xb9;
    return PDF_FONT_SYMBOL;
    case 0xb0:
        *encodedP = 0xa5;
    return PDF_FONT_SYMBOL;
    case 0xb2:
        *encodedP = 0xa3;
    return PDF_FONT_SYMBOL;
    case 0xb3:
        *encodedP = 0xb3;
    return PDF_FONT_SYMBOL;
    case 0xb6:
        *encodedP = 0x64;
    return PDF_FONT_SYMBOL;
    case 0xb7:
        *encodedP = 0x53;
    return PDF_FONT_SYMBOL;
    case 0xb8:
        *encodedP = 0x50;
    return PDF_FONT_SYMBOL;
    case 0xb9:
        *encodedP = 0x70;
    return PDF_FONT_SYMBOL;
    case 0xba:
        *encodedP = 0xf2;
    return PDF_FONT_SYMBOL;
    case 0xbd:
        *encodedP = 0x57;
    return PDF_FONT_SYMBOL;
    case 0xc3:
        *encodedP = 0xd6;
    return PDF_FONT_SYMBOL;
    case 0xc5:
        *encodedP = 0xbb;
    return PDF_FONT_SYMBOL;
    case 0xc6:
        *encodedP = 0x44;
    return PDF_FONT_SYMBOL;
    case 0xd7:
        *encodedP = 0xe0;
    return PDF_FONT_SYMBOL;
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
            p->error = PDF_LIMIT_ERROR;
        return FALSE;
    }

    *sumP = a + b; return TRUE;
}

/***********************************************************************
 *
 * FUNCTION:    text
 *
 * DESCRIPTION: Translate a GEOS text run to PDF.
 *
 * PARAMETERS:  p = context; gs = graphics state; s = source bytes.
 *
 * STRATEGY:    Use GEOS text metrics and attributes for PDF operators.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Unsupported text modes are rejected.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static PdfFixed _pascal text(PdfDocument *p, GStateHandle gs, PdfFixed x, PdfFixed y,
                             const byte *s, word count, Boolean baseline, word limit)
{
    WWFixedAsDWord size;
    word style, font, i, drawMask, fontID, glyphFont, patternSize, mode;
    MemHandle patternH;
    word pattern;
    byte encoded, glyph, metricGlyph, pair[2];
    PdfFixed advance = 0, previous = 0, width, kern, origin, offset, thickness, fontBase;
    PdfFixed glyphY;
    Boolean drawGlyph, visible, path = p->pathTransform != (void*)0;

    drawMask = GrGetTextMask(gs, (void*)0);
    visible = path || drawMask != SDM_0;
    if (!path && visible && (drawMask != SDM_100 || GrGetMixMode(gs) != MM_COPY)) {
        p->error = PDF_UNSUPPORTED;
        return 0;
    }

    pattern = GRGETTEXTPATTERN(gs, &patternH, &patternSize);
    if (((byte)pattern == PT_CUSTOM_HATCH || (byte)pattern == PT_CUSTOM_BITMAP) && patternH)
        MemFree(patternH);
    if (!path && visible && (byte)pattern != PT_SOLID) {
        p->error = PDF_UNSUPPORTED;
        return 0;
    }

    fontID = GrGetFont(gs, &size);
    style = GrGetTextStyle(gs);
    if (visible && (style & ~(TS_BOLD | TS_ITALIC | TS_UNDERLINE | TS_STRIKE_THRU |
                              TS_SUPERSCRIPT | TS_SUBSCRIPT))) {
        p->error = PDF_UNSUPPORTED;
        return 0;
    }

    mode = GrGetTextMode(gs);
    if (!baseline && !(mode & TM_DRAW_BASE)) {
        offset = (PdfFixed)GrFontMetrics(gs, GFMI_BASELINE);
        if (mode & TM_DRAW_BOTTOM) {
            offset -= (PdfFixed)GrFontMetrics(gs, GFMI_HEIGHT);
        } else if (mode & TM_DRAW_ACCENT) {
            offset -= (PdfFixed)GrFontMetrics(gs, GFMI_ACCENT);
        }
        if (!addFixed(p, y, offset, &y)) {
            return 0;
        }
    }

    glyphY = y;
    if (visible && (style & (TS_SUPERSCRIPT | TS_SUBSCRIPT))) {
        /* Native widths already include script scaling. Move only the glyph
         * baseline; kernel underline/strike bars retain the original top. */
        offset = (PdfFixed)PDFSCRIPTY(gs);
        if (!addFixed(p, y, offset, &glyphY)) return 0;
        size /= 2;
    }

    font = (style & TS_BOLD ? 1 : 0) + (style & TS_ITALIC ? 2 : 0);
    switch (fontID & 0x0e00) {
    case FG_SERIF:
        font += 4;
        break;
    case FG_MONO:
        font += 8;
        break;
    case FG_SYMBOL:
        if ((fontID & 0x0fff) == (FID_PS_SYMBOL & 0x0fff)) {
            font = PDF_FONT_SYMBOL;
        } else if ((fontID & 0x0fff) == 0x0801 || (fontID & 0x0fff) == 0x0802)
            font = PDF_FONT_DINGBATS;
        else if (visible && !path) {
            p->error = PDF_UNSUPPORTED;
            return 0;
        }

        break;
    }

    if (visible && !path) {
        PdfColor(p, GrGetTextColor(gs), 0);
    }
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
                previous = 0;
                continue;
            }

            glyph = '-';
        }

        metricGlyph = glyph;
        drawGlyph = TRUE;
        switch (glyph) {
        case C_GRAPHIC:
            /* A text graphic requires its callback/data, not a blank glyph. */
            if (visible) p->error = PDF_UNSUPPORTED;
            break;
        case C_TAB:
            glyph = C_LOGICAL_NOT;
            drawGlyph = (mode & TM_DRAW_CONTROL_CHARS) != 0;
            break;
        case C_CR:
            glyph = C_PARAGRAPH;
            drawGlyph = (mode & TM_DRAW_CONTROL_CHARS) != 0;
            break;
        case C_CTRL_K: /* GEOS section break. */
            glyph = C_SECTION;
            drawGlyph = (mode & TM_DRAW_CONTROL_CHARS) != 0;
            break;
        case C_CTRL_L: /* GEOS page/column break. */
            glyph = C_DBLDAGGER;
            drawGlyph = (mode & TM_DRAW_CONTROL_CHARS) != 0;
            break;
        case C_LINEFEED:
        case C_NULL_WIDTH:
        case C_THINSPACE:
        case C_ENSPACE:
        case C_EMSPACE:
            drawGlyph = FALSE;
            break;
        case C_SPACE:
        case C_NONBRKSPACE:
            if (mode & TM_DRAW_CONTROL_CHARS) glyph = C_CNTR_DOT;
            break;
        }
        if (p->error) break;

        width = (PdfFixed)PDFTEXTWIDTHFIXED(gs, (const char *)(s+i), 1);
        if (width < 0) {
            p->error = PDF_LIMIT_ERROR;
            break;
        }

        kern = 0;
        if (i) {
            pair[0] = s[i-1];
            pair[1] = s[i];
            kern = (PdfFixed)PDFTEXTWIDTHFIXED(gs, (const char *)pair, 2);
            if (kern < 0) {
                p->error = PDF_LIMIT_ERROR;
                break;
            }

            if (!addFixed(p, kern, -previous, &kern) ||
                !addFixed(p, kern, -width, &kern)) break;
        }

        if (!addFixed(p, advance, kern, &advance) ||
            !addFixed(p, x, advance, &origin)) break;
        if (visible && drawGlyph) {
            glyphFont = textCharacter(glyph, &encoded, font);
            if (glyphFont == 0xffff && !path) {
                p->error = PDF_UNSUPPORTED;
                break;
            }
            /* VidCom KernChar applies track kerning before painting, including
             * the first glyph. Single width minus bare glyph width also keeps
             * GEOS space padding at the same side of the space character. */
            /* VidCom maps formatting marks before painting, then restores
             * the original character's advance afterwards. Use the original
             * bare width here so a wider mark does not move its own origin. */
            offset = (PdfFixed)GrCharWidth(gs, metricGlyph);
            if (offset < 0) {
                p->error = PDF_LIMIT_ERROR;
                break;
            }

            if (!addFixed(p, width, -offset, &offset) ||
                !addFixed(p, origin, offset, &origin)) break;
            if (path) {
                glyphPath(p, gs, glyph == C_NONBRKHYPHEN ? '-' : glyph, origin, glyphY);
            } else {
                PdfText(p, origin, glyphY, (PdfFixed)size, glyphFont, &encoded, 1);
            }
        }

        if (!addFixed(p, advance, width, &advance)) {
            break;
        }
        previous = width;
    }

    if (visible && !p->error && advance > 0 &&
        (style & (TS_UNDERLINE | TS_STRIKE_THRU))) {
        if (!addFixed(p, x, advance, &origin)) {
            return advance;
        }
        /* GDFS_limit caps decoration only; the text pen keeps its advance. */
        if (limit != 0xffff && origin > (PdfFixed)limit * 65536L)
            origin = (PdfFixed)limit * 65536L;
        if (origin > x) {
            thickness = (PdfFixed)GrFontMetrics(gs, GFMI_UNDER_THICKNESS);
            fontBase = (PdfFixed)GrFontMetrics(gs, GFMI_BASELINE);
            if (thickness < 0 || fontBase < 0) {
                p->error = PDF_LIMIT_ERROR;
                return advance;
            }
            /* Native DrawOneBar uses the same thickness for both styles,
             * with positions relative to the top of the font, not baseline. */
            for (i = TS_UNDERLINE; i <= TS_STRIKE_THRU && !p->error; i <<= 1) {
                if ((style & i) && thickness) {
                    offset = (PdfFixed)GrFontMetrics(gs,
                        i == TS_UNDERLINE ? GFMI_UNDER_POS : GFMI_STRIKE_POS);
                    if (!addFixed(p, offset, -fontBase, &offset) ||
                        !addFixed(p, y, offset, &offset)) break;
                    if (path) {
                        if (!addFixed(p, offset, thickness, &kern)) break;
                        PdfPathRect(p, x, offset, origin, kern);
                    } else {
                        PdfNumber(p, x);
                        PdfNumber(p, offset);
                        PdfNumber(p, origin - x);
                        PdfNumber(p, thickness);
                        PdfRaw(p, "re f\n");
                    }
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
}

PdfTextField;
/* ESP TextAttr ends with word alignment; packed C TextAttr has no padding. */
typedef struct {
    word count;
    TextAttr attr;
    byte padding;
}

PdfTextRun;
#pragma pack()

/* Validate without painting: object bounds can use a temporary text path. */
static word _pascal textFieldSize(const byte *b, word size)
{
    word left, pos, n;

    if (size < 1 + sizeof(PdfTextField)) {
        return PDF_STATE_ERROR;
    }
    left = u16(b + 1);
    pos = 1 + sizeof(PdfTextField);
    while (left) {
        if (pos > size || (word)(size - pos) < (word)sizeof(PdfTextRun)) {
            return PDF_STATE_ERROR;
        }
        n = u16(b + pos);
        pos += sizeof(PdfTextRun);
        if (!n || n > left || n > size - pos) {
            return PDF_STATE_ERROR;
        }
        left -= n;
        pos += n;
    }
    return PDF_OK;
}

/* Decode packed style runs before emitting GEOS text field glyphs. */
static void textField(PdfDocument *p, GStateHandle gs, const byte *b, word size)
{
    const PdfTextField *f;
    const PdfTextRun *r;
    word left, pos, n;
    PdfFixed x, y, advance;

    if (textFieldSize(b, size)) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    f = (const PdfTextField *)(b + 1);
    left = f->count;
    x = (PdfFixed)f->x.WBF_int * 65536L + (word)f->x.WBF_frac * 256L;
    y = (PdfFixed)f->y.WBF_int * 65536L + (word)f->y.WBF_frac * 256L;
    advance = (PdfFixed)f->baseline.WBF_int * 65536L + (word)f->baseline.WBF_frac * 256L;
    if (!addFixed(p, y, advance, &y)) {
        return;
    }
    pos = 1 + sizeof(PdfTextField);
    while (left && !p->error) {
        r = (const PdfTextRun *)(b + pos);
        n = r->count;
        pos += sizeof(PdfTextRun);

        GrSetTextAttr(gs, &r->attr);
        advance = text(p, gs, x, y, b + pos, n, TRUE, f->limit);
        if (!addFixed(p, x, advance, &x)) {
            break;
        }
        left -= n;
        pos += n;
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

/* Null-window playback rejects these primitives before their pen setter.
 * Mirror the recorded GString's setter after playback. For relative arcs the
 * kernel's recording branch also calls the absolute setter last. */
static void _pascal arcToPen(GStateHandle gs, const byte *b)
{
    if ((b[0] == GR_DRAW_ARC_3POINT_TO || b[0] == GR_FILL_ARC_3POINT_TO ||
         b[0] == GR_DRAW_REL_ARC_3POINT_TO) && u16(b+1))
        GrMoveToWWFixed(gs, operandFixed(b+11), operandFixed(b+15));
}

static void _pascal fixedPoint(PdfDocument *p, PdfFixed x, PdfFixed y, const char *op)
{
    PdfPathPoint(p, x, y);
    PdfRaw(p, op);
}

/* Validate captured geometry before kernel playback as well as at painting.
 * A path may be defined without ever being painted. */
static word _pascal geometrySize(const byte *b, word size)
{
    word expected = 0, header, count;

    if (!size) {
        return PDF_STATE_ERROR;
    }
    switch (b[0]) {
    case GR_DRAW_TEXT_FIELD:
        return textFieldSize(b, size);
    case GR_DRAW_TEXT:
        return size >= 7 && u16(b+5) == size - 7 ? PDF_OK : PDF_STATE_ERROR;
    case GR_DRAW_TEXT_CP:
        return size >= 3 && u16(b+1) == size - 3 ? PDF_OK : PDF_STATE_ERROR;
    case GR_DRAW_CHAR:
        expected = 6;
        break;
    case GR_DRAW_CHAR_CP:
        expected = 2;
        break;
    case GR_DRAW_LINE:
    case GR_DRAW_RECT:
    case GR_FILL_RECT:
    case GR_DRAW_ELLIPSE:
    case GR_FILL_ELLIPSE:
    case GR_DRAW_REL_LINE_TO:
        expected = 9;
        break;
    case GR_DRAW_LINE_TO:
    case GR_DRAW_RECT_TO:
    case GR_FILL_RECT_TO:
    case GR_DRAW_POINT:
        expected = 5;
        break;
    case GR_DRAW_POINT_CP:
        expected = 1;
        break;
    case GR_DRAW_ARC:
    case GR_FILL_ARC:
        if (size != 15 || u16(b+1) > ACT_PIE ||
            (b[0] == GR_FILL_ARC && !u16(b+1))) return PDF_STATE_ERROR;
        return PDF_OK;
    case GR_DRAW_ARC_3POINT:
    case GR_FILL_ARC_3POINT:
    case GR_DRAW_ARC_3POINT_TO:
    case GR_FILL_ARC_3POINT_TO:
    case GR_DRAW_REL_ARC_3POINT_TO:
        expected = b[0] == GR_DRAW_ARC_3POINT || b[0] == GR_FILL_ARC_3POINT ? 27 : 19;
        if (size != expected || u16(b+1) > ACT_PIE ||
            ((b[0] == GR_FILL_ARC_3POINT || b[0] == GR_FILL_ARC_3POINT_TO) &&
             !u16(b+1))) return PDF_STATE_ERROR;
        return PDF_OK;
    case GR_DRAW_HLINE:
    case GR_DRAW_VLINE:
    case GR_DRAW_ROUND_RECT_TO:
    case GR_FILL_ROUND_RECT_TO:
        expected = 7;
        break;
    case GR_DRAW_HLINE_TO:
    case GR_DRAW_VLINE_TO:
        expected = 3;
        break;
    case GR_DRAW_ROUND_RECT:
    case GR_FILL_ROUND_RECT:
        expected = 11;
        break;
    case GR_DRAW_CURVE:
        expected = 17;
        break;
    case GR_DRAW_CURVE_TO:
        expected = 13;
        break;
    case GR_DRAW_REL_CURVE_TO:
        expected = 25;
        break;
    case GR_BRUSH_POLYLINE:
        if (size < 5 || u16(b+1) > (size-5)/4 || size-5 != u16(b+1)*4)
            return PDF_STATE_ERROR;
        return PDF_OK;
    case GR_DRAW_POLYLINE:
    case GR_DRAW_POLYGON:
    case GR_FILL_POLYGON:
    case GR_DRAW_SPLINE:
    case GR_DRAW_SPLINE_TO:
        header = b[0] == GR_FILL_POLYGON ? 4 : 3;
        if (size < header) {
            return PDF_STATE_ERROR;
        }
        count = u16(b+1);
        if (!count || count > (size-header)/4 || size-header != count*4 ||
            (header == 4 && b[3] > 1)) return PDF_STATE_ERROR;
        if (b[0] == GR_DRAW_SPLINE && (count < 4 || (count-1)%3)) {
            return PDF_STATE_ERROR;
        }
        if (b[0] == GR_DRAW_SPLINE_TO && (count < 3 || count%3)) {
            return PDF_STATE_ERROR;
        }
        return PDF_OK;
    default:
        return PDF_UNSUPPORTED;
    }

    return size == expected ? PDF_OK : PDF_STATE_ERROR;
}

/* Device pixels are physical page units. A separate, lazily owned GState
 * applies only the page matrix; the live playback state remains untouched. */
static Boolean _pascal deviceState(PdfDocument *p)
{
    TransMatrix t;
    word i;

    if (!p->deviceH) {
        p->deviceH = GrCreateState(0);
    }
    if (!p->deviceH) {
        p->error = PDF_LIMIT_ERROR;
        return FALSE;
    }
    /* The first four packed coefficients have identical 16.16 layout. */
    for (i = 0; i < 16; ++i) {
        ((byte *)&t)[i] = ((const byte *)p->pageMatrix)[i];
    }
    t.TM_e31.DWF_int = p->pageMatrix[4] >> 16;
    t.TM_e31.DWF_frac = (word)p->pageMatrix[4];
    t.TM_e32.DWF_int = p->pageMatrix[5] >> 16;
    t.TM_e32.DWF_frac = (word)p->pageMatrix[5];
    GrSetTransform(p->deviceH, &t);
    return TRUE;
}

/* Exact 300/72 conversion of a 32.16 point coordinate, rounded as GEOS does.
 * Split integer/fraction parts before multiplying to keep all products 32-bit. */
static sdword _pascal deviceCoordinate(PdfDocument *p, const DWFixed *vP)
{
    sdword whole, pixel, remainder;

    if (vP->DWF_int < -32768L || vP->DWF_int > 32767L) {
        p->error = PDF_LIMIT_ERROR;
        return 0;
    }

    whole = vP->DWF_int * PDF_DEVICE_DPI;
    pixel = whole / 72;
    remainder = whole % 72;
    if (remainder < 0) {
        remainder += 72;
        --pixel;
    }

    return pixel + (remainder * 65536L + (sdword)vP->DWF_frac * PDF_DEVICE_DPI +
                    36L * 65536L) / (72L * 65536L);
}

/* Apply playback and page transforms before rounding to device pixels. */
static void _pascal devicePoint(PdfDocument *p, GStateHandle gs, int x, int y,
                                sdword *xP, sdword *yP)
{
    PointDWFixed v;
    v.PDF_x.DWF_int = x;
    v.PDF_x.DWF_frac = 0;
    v.PDF_y.DWF_int = y;
    v.PDF_y.DWF_frac = 0;
    GrTransformDWFixed(gs, &v);
    GrTransformDWFixed(p->deviceH, &v);
    *xP = deviceCoordinate(p, &v.PDF_x); *yP = deviceCoordinate(p, &v.PDF_y);
}

/***********************************************************************
 *
 * FUNCTION:    devicePaint
 *
 * DESCRIPTION: Render device-pixel drawing operations.
 *
 * PARAMETERS:  p = context; gs = graphics state; b = record.
 *
 * STRATEGY:    Map point and brush geometry to device coordinates.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Unsupported mix modes and masks are rejected.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static void _pascal devicePaint(PdfDocument *p, GStateHandle gs, GStateHandle styleGS,
                               const byte *b, word size, Boolean path)
{
    word n, i, mask, brush, width, height;
    sdword x, y, nextX, nextY;
    XYValueAsDWord cp;

    if (geometrySize(b, size)) {
        p->error = PDF_STATE_ERROR;
        return;
    }

    if (b[0] == GR_BRUSH_POLYLINE && u16(b+1) < 2) {
        return;
    }
    if (!path) {
        mask = b[0] == GR_BRUSH_POLYLINE ? GrGetLineMask(styleGS, (void*)0) : GrGetAreaMask(styleGS, (void*)0);
        if (mask == SDM_0) {
            return;
        }
        if (mask != SDM_100 || GrGetMixMode(styleGS) != MM_COPY) {
            p->error = PDF_UNSUPPORTED;
            return;
        }

        PdfColor(p, b[0] == GR_BRUSH_POLYLINE ? GrGetLineColor(styleGS) : GrGetAreaColor(styleGS), FALSE);
    }

    if (!deviceState(p)) {
        return;
    }
    PdfRaw(p, "0.24 0 0 0.24 0 0 cm\n"); /* Exactly 72/300 physical points per pixel. */
    if (b[0] != GR_BRUSH_POLYLINE) {
        cp = GrGetCurPos(gs);
        devicePoint(p, gs, b[0] == GR_DRAW_POINT ? s16(b+1) : (sword)(word)cp,
                    b[0] == GR_DRAW_POINT ? s16(b+3) : (sword)(word)(cp >> 16), &x, &y);
        PdfInteger(p, x);
        PdfInteger(p, y);
        PdfRaw(p, path ? "1 1 re\n" : "1 1 re f\n");
        return;
    }

    n = u16(b+1);
    if (n < 2) return; /* VidPolyline needs a segment, not a single point. */
    brush = u16(b+3) - 0x0101;
    width = brush & 0x0080 ? 1 : (brush & 0xff) + 1;
    height = brush & 0x8000 ? 1 : (brush >> 8) + 1;
    devicePoint(p, gs, s16(b+5), s16(b+7), &x, &y);
    for (i = 1; i < n && !p->error; ++i) {
        devicePoint(p, gs, s16(b+5+i*4), s16(b+7+i*4), &nextX, &nextY);
        PdfBrushSegment(p, x, y, nextX, nextY, width, height);
        x = nextX;
        y = nextY;
    }
}

/* PDF path operands must share the coordinate system used when painting.
 * Use the kernel for captured transforms. Clips/fills use physical page
 * coordinates; strokes use the final painting state's coordinates so its
 * affine line width remains correct when S is emitted. */
static void _pascal transformPathPoint(void *context, PdfFixed *xP, PdfFixed *yP)
{
    PdfDocument *p = context;

    PointDWFixed v;
    v.PDF_x.DWF_int = *xP >> 16;
    v.PDF_x.DWF_frac = (word)*xP;
    v.PDF_y.DWF_int = *yP >> 16;
    v.PDF_y.DWF_frac = (word)*yP;
    GrTransformDWFixed(p->pathStateH, &v);
    if (p->pathPaintH) {
        GrUntransformDWFixed(p->pathPaintH, &v);
    } else {
        GrTransformDWFixed(p->deviceH, &v);
    }
    if (v.PDF_x.DWF_int < -32768L || v.PDF_x.DWF_int > 32767L ||
        v.PDF_y.DWF_int < -32768L || v.PDF_y.DWF_int > 32767L) {
            p->error = PDF_LIMIT_ERROR;
        return;
    }

    *xP = (PdfFixed)((dword)(word)v.PDF_x.DWF_int << 16 | v.PDF_x.DWF_frac);
    *yP = (PdfFixed)((dword)(word)v.PDF_y.DWF_int << 16 | v.PDF_y.DWF_frac);
}

/***********************************************************************
 *
 * FUNCTION:    output
 *
 * DESCRIPTION: Dispatch a GString drawing record.
 *
 * PARAMETERS:  p = context; gs = graphics state; b = record.
 *
 * STRATEGY:    Validate and dispatch native output primitives.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Unknown geometry terminates translation.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static void output(PdfDocument *p, GStateHandle gs, const byte *b, word size,
                   Boolean path, PointWWFixed *subStartP)
{
    word op = b[0], n, pos, i;
    PointWWFixed textPen;
    XYValueAsDWord cp = GrGetCurPos(gs);
    int x = (sword)(word)cp, y = (sword)(word)(cp >> 16);
    int x2, y2;
    PdfFixed fx, fy, baseX, baseY, arcStart[6];
    Boolean fill = op == GR_FILL_RECT || op == GR_FILL_RECT_TO ||
                   op == GR_FILL_POLYGON || op == GR_FILL_ELLIPSE ||
                   op == GR_FILL_ROUND_RECT || op == GR_FILL_ROUND_RECT_TO ||
                   op == GR_DRAW_POINT || op == GR_DRAW_POINT_CP || op == GR_FILL_ARC ||
                   op == GR_FILL_ARC_3POINT || op == GR_FILL_ARC_3POINT_TO;
    if (!path) {
        PdfRaw(p, "q\n");
        clipPaths(p, gs);
        if (op == GR_DRAW_PATH || op == GR_FILL_PATH) {
            if (size != (op == GR_DRAW_PATH ? 1 : 2) ||
                (op == GR_FILL_PATH && b[1] > 1)) goto bad;
            nativePath(p, gs, GPT_CURRENT, op == GR_DRAW_PATH ? -1 : b[1]);
            PdfRaw(p, "Q\n");
            return;
        }

        if (op == GR_DRAW_POINT || op == GR_DRAW_POINT_CP || op == GR_BRUSH_POLYLINE) {
            devicePaint(p, gs, gs, b, size, FALSE);
            PdfRaw(p, "Q\n");
            return;
        }

        attributes(p, gs, fill, op >= GR_DRAW_CHAR && op <= GR_DRAW_TEXT_FIELD, TRUE);
    }

    /* Every record length is checked before its operands are decoded. */
    switch (op) {
    case GR_REL_MOVE_TO:
    case GR_MOVE_TO_WWFIXED:
    case GR_DRAW_REL_LINE_TO:
        if (size != 9) {
            goto bad;
        }
        GrGetCurPosWWFixed(gs, &textPen);
        baseX = fixed(textPen.PF_x);
        baseY = fixed(textPen.PF_y);
        fx = operandFixed(b+1);
        fy = operandFixed(b+5);
        if (op != GR_MOVE_TO_WWFIXED &&
            (!addFixed(p, baseX, fx, &fx) || !addFixed(p, baseY, fy, &fy))) break;
        if (op == GR_DRAW_REL_LINE_TO && !path) {
            fixedPoint(p, baseX, baseY, "m ");
        }
        fixedPoint(p, fx, fy, op == GR_DRAW_REL_LINE_TO ? (path ? "l\n" : "l S\n") : "m\n");
        break;
    case GR_DRAW_REL_CURVE_TO:
        if (size != 25) {
            goto bad;
        }
        GrGetCurPosWWFixed(gs, &textPen);
        baseX = fixed(textPen.PF_x);
        baseY = fixed(textPen.PF_y);
        if (!path) {
            fixedPoint(p, baseX, baseY, "m ");
        }
        for (i = 0; i < 3; ++i) {
            if (!addFixed(p, baseX, operandFixed(b+1+i*8), &fx) ||
                !addFixed(p, baseY, operandFixed(b+5+i*8), &fy)) break;
            fixedPoint(p, fx, fy, "");
        }

        PdfRaw(p, path ? "c\n" : "c S\n");
        break;
    case GR_DRAW_SPLINE:
    case GR_DRAW_SPLINE_TO:
        if (geometrySize(b, size)) {
            goto bad;
        }
        n = u16(b+1);
        pos = 3;
        if (op == GR_DRAW_SPLINE) {
            point(p, s16(b+pos), s16(b+pos+2), "m ");
            pos += 4;
            --n;
        } else if (!path) point(p, x, y, "m ");
        for (i = 0; i < n; ++i, pos += 4) {
            point(p, s16(b+pos), s16(b+pos+2), "");
            if (i%3 == 2) {
                PdfRaw(p, "c\n");
            }
        }

        if (!path) {
            PdfRaw(p, "S\n");
        }
        break;
    case GR_MOVE_TO:
        if (!path || size != 5) {
            goto bad;
        }
        point(p, s16(b+1), s16(b+3), "m\n");
        break;
    case GR_CLOSE_SUB_PATH:
        if (!path || size != 1) {
            goto bad;
        }
        PdfRaw(p, "h\n");
        break;
    case GR_DRAW_LINE:
        if (size != 9) {
            goto bad;
        }
        point(p, s16(b+1), s16(b+3), "m ");
        point(p, s16(b+5), s16(b+7), path ? "l\n" : "l S\n");
        break;
    case GR_DRAW_LINE_TO:
        if (size != 5) {
            goto bad;
        }
        if (!path) {
            point(p, x, y, "m ");
        }
        point(p, s16(b+1), s16(b+3), path ? "l\n" : "l S\n");
        break;
    case GR_DRAW_HLINE:
    case GR_DRAW_VLINE:
        if (size != 7) {
            goto bad;
        }
        x = s16(b+1);
        y = s16(b+3);
        x2 = x;
        y2 = y;
        if (op == GR_DRAW_HLINE) {
            x2 = s16(b+5);
        } else {
            y2 = s16(b+5);
        }
        point(p, x, y, "m ");
        point(p, x2, y2, path ? "l\n" : "l S\n");
        break;
    case GR_DRAW_HLINE_TO:
    case GR_DRAW_VLINE_TO:
        if (size != 3) {
            goto bad;
        }
        x2 = x;
        y2 = y;
        if (op == GR_DRAW_HLINE_TO) {
            x2 = s16(b+1);
        } else {
            y2 = s16(b+1);
        }
        if (!path) {
            point(p, x, y, "m ");
        }
        point(p, x2, y2, path ? "l\n" : "l S\n");
        break;
    case GR_DRAW_RECT:
    case GR_FILL_RECT:
        if (size != 9) {
            goto bad;
        }
        x = s16(b+1);
        y = s16(b+3);
        b += 4;
        /* FALLTHROUGH */
    case GR_DRAW_RECT_TO:
    case GR_FILL_RECT_TO:
        if ((op == GR_DRAW_RECT_TO || op == GR_FILL_RECT_TO) && size != 5) {
            goto bad;
        }
        x2 = s16(b+1);
        y2 = s16(b+3);
        if (path) {
            PdfPathRect(p, (PdfFixed)x*65536L, (PdfFixed)y*65536L,
                        (PdfFixed)x2*65536L, (PdfFixed)y2*65536L);
                        break;
        }

        PdfInteger(p, x);
        PdfInteger(p, y);
        PdfInteger(p, (long)x2 - x);
        PdfInteger(p, (long)y2 - y);
        PdfRaw(p, path ? "re\n" : (fill ? "re f\n" : "re S\n"));
        break;
    case GR_DRAW_ROUND_RECT:
    case GR_FILL_ROUND_RECT:
        if (size != 11) {
            goto bad;
        }
        PdfRoundRect(p, s16(b+3), s16(b+5), s16(b+7), s16(b+9), u16(b+1), path ? -1 : fill);
        break;
    case GR_DRAW_ROUND_RECT_TO:
    case GR_FILL_ROUND_RECT_TO:
        if (size != 7) {
            goto bad;
        }
        PdfRoundRect(p, x, y, s16(b+3), s16(b+5), u16(b+1), path ? -1 : fill);
        break;
    case GR_DRAW_ARC:
    case GR_FILL_ARC:
        if (geometrySize(b, size)) {
            goto bad;
        }
        PdfArc(p, s16(b+3), s16(b+5), s16(b+7), s16(b+9),
               s16(b+11), s16(b+13), u16(b+1), path ? -1 : fill, arcStart);
        if (path && !p->error) {
            subStartP->PF_x.WWF_int = (sword)(arcStart[0] >> 16);
            subStartP->PF_x.WWF_frac = (word)arcStart[0];
            subStartP->PF_y.WWF_int = (sword)(arcStart[1] >> 16);
            subStartP->PF_y.WWF_frac = (word)arcStart[1];
        }

        break;
    case GR_DRAW_ARC_3POINT:
    case GR_FILL_ARC_3POINT:
    case GR_DRAW_ARC_3POINT_TO:
    case GR_FILL_ARC_3POINT_TO:
    case GR_DRAW_REL_ARC_3POINT_TO:
        if (geometrySize(b, size)) {
            goto bad;
        }
        pos = 3;
        i = 0;
        if (size == 19) {
            GrGetCurPosWWFixed(gs, &textPen);
            arcStart[0] = fixed(textPen.PF_x);
            arcStart[1] = fixed(textPen.PF_y);
            i = 2;
        }

        for (; i < 6; ++i, pos += 4) {
            arcStart[i] = operandFixed(b+pos);
            if (op == GR_DRAW_REL_ARC_3POINT_TO &&
                !addFixed(p, arcStart[i], arcStart[i%2], arcStart+i)) break;
        }

        if (p->error) {
            break;
        }
        PdfThreePointArc(p, arcStart, u16(b+1), path ? -1 : fill);
        if (path && !p->error) {
            subStartP->PF_x.WWF_int = (sword)(arcStart[0] >> 16);
            subStartP->PF_x.WWF_frac = (word)arcStart[0];
            subStartP->PF_y.WWF_int = (sword)(arcStart[1] >> 16);
            subStartP->PF_y.WWF_frac = (word)arcStart[1];
        }

        break;
    case GR_DRAW_ELLIPSE:
    case GR_FILL_ELLIPSE:
        if (size != 9) {
            goto bad;
        }
        PdfEllipse(p, s16(b+1), s16(b+3), s16(b+5), s16(b+7), path ? -1 : fill);
        break;
    case GR_DRAW_CURVE:
    case GR_DRAW_CURVE_TO:
        pos = 1;
        if (op == GR_DRAW_CURVE) {
            if (size != 17) {
                goto bad;
            }
            x = s16(b+1);
            y = s16(b+3);
            pos = 5;
        } else if (size != 13) goto bad;
        if (!path || op == GR_DRAW_CURVE) {
            point(p, x, y, "m ");
        }
        for (i = 0; i < 3; ++i, pos += 4) {
            point(p, s16(b+pos), s16(b+pos+2), "");
        }
        PdfRaw(p, path ? "c\n" : "c S\n");
        break;
    case GR_BRUSH_POLYLINE:
        if (!path || geometrySize(b, size)) {
            goto bad;
        }
        n = u16(b+1);
        for (i = 0; i < n; ++i)
            point(p, s16(b+5+i*4), s16(b+7+i*4), i ? "l " : "m ");
        PdfRaw(p, "\n");
        break;
    case GR_DRAW_POLYLINE:
    case GR_DRAW_POLYGON:
    case GR_FILL_POLYGON:
        if (size < (fill ? 4 : 3)) {
            goto bad;
        }
        n = u16(b+1);
        pos = fill ? 4 : 3;
        if (!n || n > (size - pos) / 4 || size - pos != n * 4) {
            goto bad;
        }
        for (i = 0; i < n; ++i, pos += 4)
            point(p, s16(b+pos), s16(b+pos+2), i ? "l " : "m ");
        if (fill && b[3] > 1) {
            goto bad;
        }
        if (path) {
            PdfRaw(p, op == GR_DRAW_POLYLINE ? "\n" : "h\n");
        } else PdfRaw(p, fill ? (b[3] ? "h f\n" : "h f*\n") :
                             (op == GR_DRAW_POLYGON ? "h S\n" : "S\n"));
                             break;
    case GR_DRAW_TEXT:
        if (size < 7 || u16(b+5) != size - 7) {
            goto bad;
        }
        text(p, gs, (PdfFixed)s16(b+1)*65536L, (PdfFixed)s16(b+3)*65536L, b+7, u16(b+5), FALSE, 0xffff);
        break;
    case GR_DRAW_TEXT_CP:
        if (size < 3 || u16(b+1) != size - 3) {
            goto bad;
        }
        GrGetCurPosWWFixed(gs, &textPen);
        text(p, gs, fixed(textPen.PF_x), fixed(textPen.PF_y), b+3, u16(b+1), FALSE, 0xffff);
        break;
    case GR_DRAW_CHAR:
        if (size != 6) {
            goto bad;
        }
        text(p, gs, (PdfFixed)s16(b+2)*65536L, (PdfFixed)s16(b+4)*65536L, b+1, 1, FALSE, 0xffff);
        break;
    case GR_DRAW_CHAR_CP:
        if (size != 2) {
            goto bad;
        }
        GrGetCurPosWWFixed(gs, &textPen);
        text(p, gs, fixed(textPen.PF_x), fixed(textPen.PF_y), b+1, 1, FALSE, 0xffff);
        break;
    case GR_DRAW_TEXT_FIELD:
        textField(p, gs, b, size);
        break;
    default:
        p->error = PDF_UNSUPPORTED;
    }

    if (!path) {
        PdfRaw(p, "Q\nQ\n");
    }
    return;
bad:
    p->error = PDF_STATE_ERROR;
}

/***********************************************************************
 * FUNCTION:    glyphPath
 * DESCRIPTION: Append one native font outline to the current PDF path.
 * STRATEGY:    Record one glyph through DR_FONT_GEN_PATH. Replay its bounded
 *              geometry on the saved path state, using the existing native
 *              coordinate callback. Keep neither a font nor a page cache.
 * CAVEATS:     Bitmap-only fonts have no outline and fail explicitly.
 * REVISION HISTORY:
 *              Codex/MeyerK 11/07/26 Initial version.
 ***********************************************************************/
static void _pascal glyphPath(PdfDocument *p, GStateHandle gs, word character,
                              PdfFixed x, PdfFixed y)
{
    MemHandle blockH;
    GStateHandle string = 0;
    TransMatrix transform;
    PointWWFixed subStart;
    WWFixedAsDWord size;
    word chunk, font = 0, op = 0, bytes = 0, result, last, style;
    byte element[32];
    Boolean saved = FALSE, contour = FALSE;

    blockH = MemAllocLMem(LMEM_TYPE_GENERAL, 0);
    if (!blockH) {
        p->error = PDF_LIMIT_ERROR;
        return;
    }
    string = GrCreateGString(blockH, GST_CHUNK, &chunk);
    if (!string) {
        p->error = PDF_LIMIT_ERROR;
        goto cleanup;
    }
    font = GrGetFont(gs, &size);
    GrSetFont(string, font, size);
    style = GrGetTextStyle(gs);
    /* Apply script placement ourselves. Driver path transforms use different
     * script translations from their native text rasterizers. */
    GrSetTextStyle(string, style & ~(TS_SUPERSCRIPT | TS_SUBSCRIPT), 0xff);
    GrSetFontWeight(string, GrGetFontWeight(gs));
    GrSetFontWidth(string, GrGetFontWidth(gs));
    GrGetTransform(gs, &transform);
    GrSetTransform(string, &transform);
    /* Fractional placement is in the matrix: font drivers query integer CP.
     * PostScript outlines are baseline-relative with Y increasing upwards. */
    GrApplyTranslation(string, x, y);
    if (style & (TS_SUPERSCRIPT | TS_SUBSCRIPT))
        GrApplyScale(string, 32768L, -32768L);
    else GrApplyScale(string, 65536L, -65536L);
    p->error = PDFGENCHAR(string, character);
    if (p->error) goto cleanup;
    if (GrEndGString(string) != GSET_NO_ERROR) {
        p->error = PDF_LIMIT_ERROR;
        goto cleanup;
    }
    GrDestroyGString(string, 0, GSKT_LEAVE_DATA);
    string = GrLoadGString(blockH, GST_CHUNK, chunk);
    if (!string) {
        p->error = PDF_LIMIT_ERROR;
        goto cleanup;
    }

    GrSaveState(gs);
    saved = TRUE;
    GrSetNullTransform(gs);
    GrMoveTo(gs, 0, 0);
    result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
    while (!p->error && result == GSRT_ONE) {
        op = GrGetGStringElement(gs, string, 0, (void*)0, &bytes);
        if (op == GR_END_GSTRING) break;
        if (op == GR_COMMENT) {
            GrSetGStringPos(string, GSSPT_SKIP_1, 0);
            continue;
        }
        if (!bytes || bytes > sizeof(element)) {
            /* ATTENTION: glyph commands are limited to 32 bytes. Extend
             * this bounded decoder if a font driver adds larger records. */
            p->error = PDF_LIMIT_ERROR;
            break;
        }
        GrGetGStringElement(gs, string, bytes, element, &bytes);
        if (op == GR_MOVE_TO || op == GR_DRAW_LINE_TO || op == GR_DRAW_HLINE_TO ||
            op == GR_DRAW_VLINE_TO || op == GR_DRAW_REL_LINE_TO ||
            op == GR_DRAW_CURVE_TO || op == GR_DRAW_REL_CURVE_TO ||
            op == GR_CLOSE_SUB_PATH) {
            if (op == GR_MOVE_TO) {
                if (contour) PdfRaw(p, "h\n");
                contour = TRUE;
            } else if (!contour) {
                p->error = PDF_STATE_ERROR;
                break;
            }
            output(p, gs, element, bytes, TRUE, &subStart);
        } else if (!((op >= GR_APPLY_ROTATION && op <= GR_RESTORE_TRANSFORM) ||
                     (op >= GR_SET_MIX_MODE && op <= GR_SET_CUSTOM_TEXT_PATTERN))) {
            p->error = PDF_UNSUPPORTED;
            break;
        }
        result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
        if (op == GR_MOVE_TO) GrGetCurPosWWFixed(gs, &subStart);
        if (op == GR_CLOSE_SUB_PATH)
            GrMoveToWWFixed(gs, fixed(subStart.PF_x), fixed(subStart.PF_y));
    }
    if (!p->error && result != GSRT_ONE && result != GSRT_COMPLETE)
        p->error = PDF_STATE_ERROR;
    if (!p->error && contour) PdfRaw(p, "h\n");

cleanup:
#ifndef PDF_HOST_TEST
    if (p->error) {
        EC_WARNING(0x5047); /* PDF_TEXT_PATH_REQUIRED: inspect the native glyph. */
    }
#endif
    if (string) GrDestroyGString(string, saved ? gs : 0, GSKT_LEAVE_DATA);
    if (saved) GrRestoreState(gs);
    MemFree(blockH);
}

/***********************************************************************
 *
 * FUNCTION:    regionPath
 * DESCRIPTION: Append one native region strip to the PDF construction path.
 * PARAMETERS:  gs = reconstructed clip; bandOffset = physical row origin.
 * STRATEGY:    Decode inclusive scanline bands and emit disjoint rectangles.
 *              The region copy is owned here and freed on every exit.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              ATTENTION: Boolean unions use the printer's 300 dpi grid.
 *              Ordinary paths retain curves; exact vector unions need a
 *              curve Boolean engine. Native regions use word coordinates.
 *
 ***********************************************************************/
static void _pascal regionPath(PdfDocument *p, GStateHandle gs, sdword bandOffset)
{
    MemHandle regionH;
    const byte *regionP;
    word size, at = 12, value;
    sdword previous, bottom, top, end, left, right;
    PdfFixed x1, y1, x2, y2;
    Boolean complete = FALSE;

    regionH = GrGetClipRegion(gs, ODD_EVEN);
    if (!regionH) return; /* The intersection can genuinely be empty. */
    regionP = MemLock(regionH);
    size = MemGetInfo(regionH, MGIT_SIZE);
    if (size < 14 || u16(regionP+8) == EOREGREC || u16(regionP+10) != EOREGREC) {
        p->error = PDF_STATE_ERROR;
        goto cleanup;
    }
    previous = s16(regionP+8); /* initial empty band ends at top-1 */
    while (!p->error && at + 2UL <= size) {
        value = u16(regionP + at);
        at += 2;
        if (value == EOREGREC) {
            complete = TRUE;
            break;
        }
        bottom = (sword)value;
        if (bottom <= previous) {
            p->error = PDF_STATE_ERROR;
            break;
        }
        /* The null-window region builder reserves two safety scanlines.
         * Keep adjacent 2048-row strips disjoint, even at their boundaries. */
        top = previous < -1024 ? -1024 : previous + 1;
        end = bottom > 1023 ? 1024 : bottom + 1;
        top += bandOffset;
        end += bandOffset;
        y1 = top / 25 * 393216L + top % 25 * 393216L / 25;
        y2 = end / 25 * 393216L + end % 25 * 393216L / 25;
        while (at + 2UL <= size && u16(regionP + at) != EOREGREC) {
            if (at + 6UL > size) {
                p->error = PDF_STATE_ERROR;
                break;
            }
            left = s16(regionP + at);
            right = s16(regionP + at + 2);
            at += 4;
            if (right < left || right == -32768L) {
                p->error = PDF_STATE_ERROR;
                break;
            }
            /* 72/300 = 6/25. Divide before multiplying to avoid overflow. */
            x1 = left / 25 * 393216L + left % 25 * 393216L / 25;
            ++right;
            x2 = right / 25 * 393216L + right % 25 * 393216L / 25;
            if (end > top) PdfPathRect(p, x1, y1, x2, y2);
        }
        if (at + 2UL > size) break;
        at += 2; /* end of this band's spans */
        previous = bottom;
    }
    if (!p->error && !complete) p->error = PDF_STATE_ERROR;
cleanup:
    MemFree(regionH);
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
    TransMatrix transform, regionBase;
    PdfFixed values[6], previousMatrix[6];
    PointWWFixed subStart, pen;
    word op, size, result, last, i, combine = 0, rule = 0, sections = 0, depth = 0;
    byte header[5];
    sdword band = 0, bands = 1, bandOffset;
    Boolean open = FALSE, complete = FALSE, more, to, changed;
    Boolean subpath = FALSE, matrixKnown = FALSE, separatePen = FALSE, region = FALSE;

    if (p->error || !GrTestPath(gs, type)) {
        return;
    }
    pathH = GrGetPath(gs, type);
    if (!pathH) {
        p->error = PDF_LIMIT_ERROR;
        return;
    }

    pathP = MemLock(pathH);
    source = GrLoadGString(PtrToSegment(pathP), GST_PTR, PtrToOffset(pathP));
    if (!source) {
        p->error = PDF_LIMIT_ERROR;
        goto cleanup;
    }

    playback = GrCreateState(0);
    if (!playback) {
        p->error = PDF_LIMIT_ERROR;
        goto cleanup;
    }

    if (paint != -1 && !deviceState(p)) {
        goto cleanup;
    }
    /* Detect unions before emitting any clips: a PDF clip cannot expand. */
    if (paint >= 0) {
        while (TRUE) {
            op = GrGetGStringElement(playback, source, 0, (void*)0, &size);
            if (!size || op == GR_END_GSTRING) break;
            if (op == GR_BEGIN_PATH && size == 5) {
                GrGetGStringElement(playback, source, 5, header, &size);
                if ((header[3] & 3) == PCT_UNION) region = TRUE;
            }
            GrSetGStringPos(source, GSSPT_SKIP_1, 0);
        }
        GrSetGStringPos(source, GSSPT_BEGINNING, 0);
    }
    if (region) {
        /* Native regions use signed word device coordinates. */
        if ((sdword)p->width * PDF_DEVICE_DPI > 32767L * 72 ||
            (sdword)p->height * PDF_DEVICE_DPI > 32767L * 72) {
            p->error = PDF_LIMIT_ERROR;
            goto cleanup;
        }
        bands = ((sdword)p->height * PDF_DEVICE_DPI + 147455L) / 147456L;
    }
    PdfRaw(p, "n\n");
replay:
    if (region) {
        /* GetWinTopBottom limits null-window regions to roughly +/-1024.
         * Shift one page strip into that range for each native conversion. */
        bandOffset = band * 2048L + 1024;
        GrGetTransform(p->deviceH, &transform);
        GrApplyTranslation(playback, 0, -bandOffset * 65536L);
        GrApplyScale(playback, 273067L, 273067L); /* 300/72 in 16.16 */
        GrApplyTransform(playback, &transform);
        GrGetTransform(playback, &regionBase);
        GrInitDefaultTransform(playback);
    }
    result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
    if (result != GSRT_ONE && result != GSRT_COMPLETE) {
        p->error = PDF_STATE_ERROR;
    }
    while (!p->error && result != GSRT_COMPLETE) {
        op = GrGetGStringElement(playback, source, 0, (void*)0, &size);
        if (!size || size > 32760) {
            p->error = size ? PDF_LIMIT_ERROR : PDF_STATE_ERROR;
            break;
        }

        if (op == GR_END_GSTRING) {
            complete = TRUE;
            break;
        }

        elementH = MemAlloc(size, HF_DYNAMIC, HAF_ZERO_INIT | HAF_LOCK);
        if (!elementH) {
            p->error = PDF_LIMIT_ERROR;
            break;
        }

        elementP = MemDeref(elementH);
        GrGetGStringElement(playback, source, size, elementP, &size);
        if (op == GR_BEGIN_PATH) {
            if (open || size != 5 || u16(elementP+1) > PCT_INTERSECTION) {
                p->error = PDF_STATE_ERROR;
            } else {
                combine = sections ? elementP[3] & 3 : PCT_REPLACE;
                if (sections && paint != -1 && !region && combine != PCT_INTERSECTION)
                    p->error = PDF_UNSUPPORTED;
                rule = (elementP[3] & 0x10) ? !!(elementP[3] & 0x20) : (paint == 1);
                ++sections;
                open = TRUE;
                if (region) GrBeginPath(playback, PCT_REPLACE);
                else GrSaveState(playback);
            }

            GrSetGStringPos(source, GSSPT_SKIP_1, 0);
        } else if (op == GR_END_PATH) {
            if (!open || depth || size != 1) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            if (region) {
                GrEndPath(playback);
                GrSetClipPath(playback, combine, rule);
            } else GrRestoreState(playback);
            open = FALSE;
            GrSetGStringPos(source, GSSPT_SKIP_1, 0);
            op = GrGetGStringElement(playback, source, 0, (void*)0, &size);
            more = op != GR_END_GSTRING;
            if (!region && (paint == 2 || (paint >= 0 && more)))
                PdfRaw(p, rule ? "W n\n" : "W* n\n");
            /* GrGetPath changed each saved SetTransform to ApplyTransform.
             * Each section's saved matrix is absolute, not cumulative. */
            if (region) GrSetTransform(playback, &regionBase);
            else GrSetNullTransform(playback);
            subpath = matrixKnown = separatePen = FALSE;
        } else if ((op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F) ||
                   op == GR_MOVE_TO || op == GR_CLOSE_SUB_PATH ||
                   op == GR_REL_MOVE_TO || op == GR_MOVE_TO_WWFIXED) {
            if (region) {
                if (op == GR_MOVE_TO || op == GR_REL_MOVE_TO ||
                    op == GR_MOVE_TO_WWFIXED || op == GR_CLOSE_SUB_PATH) {
                    if (size != (op == GR_CLOSE_SUB_PATH ? 1 : op == GR_MOVE_TO ? 5 : 9))
                        p->error = PDF_STATE_ERROR;
                } else p->error = geometrySize(elementP, size);
            } else if (paint == -1 && (op == GR_DRAW_POINT || op == GR_DRAW_POINT_CP ||
                                 op == GR_BRUSH_POLYLINE)) {
                attributes(p, gs, FALSE, FALSE, TRUE);
                PdfRaw(p, "S\nQ\nq\n");
                devicePaint(p, playback, gs, elementP, size, FALSE);
                PdfRaw(p, "Q\n");
                subpath = matrixKnown = separatePen = FALSE;
            } else if (op == GR_DRAW_POINT || op == GR_DRAW_POINT_CP) {
                PdfRaw(p, "q\n");
                devicePaint(p, playback, gs, elementP, size, TRUE);
                PdfRaw(p, "Q\n");
                subpath = matrixKnown = separatePen = FALSE;
            } else {
                GrGetTransform(playback, &transform);
                if (matrix(p, &transform, values)) {
                    p->pathStateH = playback;
                    p->pathPaintH = paint == -1 ? gs : 0;
                    p->pathTransform = transformPathPoint;
                    changed = !matrixKnown;
                    for (i = 0; i < 6; ++i) {
                        if (matrixKnown && values[i] != previousMatrix[i]) {
                            changed = TRUE;
                        }
                        previousMatrix[i] = values[i];
                    }

                    matrixKnown = TRUE;
                    to = op == GR_DRAW_LINE_TO || op == GR_DRAW_HLINE_TO ||
                         op == GR_DRAW_VLINE_TO || op == GR_DRAW_REL_LINE_TO ||
                         op == GR_DRAW_CURVE_TO || op == GR_DRAW_REL_CURVE_TO ||
                         op == GR_DRAW_SPLINE_TO;
                    if (to && (!subpath || changed || separatePen)) {
                        GrGetCurPosWWFixed(playback, &subStart);
                        fixedPoint(p, fixed(subStart.PF_x), fixed(subStart.PF_y), "m\n");
                        subpath = TRUE;
                    }

                    output(p, playback, elementP, size, TRUE, &subStart);
                    if (op == GR_CLOSE_SUB_PATH && subpath)
                        GrMoveToWWFixed(playback, fixed(subStart.PF_x), fixed(subStart.PF_y));
                    else if (op == GR_DRAW_LINE || op == GR_DRAW_CURVE ||
                             op == GR_DRAW_POLYLINE || op == GR_DRAW_SPLINE || op == GR_BRUSH_POLYLINE) {
                        i = op == GR_BRUSH_POLYLINE ? 5 :
                            (op == GR_DRAW_POLYLINE || op == GR_DRAW_SPLINE ? 3 : 1);
                        subStart.PF_x.WWF_int = s16(elementP+i);
                        subStart.PF_x.WWF_frac = 0;
                        subStart.PF_y.WWF_int = s16(elementP+i+2);
                        subStart.PF_y.WWF_frac = 0;
                        subpath = TRUE;
                    } else if (op == GR_DRAW_ARC || op == GR_FILL_ARC)
                        subpath = u16(elementP+1) == ACT_OPEN;
                    else if (op == GR_DRAW_ARC_3POINT || op == GR_FILL_ARC_3POINT ||
                             op == GR_DRAW_ARC_3POINT_TO || op == GR_FILL_ARC_3POINT_TO ||
                             op == GR_DRAW_REL_ARC_3POINT_TO)
                        subpath = TRUE;
                    else if (op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F && !to)
                        subpath = FALSE;
                    separatePen = op == GR_DRAW_ARC_3POINT || op == GR_FILL_ARC_3POINT ||
                                  op == GR_DRAW_ARC_3POINT_TO || op == GR_FILL_ARC_3POINT_TO ||
                                  op == GR_DRAW_REL_ARC_3POINT_TO;
                    p->pathTransform = (void*)0;
                }
            }

            if (!p->error) {
                result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
                arcToPen(playback, elementP);
            }
            if (op == GR_MOVE_TO || op == GR_REL_MOVE_TO || op == GR_MOVE_TO_WWFIXED) {
                GrGetCurPosWWFixed(playback, &pen);
                subStart = pen;
                subpath = TRUE;
            }
        } else if (op == GR_SAVE_STATE || op == GR_RESTORE_STATE) {
            /* The section's own saved state must not be consumed by a
             * recorded RestoreState. Coordinates remain in the PDF path. */
            if (!open || size != 1 || (op == GR_RESTORE_STATE && !depth)) {
                p->error = PDF_STATE_ERROR;
            } else if (op == GR_SAVE_STATE && depth == 31) {
                p->error = PDF_LIMIT_ERROR;
            } else {
                if (op == GR_SAVE_STATE) {
                    ++depth;
                } else {
                    --depth;
                    separatePen = TRUE; /* The kernel also restores the pen. */
                }
                result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
            }
        } else if ((op >= GR_APPLY_ROTATION && op <= GR_RESTORE_TRANSFORM) ||
                   (op >= GR_SET_MIX_MODE && op <= GR_SET_CUSTOM_TEXT_PATTERN)) {
            /* Replay captured attributes in the kernel. Painting uses the
             * caller's final attributes, not the definition's temporary ones. */
            if (region && (op == GR_SET_TRANSFORM || op == GR_SET_NULL_TRANSFORM)) {
                if (size != (op == GR_SET_TRANSFORM ? 29 : 1)) {
                    p->error = PDF_STATE_ERROR;
                } else {
                    GrSetTransform(playback, &regionBase);
                    if (op == GR_SET_TRANSFORM)
                        GrApplyTransform(playback, (const TransMatrix *)(elementP+1));
                    GrSetGStringPos(source, GSSPT_SKIP_1, 0);
                }
            } else result = GrDrawGStringAtCP(playback, source, GSC_ONE, &last);
        } else p->error = PDF_UNSUPPORTED;
        /* Preserve the rejected snapshot element for the EC warning. */
        if (p->error) {
            break;
        }
        MemFree(elementH);
        elementH = 0;
        if (result != GSRT_ONE && result != GSRT_COMPLETE) {
            p->error = PDF_STATE_ERROR;
        }
    }

    if (result == GSRT_COMPLETE) {
        complete = TRUE;
    }
    if ((!complete || open || depth || !sections) && !p->error) {
        p->error = PDF_STATE_ERROR;
    }
    if (!p->error && region) {
        regionPath(p, playback, bandOffset);
        if (!p->error && ++band < bands) {
            GrDestroyState(playback);
            playback = GrCreateState(0);
            if (!playback) {
                p->error = PDF_LIMIT_ERROR;
                goto cleanup;
            }
            sections = depth = 0;
            open = complete = FALSE;
            GrSetGStringPos(source, GSSPT_BEGINNING, 0);
            goto replay;
        }
        rule = 1; /* Native region rectangles have no overlapping interiors. */
        if (paint == 2) PdfRaw(p, "0 0 0 0 re W n\n");
    }
    if (!p->error && paint != 2) {
        /* Fills use physical coordinates. Strokes were mapped into the
         * painting state's coordinates, retaining its affine line width. */
        attributes(p, gs, paint >= 0, FALSE, paint == -1);
        PdfRaw(p, paint < 0 ? "S\n" : (rule ? "f\n" : "f*\n"));
        PdfRaw(p, "Q\n");
    }

cleanup:
    /* These are borrowed or temporary resources, never owned by the job. */
    p->pathTransform = (void*)0;
#ifndef PDF_HOST_TEST
    if (p->error && elementH) {
        EC_WARNING(0x5048); /* PDF_PATH_TRANSLATION_FAILED: retain the element. */
    }
#endif
    if (elementH) {
        MemFree(elementH);
    }
    if (playback) {
        if (region && open) {
            while (depth) {
                GrRestoreState(playback);
                --depth;
            }
            GrEndPath(playback);
        }
        GrDestroyState(playback);
    }
    if (source) {
        GrDestroyGString(source, 0, GSKT_LEAVE_DATA);
    }
    if (pathH) {
        MemFree(pathH);
    }
}

/* A bitmap is one logical output element with zero or more follow-on slices.
 * Kernel bitmap playback consumes those slices via a callback, so we must
 * advance them explicitly instead of calling GrDrawGStringAtCP on the bitmap.
 * Retain one serialized slice, plus a palette/packed mask-row block (<=8240
 * bytes). No full image or color scanline buffer is needed. Compressed rows
 * use a separate 128-/1152-byte workspace. */
/***********************************************************************
 *
 * FUNCTION:    bitmap
 *
 * DESCRIPTION: Translate a GEOS bitmap and its slices.
 *
 * PARAMETERS:  p = context; gs = state; string = GString.
 *
 * STRATEGY:    Read bounded bitmap slices and emit image rows.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Do not allocate a complete image buffer.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

static void bitmap(PdfDocument *p, GStateHandle gs, GStateHandle string, byte op)
{
    PdfBitmapSlice s, first;
    PdfBitmapReader reader;
    PdfImage image;
    TransMatrix t;
    PdfFixed m[6], width, height;
    MemHandle block = 0, auxH = 0, workspaceH = 0;
    byte *b, *paletteP, *workspaceP = (void*)0;
    const byte *row;
    word size, prefix, i, error, rowBytes, maskBytes, paletteBytes;
    dword rgb;
    XYValueAsDWord cp = GrGetCurPos(gs);
    int x = (sword)(word)cp, y = (sword)(word)(cp >> 16);
    Boolean initial = TRUE, fill = op == GR_FILL_BITMAP || op == GR_FILL_BITMAP_CP;

    /* The first bitmap implementation supports COPY with an opaque area. */
    if (GrGetMixMode(gs) != MM_COPY || GrGetAreaMask(gs, (void*)0) != SDM_100) {
        p->error = PDF_UNSUPPORTED;
        return;
    }
    /* A bitmap can span multiple serialized records in the GString. */
    while (!p->error) {
        GrGetGStringElement(gs, string, 0, (void *)0, &size);
        if (!size) {
            p->error = PDF_STATE_ERROR;
            break;
        }

        if (size > 32760) {
            p->error = PDF_LIMIT_ERROR;
            break;
        }

        block = MemAlloc(size, HF_DYNAMIC, HAF_LOCK);
        if (!block) {
            p->error = PDF_LIMIT_ERROR;
            break;
        }

        b = MemDeref(block);
        GrGetGStringElement(gs, string, size, b, &size);
        prefix = initial && (op == GR_DRAW_BITMAP || op == GR_FILL_BITMAP) ? 7 : 3;
        if (size < prefix || b[0] != (initial ? op : GSE_BITMAP_SLICE) ||
            u16(b + prefix - 2) != size - prefix) {
                p->error = PDF_STATE_ERROR;
            break;
            }
        error = PdfBitmapReaderOpen(&reader, b + prefix, (word)(size - prefix));
        if (error) {
            p->error = error;
            break;
        }

        s = reader.slice;
        /* Only the first slice determines the common image geometry. */
        if (initial) {
            if (s.firstRow) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            if (fill && s.image.format != PDF_IMAGE_STENCIL1) {
                p->error = PDF_UNSUPPORTED;
                break;
            }

            first = s;
            if (prefix == 7) {
                x = s16(b+1);
                y = s16(b+3);
            }

            error = PdfBitmapExtent(s.image.width, s.xDpi, &width);
            if (!error) {
                error = PdfBitmapExtent(s.image.height, s.yDpi, &height);
            }
            if (error) {
                p->error = error;
                break;
            }

            GrGetTransform(gs, &t);
            if (!matrix(p, &t, m)) {
                break;
            }
            PdfRaw(p, "q\n");
            clipPaths(p, gs);
            if (p->error) {
                break;
            }
            PdfApplyPageMatrix(p);
            for (i = 0; i < 6; ++i) {
                PdfNumber(p, m[i]);
            }
            PdfRaw(p, "cm\n");
            /* GEOS DrawBitmap's mono foreground is black; FillBitmap uses
             * area color. In both cases zero source bits remain transparent. */
            if (s.image.format == PDF_IMAGE_STENCIL1)
                PdfColor(p, fill ? GrGetAreaColor(gs) : 0, 0);
            maskBytes = s.image.masked ? (word)(((dword)s.image.width + 7) / 8) : 0;
            paletteBytes = s.image.paletteEntries * 3;
            if (maskBytes || paletteBytes) {
                auxH = MemAlloc(maskBytes + paletteBytes, HF_DYNAMIC,
                                    HAF_ZERO_INIT | HAF_LOCK);
                if (!auxH) {
                    p->error = PDF_LIMIT_ERROR;
                    break;
                }

                paletteP = MemDeref(auxH);
                if (s.image.palette) {
                    for (i = 0; i < s.image.paletteEntries * 3; ++i)
                        paletteP[i] = s.image.palette[i];
                } else {
                    /* No bitmap palette means the system's default colors,
                     * independent of a window's current custom palette. */
                    for (i = 0; i < s.image.paletteEntries; ++i) {
                        rgb = GrMapColorIndex(0, i);
                        paletteP[i*3] = (byte)rgb;
                        paletteP[i*3+1] = (byte)(rgb >> 8);
                        paletteP[i*3+2] = (byte)(rgb >> 16);
                    }
                }

                if (paletteBytes) {
                    s.image.palette = paletteP;
                }
            }

            if (s.compact) {
                workspaceH = MemAlloc(s.compact == 2 ? PDF_BITMAP_WORKSPACE : PDF_BITMAP_CHUNK,
                                     HF_DYNAMIC, HAF_ZERO_INIT | HAF_LOCK);
                if (!workspaceH) {
                    p->error = PDF_LIMIT_ERROR;
                    break;
                }

                workspaceP = MemDeref(workspaceH);
            }

            if (s.image.masked)
                PdfImageBeginMasked(p, &image, &s.image, x, y, width, height, paletteP + paletteBytes);
            else {
                PdfImageBegin(p, &image, &s.image, x, y, width, height);
            }
            first.image.palette = (void*)0;
            if (prefix == 7) {
                GrMoveTo(gs, x, y);
            }
        } else if (!s.complex || !s.rows || s.firstRow != image.rows ||
                   s.image.width != first.image.width || s.image.height != first.image.height ||
                   s.image.format != first.image.format || s.image.masked != first.image.masked ||
                   s.compact != first.compact ||
                   s.xDpi != first.xDpi || s.yDpi != first.yDpi) {
                       p->error = PDF_STATE_ERROR;
            break;
        }

        if (!initial && s.image.palette) {
            /* ATTENTION: a changing palette needs separate image pieces or
             * RGB conversion. Repeated identical palettes are supported. */
            if (s.image.paletteEntries != first.image.paletteEntries) {
                p->error = PDF_UNSUPPORTED;
                break;
            }

            for (i = 0; i < s.image.paletteEntries * 3; ++i)
                if (s.image.palette[i] != paletteP[i]) {
                    p->error = PDF_UNSUPPORTED;
                }
            if (p->error) {
                break;
            }
        }
        /* Decode bounded row chunks directly into the inline-image writer. */
        while (reader.row < s.rows && !p->error) {
            error = s.compact ? PdfBitmapNextChunk(&reader, workspaceP, &row, &rowBytes) :
                                PdfBitmapNextRow(&reader, &row, &rowBytes);
            if (error) {
                p->error = error;
            } else if (s.compact) {
                PdfImageRowPart(p, &image, row, rowBytes);
            } else {
                PdfImageRow(p, &image, row, rowBytes);
            }
        }

        MemFree(block);
        block = 0;
        if (p->error) {
            break;
        }
        GrSetGStringPos(string, GSSPT_SKIP_1, 0);
        if (image.rows == image.spec.height) {
            PdfImageEnd(p, &image);
            PdfRaw(p, "Q\n");
            break;
        }

        if (!first.complex) {
            p->error = PDF_STATE_ERROR;
            break;
        }

        initial = FALSE;
    }

    if (workspaceH) {
        MemFree(workspaceH);
    }
    if (auxH) {
        MemFree(auxH);
    }
    if (block) {
        MemFree(block);
    }
}

/***********************************************************************
 *
 * FUNCTION:    PDFGSTRING
 *
 * DESCRIPTION: Translate a GString to the current PDF page.
 *
 * PARAMETERS:  h = context; string = GString; flags = control.
 *
 * STRATEGY:    Keep transforms in kernel playback and translate records.
 *
 * KNOWN BUGS/SIDE EFFECTS/CAVEATS/IDEAS:
 *              Stop at page boundary or error.
 *
 * REVISION HISTORY:
 *      Codex/MeyerK 11/07/26 Document routine.
 *
 ***********************************************************************/

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

#ifndef PDF_HOST_TEST
    EC_WARNING(0x5045); /* PDF_TRANSLATION_STARTED: one message per page. */
#endif
    (void)flags; /* PDL contract always ends at a physical page boundary. */
    if (!p->inPage || !p->transformed) {
        p->error = PDF_STATE_ERROR;
    }
    PdfRaw(p, "q\n");
    /* Prime playback before extracting an element: establishes the kernel's
     * default transform at origin, including when the first output is a bitmap.
     * No element is ready yet, so GSC_ONE stops BEFORE the first operation. */
    result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
    if (result != GSRT_ONE && result != GSRT_COMPLETE) {
        p->error = PDF_STATE_ERROR;
    }
    while (!p->error && result != GSRT_COMPLETE) {
        op = GrGetGStringElement(gs, string, 0, (void *)0, &size);
        if (!size) {
            p->error = PDF_STATE_ERROR;
            break;
        }

        if (op == GR_END_GSTRING || op == GR_NEW_PAGE) {
            if (op == GR_NEW_PAGE) {
                GrSetGStringPos(string, GSSPT_SKIP_1, 0);
            }
            result = op == GR_NEW_PAGE ? GSRT_NEW_PAGE : GSRT_COMPLETE;
            break;
        }

        if (op == GR_DRAW_BITMAP || op == GR_DRAW_BITMAP_CP ||
            op == GR_FILL_BITMAP || op == GR_FILL_BITMAP_CP) {
            if (definingPath) {
                p->error = PDF_UNSUPPORTED;
                break;
            }

            bitmap(p, gs, string, op);
            continue;
        }

        /* Mirror kernel save/restore nesting in the PDF graphics stack. */
        if (op == GR_SAVE_STATE) {
            if (depth == 31) {
                p->error = PDF_LIMIT_ERROR;
                break;
            }

            ++depth;
            PdfRaw(p, "q\n");
        } else if (op == GR_RESTORE_STATE) {
            if (!depth) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            --depth;
            PdfRaw(p, "Q\n");
        } else if (op == GR_BEGIN_PATH) {
            if (definingPath || size != 5) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+1) > PCT_INTERSECTION) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            definingPath = u16(control+1) != PCT_NULL;
        } else if (op == GR_END_PATH) {
            if (size != 1) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            definingPath = FALSE;
        } else if (op == GR_CLOSE_SUB_PATH) {
            if (!definingPath || size != 1) {
                p->error = PDF_STATE_ERROR;
                break;
            }
        } else if (op == GR_SET_CLIP_RECT || op == GR_SET_WIN_CLIP_RECT) {
            if (definingPath || size != 11) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+1) > PCT_INTERSECTION) {
                p->error = PDF_STATE_ERROR;
                break;
            }
        } else if (op == GR_SET_CLIP_PATH || op == GR_SET_WIN_CLIP_PATH) {
            if (definingPath || size != 4) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, control, &size);
            if (u16(control+2) > PCT_INTERSECTION ||
                (u16(control+2) != PCT_NULL && control[1] > 1)) {
                    p->error = PDF_STATE_ERROR;
                break;
            }
        } else if (op == GR_SET_LINE_STYLE) {
            if (size != 3) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, control, &size);
            if (control[1] > LS_DASHDDOT || control[2] > 127 ||
                (control[1] != LS_SOLID && control[2] >
                    (control[1] == LS_DOTTED ? 3 : 8))) {
                        p->error = PDF_STATE_ERROR;
                break;
            }
        } else if (op == GR_SET_CUSTOM_LINE_STYLE) {
            if (size < 7 || size > sizeof(control)) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, control, &size);
            n = u16(control+3);
            if (!n || n > 5 || size != 5 + n * 2 || u16(control+1) > 127 ||
                u16(control+1) > (byte)(control[5] + control[6])) {
                    p->error = PDF_STATE_ERROR;
                break;
            }

            for (n = 5; n < size; ++n) if (!control[n]) p->error = PDF_STATE_ERROR;
            if (p->error) {
                break;
            }
        } else if (op == GR_SET_AREA_PATTERN || op == GR_SET_TEXT_PATTERN) {
            if (size != sizeof(pattern)) {
                p->error = PDF_STATE_ERROR;
                break;
            }

            GrGetGStringElement(gs, string, size, pattern, &size);
            /* PT_SOLID ignores the data byte; playback maintains the GState. */
            if (pattern[1] != PT_SOLID) {
                p->error = PDF_UNSUPPORTED;
                break;
            }
        } else if (op >= GR_BEGIN_PATH || op == GR_ESCAPE ||
                   op == GR_SET_CUSTOM_AREA_PATTERN ||
                   op == GR_SET_CUSTOM_TEXT_PATTERN) {
                       p->error = PDF_UNSUPPORTED;
            break;
        }

        if (op >= GR_DRAW_LINE && op <= GR_OUTPUT_5F) {
            if (size > 32760) {
                p->error = PDF_LIMIT_ERROR;
                break;
            }

            element = MemAlloc(size, HF_DYNAMIC, HAF_LOCK);
            if (!element) {
                p->error = PDF_LIMIT_ERROR;
                break;
            }

            b = MemDeref(element);
            GrGetGStringElement(gs, string, size, b, &size);
            if (definingPath) {
                p->error = geometrySize(b, size);
            } else {
                output(p, gs, b, size, FALSE, (void*)0);
            }
            /* Keep a rejected record alive for the EC warning below. */
            if (p->error) {
                break;
            }
        }

        result = GrDrawGStringAtCP(gs, string, GSC_ONE, &last);
        if (element) {
            if (!definingPath) {
                arcToPen(gs, b);
            }
            MemFree(element);
            element = 0;
        }

        if (result != GSRT_ONE && result != GSRT_COMPLETE) {
            p->error = PDF_STATE_ERROR;
            break;
        }
        /* COMPLETE restores the kernel transform and rewinds the source.
         * Stop here; another extraction would repeat the document forever. */
    }

    if ((depth || definingPath) && !p->error) {
        p->error = PDF_STATE_ERROR;
    }
    PdfRaw(p, "Q\n");
    if (p->error) {
#ifndef PDF_HOST_TEST
        EC_WARNING(0x5044); /* PDF translation failed; inspect op and p->error. */
#endif
        result = GSRT_FAULT;
    }

    if (element) {
        MemFree(element);
    }
    /* An unfinished definition still owns a kernel path GString. GrEndPath
     * releases it and restores the saved GState before GrDestroyState. */
    if (definingPath) {
        GrEndPath(gs);
    }
    GrDestroyState(gs);
#ifndef PDF_HOST_TEST
    if (!p->error) {
        EC_WARNING(0x5046); /* PDF_TRANSLATION_FINISHED. */
    }
#endif
    MemUnlock(h);
    return result;
}
