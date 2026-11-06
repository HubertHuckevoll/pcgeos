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
typedef struct {
    WWFixed TM_e11, TM_e12, TM_e21, TM_e22;
    DWFixed TM_e31, TM_e32;
} TransMatrix;
typedef struct {
    byte color[4], mask, pattern[2], styleSet, styleClear, modeSet, modeClear;
    WBFixed space; word font; WBFixed size; sword kern; byte weight, width;
} TextAttr;
#pragma pack(pop)
#define SDM_100    25
#define MM_COPY 1
#define LS_SOLID 0
#define TS_BOLD		0x20
#define TS_ITALIC	0x10
#define TM_DRAW_BASE			0x08
#define TM_DRAW_BOTTOM			0x04
#define TM_DRAW_ACCENT			0x02
#define GR_END_GSTRING 0
#define GR_ESCAPE 14
#define GR_NEW_PAGE 15
#define GR_DRAW_LINE 32
#define GR_DRAW_LINE_TO 33
#define GR_DRAW_HLINE 35
#define GR_DRAW_HLINE_TO 36
#define GR_DRAW_VLINE 37   
#define GR_DRAW_VLINE_TO 38
#define GR_DRAW_POLYLINE 39
#define GR_DRAW_RECT 44
#define GR_DRAW_RECT_TO 45
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
#define GR_FILL_POLYGON 71
#define GR_OUTPUT_5F 95
#define GR_SAVE_STATE 96
#define GR_RESTORE_STATE 97
#define GR_MOVE_TO 99     
#define GR_SET_CUSTOM_LINE_STYLE 116
#define GR_SET_AREA_PATTERN 123
#define GR_SET_CUSTOM_AREA_PATTERN 124
#define GR_SET_TEXT_PATTERN 140  
#define GR_SET_CUSTOM_TEXT_PATTERN 141
#define GR_BEGIN_PATH 160
#define GR_SET_CLIP_RECT 162
#define GSC_ONE			0x0100
#define GSC_NEW_PAGE		0x0010
#define GSSPT_SKIP_1 0
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
#define GFMI_ACCENT 24
MemHandle MemAlloc(word size, word flags, word allocFlags);
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
word GrTextWidth(GStateHandle gs, const char *text, word count);
void GrSetTextAttr(GStateHandle gs, const TextAttr *attr);
dword GrGetCurPos(GStateHandle gs);
byte GrGetGStringElement(GStateHandle gs, GStateHandle string, word size,
                        void *buffer, word *actual);
void GrSetGStringPos(GStateHandle string, byte type, word skip);
word GrDrawGStringAtCP(GStateHandle gs, GStateHandle string, word flags, word *last);
void GrTransformWWFixed(GStateHandle gs, dword x, dword y, PointWWFixed *point);
#endif
