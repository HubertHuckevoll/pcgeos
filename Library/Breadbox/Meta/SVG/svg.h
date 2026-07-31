/*--------------------------------------------------------------------
 * svg.h - Master public header for the Meta SVG renderer (GEOS/GOC)
 *------------------------------------------------------------------*/

#include <xlatLib.h>

/* ---- global compile-time constants ---- */
#define SVG_COLOR_NAME_LEN   32
#define SVG_IO_BUF_SIZE             1024
#define SVG_TEXT_INITIAL_SIZE       1024
#define SVG_TEXT_MAX_SIZE           8192
#define SVG_POINTS_INITIAL_CAPACITY 128
#define MAX_SVG_POINTS              4096

/* Convenient 16.16 one */
#define WWFIXED_ONE      ((WWFixedAsDWord)(1UL << 16))

/* WWFixed add/sub helpers (C89 macro style, used across modules) */
#ifndef SVG_WWFIX_ADD_SUB_DEFINED
#define SVG_WWFIX_ADD_SUB_DEFINED
#define GrAddWWFixed(a,b) ((WWFixedAsDWord)((sdword)(a) + (sdword)(b)))
#define GrSubWWFixed(a,b) ((WWFixedAsDWord)((sdword)(a) - (sdword)(b)))
#endif

/* ATTENTION: SVG groups are limited to 16 levels to bound heap use.
 * Replace the fixed stacks with growable blocks if deeper input is needed.
 */
#define SVG_GROUP_NESTING_MAX 16

/* ---- transform stack (CTM) size ---- */
#define SVG_XFORM_GSTACK_MAX 16

/* ---- group style stack (fill/stroke/stroke-width) ---- */
#define SVG_STYLE_GSTACK_MAX 17 /* root style plus 16 nested groups */
#define SVG_STYLE_APPROX_JOIN_SEG_THRESHOLD 12

/* per-group style state */
typedef struct {
    Boolean         fillSet, strokeSet, swSet;
    char            fillVal[64], strokeVal[64];
    WWFixedAsDWord  strokeWidth;
    Boolean         frSet;  byte fr;      /* 0=nonzero, 1=evenodd */
    Boolean         lcSet;  byte lc;      /* 0=butt, 1=round, 2=square */
    Boolean         ljSet;  byte lj;      /* 0=miter, 1=round, 2=bevel */
    Boolean         mlSet;  WWFixedAsDWord miterLimit; /* stroke-miterlimit */
    Boolean         colorSet;             /* CSS color property (for currentColor) */
    char            colorVal[64];
    Boolean         visible;
} SvgGroupStyle;

typedef enum {
    SVG_SCRATCH_OK,
    SVG_SCRATCH_ALLOCATION_FAILED,
    SVG_SCRATCH_LIMIT_EXCEEDED
} SvgScratchFailure;

/* ---- shared data types ---- */
typedef struct {
    byte SNC_r;
    byte SNC_g;
    byte SNC_b;
    char SNC_name[SVG_COLOR_NAME_LEN + 1];   /* NUL-terminated */
} SvgNamedColor;

/* WWPoint in 16.16 */
typedef struct {
    WWFixedAsDWord x;
    WWFixedAsDWord y;
} SvgWWPoint;

/* SVG 2x3 affine matrix in user units: [a c e; b d f] */
typedef struct {
    WWFixedAsDWord a, b, c, d, e, f;
} SvgMatrix;

/* All sizeable scratch buffers kept on heap to keep stack tiny */
typedef struct _SVGScratch {
    MemHandle   tagH;
    char       *tagP;
    word        tagCapacity;

    MemHandle   dbH;
    char       *dbP;
    word        dbCapacity;

    MemHandle   ptsH;
    Point      *ptsP;
    word        ptsCapacity;

    MemHandle   ptsWWFH;
    SvgWWPoint *ptsWWFP;
    word        ptsWWFCapacity;

    SvgScratchFailure failure;
    Boolean     unsupportedElement;
} SVGScratch;

typedef struct {
    MemHandle  ioH;
    char      *ioP;
    word       bytes;
    word       pos;
    Boolean    inTag;
    Boolean    inQuote;
    char       quoteCh;
    word       tagLen;
} SvgScanCtx;

