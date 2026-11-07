/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     PDF Host Regression Tests
FILE:       geosmock.h

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    MockSegment - Map test pointers to mock GEOS segments
    GrCreateState - Simulated graphics state API

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Define the minimal packed GEOS ABI types used by the host tests.
    Native compilation uses the real GEOS headers instead.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Minimal GEOS ABI test double. Native compilation uses the real CInclude.
 * Wire structures are packed exactly like Watcom -zp1, never host enums. */
#ifndef PDF_GEOS_MOCK_H
#define PDF_GEOS_MOCK_H
#include <stdint.h>
#include <stddef.h>
#define _pascal
#define _export
typedef uint8_t byte;
typedef uint16_t word, MemHandle, GStateHandle;
typedef int16_t sword, Boolean;
typedef uint32_t dword, WWFixedAsDWord, XYValueAsDWord;
typedef int32_t sdword;
typedef byte DrawMask[8];
typedef struct { byte HP_type, HP_data; } GraphicPattern;
#define FG_SERIF 0x0000
#define FG_SANS_SERIF 0x0200
#define FG_SYMBOL 0x0800
#define FG_MONO 0x0a00
#define FID_PS_SYMBOL 0x2800
#define TRUE 1
#define FALSE 0
#define HF_DYNAMIC 0
#define HAF_ZERO_INIT 1
#define HAF_LOCK 2
#pragma pack(push, 1)
typedef struct { word WWF_frac; sword WWF_int; } WWFixed;
typedef struct { byte WBF_frac; sword WBF_int; } WBFixed;
typedef struct { word DWF_frac; sdword DWF_int; } DWFixed;
typedef struct { WWFixed PF_x, PF_y; } PointWWFixed;
typedef struct { DWFixed PDF_x, PDF_y; } PointDWFixed;
typedef struct {
    WWFixed TM_e11, TM_e12, TM_e21, TM_e22;
    DWFixed TM_e31, TM_e32;
} TransMatrix;
typedef struct {
    byte color[4], mask, pattern[2], styleSet, styleClear, modeSet, modeClear;
    WBFixed space; word font; WBFixed size; sword kern; byte weight, width;
} TextAttr;
#pragma pack(pop)
#define GPT_CURRENT 0
#define GPT_CLIP 1
#define GPT_WIN_CLIP 2
#define GST_PTR 0
#define GST_CHUNK 1
#define LMEM_TYPE_GENERAL 0
#define GR_COMMENT 1
#define GSET_NO_ERROR 0
#define GSKT_LEAVE_DATA 0
#define GR_APPLY_ROTATION 16
#define GR_APPLY_TRANSFORM 19
#define GR_SET_TRANSFORM 21
#define GR_SET_NULL_TRANSFORM 22
#define EOREGREC 0x8000
#define ODD_EVEN 0
#define MGIT_SIZE 0
#define GR_RESTORE_TRANSFORM 26
#define GR_REL_MOVE_TO 100
#define GR_DRAW_PATH 65
#define GR_FILL_PATH 73
#define GR_END_PATH 161
#define GR_SET_WIN_CLIP_RECT 163
#define GR_CLOSE_SUB_PATH 164
#define GR_SET_CLIP_PATH 165
#define GR_SET_WIN_CLIP_PATH 166
word MockSegment(const void *p);
#define PtrToSegment(p) MockSegment(p)
#define PtrToOffset(p) ((word)0)
Boolean GrTestPath(GStateHandle gs, word type);
MemHandle GrGetPath(GStateHandle gs, word type);
GStateHandle GrLoadGString(word segment, byte type, word offset);
void GrDestroyGString(GStateHandle string, GStateHandle gs, byte type);
void GrSetNullTransform(GStateHandle gs);
void GrSetTransform(GStateHandle gs, const TransMatrix *t);
void GrTransformDWFixed(GStateHandle gs, PointDWFixed *point);
void GrUntransformDWFixed(GStateHandle gs, PointDWFixed *point);
void GrEndPath(GStateHandle gs);
void GrBeginPath(GStateHandle gs, word combine);
void GrSetClipPath(GStateHandle gs, word combine, word rule);
void GrApplyTransform(GStateHandle gs, const TransMatrix *t);
void GrInitDefaultTransform(GStateHandle gs);
MemHandle GrGetClipRegion(GStateHandle gs, word rule);
word MemGetInfo(MemHandle h, word info);
void GrSaveState(GStateHandle gs);
void GrRestoreState(GStateHandle gs);
#define SDM_0      89
#define SDM_100    25
#define MM_COPY 1
#define LS_SOLID 0
#define LS_DASHED 1
#define LS_DOTTED 2
#define LS_DASHDOT 3
#define LS_DASHDDOT 4
#define LS_CUSTOM 5
#define GR_SET_LINE_STYLE 113
#define GR_SET_LINE_WIDTH 108
#define PT_SOLID 0
#define PT_CUSTOM_HATCH 5
#define PT_CUSTOM_BITMAP 6
#define TS_BOLD		0x20
#define TS_ITALIC	0x10
#define TS_UNDERLINE 0x01
#define TS_STRIKE_THRU 0x02
#define TS_SUPERSCRIPT 0x08
#define TS_SUBSCRIPT 0x04
#define C_NONBRKHYPHEN 0x1e
#define C_OPTHYPHEN 0x1f
#define TM_DRAW_OPTIONAL_HYPHENS 0x01
#define TM_DRAW_BASE			0x08
#define TM_DRAW_BOTTOM			0x04
#define TM_DRAW_ACCENT			0x02
#define GR_END_GSTRING 0
#define GR_ESCAPE 14
#define GR_NEW_PAGE 15
#define GR_DRAW_LINE 32
#define GR_DRAW_LINE_TO 33
#define GR_DRAW_REL_LINE_TO 34
#define GR_DRAW_SPLINE 48
#define GR_DRAW_SPLINE_TO 49
#define GR_BRUSH_POLYLINE 57
#define GR_DRAW_POINT 55
#define GR_DRAW_POINT_CP 56
#define GR_DRAW_ARC_3POINT 41
#define GR_DRAW_ARC_3POINT_TO 42
#define GR_DRAW_REL_ARC_3POINT_TO 43
#define GR_FILL_ARC_3POINT 74
#define GR_FILL_ARC_3POINT_TO 75
#define GR_DRAW_ARC 40
#define GR_FILL_ARC 70
#define ACT_OPEN 0
#define ACT_CHORD 1
#define ACT_PIE 2
#define GR_DRAW_REL_CURVE_TO 52
#define GR_DRAW_HLINE 35
#define GR_DRAW_HLINE_TO 36
#define GR_DRAW_VLINE 37
#define GR_DRAW_VLINE_TO 38
#define GR_DRAW_POLYLINE 39
#define GR_DRAW_RECT 44
#define GR_DRAW_ELLIPSE 53
#define GR_FILL_ELLIPSE 72
#define GR_DRAW_RECT_TO 45
#define GR_DRAW_ROUND_RECT 46
#define GR_DRAW_ROUND_RECT_TO 47
#define GR_DRAW_CURVE 50
#define GR_DRAW_CURVE_TO 51
#define GR_DRAW_POLYGON 54
#define GR_DRAW_CHAR 58
#define GR_DRAW_CHAR_CP 59
#define GR_DRAW_TEXT 60
#define GR_DRAW_TEXT_CP 61
#define GR_DRAW_TEXT_FIELD 62
#define GR_FILL_RECT 66
#define GR_FILL_RECT_TO 67
#define GR_FILL_ROUND_RECT 68
#define GR_FILL_ROUND_RECT_TO 69
#define GR_FILL_POLYGON 71
#define GR_FILL_BITMAP 76
#define GR_FILL_BITMAP_CP 77
#define GR_DRAW_BITMAP 80
#define GR_DRAW_BITMAP_CP 81
#define GSE_BITMAP_SLICE 84
#define GR_OUTPUT_5F 95
#define GR_SAVE_STATE 96
#define GR_RESTORE_STATE 97
#define GR_SET_MIX_MODE 98
#define GR_MOVE_TO 99
#define GR_SET_CUSTOM_LINE_STYLE 116
#define GR_SET_TEXT_ATTR 131
#define GR_MOVE_TO_WWFIXED 142
#define GR_SET_AREA_PATTERN 123
#define GR_SET_CUSTOM_AREA_PATTERN 124
#define GR_SET_TEXT_PATTERN 140
#define GR_SET_CUSTOM_TEXT_PATTERN 141
#define GR_BEGIN_PATH 160
#define GR_SET_CLIP_RECT 162
#define GSC_ONE			0x0100
#define GSC_NEW_PAGE		0x0010
#define GSSPT_SKIP_1 0
#define GSSPT_BEGINNING 2
#define GSRT_COMPLETE 0
#define GSRT_ONE 1
#define GSRT_NEW_PAGE 5
#define GSRT_FAULT 0xffff
#define PCT_NULL 0
#define PCT_REPLACE 1
#define PCT_UNION 2
#define PCT_INTERSECTION 3
#define GFMI_HEIGHT 0
#define GFMI_BASELINE 6
#define GFMI_UNDER_POS 18
#define GFMI_UNDER_THICKNESS 20
#define GFMI_STRIKE_POS 36
#define GFMI_ACCENT 24
MemHandle MemAlloc(word size, word flags, word allocFlags);
MemHandle MemAllocLMem(word type, word header);
GStateHandle GrCreateGString(MemHandle block, byte type, word *chunk);
word GrEndGString(GStateHandle gs);
void GrSetFont(GStateHandle gs, word font, dword size);
void GrSetTextStyle(GStateHandle gs, byte set, byte clear);
word GrGetFontWeight(GStateHandle gs);
word GrGetFontWidth(GStateHandle gs);
void GrSetFontWeight(GStateHandle gs, word weight);
void GrSetFontWidth(GStateHandle gs, word width);
void GrApplyTranslation(GStateHandle gs, dword x, dword y);
void GrApplyScale(GStateHandle gs, dword x, dword y);
void *MemLock(MemHandle h);
void *MemDeref(MemHandle h);
void MemUnlock(MemHandle h);
void MemFree(MemHandle h);
GStateHandle GrCreateState(word window);
void GrDestroyState(GStateHandle gs);
void GrGetTransform(GStateHandle gs, TransMatrix *t);
dword GrGetLineColor(GStateHandle gs);
dword GrGetAreaColor(GStateHandle gs);
dword GrGetTextColor(GStateHandle gs);
dword GrMapColorIndex(GStateHandle gs, byte index);
dword GrGetLineWidth(GStateHandle gs);
word GrGetLineEnd(GStateHandle gs);
word GrGetLineJoin(GStateHandle gs);
dword GrGetMiterLimit(GStateHandle gs);
word GrGetMixMode(GStateHandle gs);
word GrGetLineStyle(GStateHandle gs);
word GrGetLineMask(GStateHandle gs, DrawMask *mask);
word GrGetAreaMask(GStateHandle gs, DrawMask *mask);
word GrGetTextMask(GStateHandle gs, DrawMask *mask);
word GrGetFont(GStateHandle gs, dword *size);
word GrGetTextStyle(GStateHandle gs);
word GrGetTextMode(GStateHandle gs);
dword GrFontMetrics(GStateHandle gs, word type);
dword GrCharWidth(GStateHandle gs, word ch);
word GrTextWidth(GStateHandle gs, const char *text, word count);
void GrSetTextAttr(GStateHandle gs, const TextAttr *attr);
dword GrGetCurPos(GStateHandle gs);
void GrGetCurPosWWFixed(GStateHandle gs, PointWWFixed *point);
byte GrGetGStringElement(GStateHandle gs, GStateHandle string, word size,
                        void *buffer, word *actual);
void GrSetGStringPos(GStateHandle string, byte type, word skip);
word GrDrawGStringAtCP(GStateHandle gs, GStateHandle string, word flags, word *last);
void GrTransformWWFixed(GStateHandle gs, dword x, dword y, PointWWFixed *point);
void GrMoveTo(GStateHandle gs, sword x, sword y);
void GrMoveToWWFixed(GStateHandle gs, dword x, dword y);
#endif