typedef enum {
    SVG_SCAN_TAG,
    SVG_SCAN_EOF,
    SVG_SCAN_TRUNCATED,
    SVG_SCAN_IO_ERROR,
    SVG_SCAN_NO_INPUT,
    SVG_SCAN_OUT_OF_MEMORY,
    SVG_SCAN_LIMIT_EXCEEDED
} SvgScanResult;

typedef enum {
    SVG_ATTR_MISSING,
    SVG_ATTR_VALID,
    SVG_ATTR_MALFORMED,
    SVG_ATTR_TOO_LONG
} SvgAttrResult;

/* ---- parser-layer (raw text scan) ---- */
const char* SvgParserSkipWS(const char *p);
const char* SvgParserSkipCommaWS(const char *p);
Boolean     SvgParserTagIs(const char *tag, const char *name);
Boolean     SvgParserGetAttrBounded(const char *tag, const char *name,
                                    char *out, word outSize);
SvgAttrResult SvgParserGetAttrSpan(const char *tag, const char *name,
                                   const char **valuePP, word *lengthP,
                                   word maximumBytes);
void        SvgParserScanInit(SvgScanCtx *c);
SvgScanResult SvgParserScanNextTag(FileHandle fh, SvgScanCtx *c,
                                   SVGScratch *sc);
Boolean     SvgParseGetInlineStyleProp(const char *tag, const char *prop,
                                       char *out, word outSize);

Boolean     SvgScratchInit(SVGScratch *sc);
void        SvgScratchFree(SVGScratch *sc);
Boolean     SvgScratchEnsureTagCapacity(SVGScratch *sc, word neededBytes);
Boolean     SvgScratchEnsurePathBuf(SVGScratch *sc, word neededBytes);
Boolean     SvgScratchEnsurePointCapacity(SVGScratch *sc, word neededPoints);
Boolean     SvgScratchEnsureWWPointCapacity(SVGScratch *sc, word neededPoints);

/* ---- small utility (common) ---- */
Boolean     SvgUtilAsciiNoCaseEq(const char *a, const char *b);
word        SvgUtilHexNibble(char c);
word        SvgUtilHexByte(const char *p);
Boolean     SvgUtilExpandShortHex(const char *s, word *r, word *g, word *b);
Boolean     SvgUtilParseRGBFunc(const char *s, word *r, word *g, word *b);
Boolean     SvgUtilKeyEqNoCase(const char *kb, const char *ke, const char *prop);
const char* SvgUtilParseWWFixed16_16(const char *s, WWFixedAsDWord *out);
Boolean     SvgUtilIsNumStart(char c);

/* ---- geometry helpers (shared fixed-point math) ---- */
WWFixedAsDWord SvgGeomMakeWWFixedFromInt(int v);
sword          SvgGeomWWFixedToSWordRound(WWFixedAsDWord w);
WWFixedAsDWord SvgGeomWWSqrt(WWFixedAsDWord a);
WWFixedAsDWord SvgGeomWWAbs(WWFixedAsDWord x);
WWFixedAsDWord SvgGeomWWMin(WWFixedAsDWord a, WWFixedAsDWord b);
WWFixedAsDWord SvgGeomWWMax(WWFixedAsDWord a, WWFixedAsDWord b);
WWFixedAsDWord SvgGeomWWAtan2Deg(WWFixedAsDWord y, WWFixedAsDWord x);

/* ----- style stack API ------ */
Boolean SvgStyleStackInit(void);
void    SvgStyleStackFree(void);

/* ---- style (stroke/fill/colors) ---- */
void    SvgStyleApplyStrokeAndFill(const char *tag);
void    SvgStyleApplyStrokeWidth(const char *tag, const SvgMatrix *worldMP);
void    SvgStyleApplyFillRule(const char *tag);
void    SvgStyleApplyStrokeCapJoin(const char *tag);
Boolean SvgStyleHasStroke(const char *tag);
Boolean SvgStyleHasFill(const char *tag);
Boolean SvgStyleElementIsVisible(const char *tag);
Boolean SvgStyleIsLineJoinExplicit(const char *tag);
Boolean SvgStyleGroupStrokeWidthGet(WWFixedAsDWord *outW);
Boolean SvgStyleGroupMiterLimitGet(WWFixedAsDWord *outLimit);
Boolean SvgStyleForceRoundJoin(const char *tag);
Boolean SvgStyleForceRoundJoinForSegments(const char *tag, word segmentCount);
void    SvgStyleRestoreForcedJoin(const char *tag, Boolean forced);
/* groups */
Boolean SvgStyleGroupPush(const char *tag);
void    SvgStyleGroupPop(void);
#ifdef SVG_STYLE_ENABLE_SELF_TEST
Boolean SvgStyleRunSelfTest(void);
#endif

/* ---- viewBox/viewport mapping ---- */
void   SvgViewReset(void);
void   SvgViewInitFromSvgTag(const char *tag);
void   SvgViewInitDefault(void);
sword  SvgViewMapPosX_F(WWFixedAsDWord fx);
sword  SvgViewMapPosY_F(WWFixedAsDWord fy);


/* Provide the view matrix (world <- user) as SVG-style 2x3:
   x' = a*x + c*y + e;  y' = b*x + d*y + f */
void   SvgViewGetMatrix(WWFixedAsDWord *a, WWFixedAsDWord *b,
                        WWFixedAsDWord *c, WWFixedAsDWord *d,
                        WWFixedAsDWord *e, WWFixedAsDWord *f);


/* Transform layer (CTM) */
/* ---- transform layer (CTM) ---- */
Boolean SvgXformStackInit(void);
void    SvgXformStackFree(void);
void SvgXformApplyPoint(sword *xP, sword *yP, const SvgMatrix *m);
Boolean SvgXformParseAttrUser(const char *tag, SvgMatrix *outUser);
Boolean SvgXformBuildWorld(const char *tag, const SvgMatrix *parentCTM, SvgMatrix *outWorld);
Boolean SvgXformGroupPush(const char *tag);
void SvgXformGroupPop(void);
#ifdef SVG_XFORM_ENABLE_SELF_TEST
Boolean SvgXformRunSelfTest(void);
#endif

/* ---- tag handlers (dispatch targets) ---- */
Boolean SvgShapeHandleLine(const char *tag, SVGScratch *sc);
Boolean SvgShapeHandlePolyline(const char *tag, SVGScratch *sc,
                               Boolean *validP);
Boolean SvgShapeHandlePolygon(const char *tag, SVGScratch *sc,
                              Boolean *validP);
Boolean SvgShapeHandleRect(const char *tag, SVGScratch *sc);
Boolean SvgShapeHandleEllipse(const char *tag, SVGScratch *sc);
Boolean SvgShapeHandleCircle(const char *tag, SVGScratch *sc);

/* ---- tag handlers: path with subcommands ---- */
Boolean SvgPathHandle(const char *tag, SVGScratch *sc, Boolean *emittedP);
static void SvgPathHandleMoveTo   (const char **sPP, char *lastCmdP,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   WWFixedAsDWord *subStartXWP, WWFixedAsDWord *subStartYWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleLineTo   (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleHLineTo  (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleVLineTo  (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleQuadratic(const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                   WWFixedAsDWord *lastQcxWP, WWFixedAsDWord *lastQcyWP);
static void SvgPathHandleSmoothQuadratic(const char **sPP, char lastCmd,
                                         SVGScratch *sc, word *npP,
                                         WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                         Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                         WWFixedAsDWord *lastQcxWP, WWFixedAsDWord *lastQcyWP);
static void SvgPathHandleCubic    (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                   WWFixedAsDWord *lastC2xWP, WWFixedAsDWord *lastC2yWP);
static void SvgPathHandleSmoothCubic(const char **sPP, char lastCmd,
                                     SVGScratch *sc, word *npP,
                                     WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                     Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                     WWFixedAsDWord *lastC2xWP, WWFixedAsDWord *lastC2yWP);
static void SvgPathHandleArc      (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleClose    (const char **sPP,
                                   Boolean *closedP,
                                   WWFixedAsDWord *lastxWP, WWFixedAsDWord *lastyWP,
                                   WWFixedAsDWord subStartXW, WWFixedAsDWord subStartYW,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleUnknown  (const char **sPP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);

/* ---- streamed parser entry ---- */
typedef Boolean _pascal ProgressCallback(word percent);
TransError _export _pascal ReadSVG(FileHandle srcFile, word settings, ProgressCallback *callback);
