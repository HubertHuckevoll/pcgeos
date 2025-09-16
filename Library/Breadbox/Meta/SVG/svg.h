/*--------------------------------------------------------------------
 * svg.h — Master public header for the Meta SVG renderer (GEOS/GOC)
 *------------------------------------------------------------------*/

#include <xlatLib.h>

/* ---- global compile-time constants ---- */
#define SVG_COLOR_NAME_LEN   32
#define MAX_SVG_POINTS       4096
#define SVG_IO_BUF_SIZE      1024
#define TAG_BUF_SIZE         8192  /* must hold entire tag */
#define MAX_PATH_ATTR_SIZE    8192   /* must hold entire attribute value - FIXME: can't be bigger or equal to tag size but is needed to be big for complex SVGs */

/* Convenient 16.16 one */
#define WWFIXED_ONE      ((WWFixedAsDWord)(1UL << 16))

/* WWFixed add/sub helpers (C89 macro style, used across modules) */
#ifndef SVG_WWFIX_ADD_SUB_DEFINED
#define SVG_WWFIX_ADD_SUB_DEFINED
#define GrAddWWFixed(a,b) ((WWFixedAsDWord)((sdword)(a) + (sdword)(b)))
#define GrSubWWFixed(a,b) ((WWFixedAsDWord)((sdword)(a) - (sdword)(b)))
#endif

/* ---- group style stack (fill/stroke/stroke-width) ---- */
#define SVG_STYLE_GSTACK_MAX 16 /* max group nesting depth */

/* per-group style state */
typedef struct {
    Boolean         fillSet, strokeSet, swSet;
    char            fillVal[64], strokeVal[64];
    WWFixedAsDWord  strokeWidth;
    Boolean         frSet;  byte fr;      /* 0=nonzero, 1=evenodd */
    Boolean         lcSet;  byte lc;      /* 0=butt, 1=round, 2=square */
    Boolean         ljSet;  byte lj;      /* 0=miter, 1=round, 2=bevel */
} SvgGroupStyle;

/* ---- shared data types ---- */
typedef struct {
    byte SNC_r;
    byte SNC_g;
    byte SNC_b;
    char SNC_name[SVG_COLOR_NAME_LEN + 1];   /* NUL-terminated */
} SvgNamedColor;

/* All sizeable scratch buffers kept on heap to keep stack tiny - fixme: put in LMemHeap or something */
typedef struct _SVGScratch {
    char    tag[TAG_BUF_SIZE];         // FIXME: make this dynamic!

    char    pb[256];
    char    db[MAX_PATH_ATTR_SIZE];   // FIXME: make this dynamic!
    char    xb[32], yb[32], x2b[32], y2b[32];
    char    wb[32], hb[32];
    char    cxb[32], cyb[32], rxb[32], ryb[32];
    char    rb[32];
    char    col[64];
    char    tbuf[96];

    Point   pts[MAX_SVG_POINTS];    // FIXME: make this dynamic!
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

/* ---- small utility (common) ---- */
Boolean SvgUtilAsciiNoCaseEq(const char *a, const char *b);
const char* SvgUtilSkipSpace(const char *p);
word    SvgUtilHexNibble(char c);
word    SvgUtilHexByte(const char *p);
Boolean SvgUtilExpandShortHex(const char *s, word *r, word *g, word *b);
Boolean SvgUtilParseRGBFunc(const char *s, word *r, word *g, word *b);
Boolean SvgUtilKeyEqNoCase(const char *kb, const char *ke, const char *prop);
Boolean SvgUtilGetInlineProp(const char *tag, const char *prop,
                             char *out, word outSize);

/* ---- geometry helpers (shared fixed-point math) ---- */
WWFixedAsDWord SvgGeomMakeWWFixedFromInt(int v);
sword          SvgGeomWWFixedToSWordRound(WWFixedAsDWord w);
WWFixedAsDWord SvgGeomWWSqrt(WWFixedAsDWord a);
WWFixedAsDWord SvgGeomWWAbs(WWFixedAsDWord x);
WWFixedAsDWord SvgGeomWWMin(WWFixedAsDWord a, WWFixedAsDWord b);
WWFixedAsDWord SvgGeomWWMax(WWFixedAsDWord a, WWFixedAsDWord b);
WWFixedAsDWord SvgGeomWWAtan2Deg(WWFixedAsDWord y, WWFixedAsDWord x);

/* ---- parser-layer helpers (raw text scan) ---- */
const char* SvgParserSkipWS(const char *s);
const char* SvgParserParseWWFixed16_16(const char *s, WWFixedAsDWord *out);
Boolean     SvgParserTagIs(const char *tag, const char *name);
Boolean     SvgParserGetAttrBounded(const char *tag, const char *name,
                                    char *out, word outSize);
void        SvgParserScanInit(SvgScanCtx *c);
Boolean     SvgParserScanNextTag(FileHandle fh, SvgScanCtx *c,
                                 SVGScratch *sc);

/* ----- style stack API ------ */
Boolean SvgStyleStackInit(void);
void    SvgStyleStackFree(void);

/* ---- style (stroke/fill/colors) ---- */
void    SvgStyleApplyStrokeAndFill(const char *tag);
void    SvgStyleApplyStrokeWidth(const char *tag);
void    SvgStyleApplyFillRule(const char *tag);
void    SvgStyleApplyStrokeCapJoin(const char *tag);
Boolean SvgStyleHasStroke(const char *tag);
Boolean SvgStyleHasFill(const char *tag);
/* groups */
void    SvgStyleGroupPush(const char *tag);
void    SvgStyleGroupPop(void);
Boolean SvgStyleGroupStrokeWidthGet(WWFixedAsDWord *outW);

/* ---- viewBox/viewport mapping ---- */
void   SvgViewInitFromSvgTag(const char *tag);
void   SvgViewInitDefault(void);
sword  SvgViewMapPosX_F(WWFixedAsDWord fx);
sword  SvgViewMapPosY_F(WWFixedAsDWord fy);
sword  SvgViewMapLenX_F(WWFixedAsDWord fx);
sword  SvgViewMapLenY_F(WWFixedAsDWord fy);

/* Provide the view matrix (world <- user) as SVG-style 2x3:
   x' = a*x + c*y + e;  y' = b*x + d*y + f */
void   SvgViewGetMatrix(WWFixedAsDWord *a, WWFixedAsDWord *b,
                        WWFixedAsDWord *c, WWFixedAsDWord *d,
                        WWFixedAsDWord *e, WWFixedAsDWord *f);


/* Transform layer (CTM) */
/* ---- transform layer (CTM) ---- */
/* SVG 2x3 affine matrix in user units: [a c e; b d f] */
typedef struct {
    WWFixedAsDWord a, b, c, d, e, f;
} SvgMatrix;

void SvgXformApplyPoint(sword *xP, sword *yP, const SvgMatrix *m);
void SvgXformApplyVector(sword *dxP, sword *dyP, const SvgMatrix *m);
void SvgXformParseAttrUser(const char *tag, SvgMatrix *outUser);
void SvgXformBuildWorld(const char *tag, const SvgMatrix *parentCTM, SvgMatrix *outWorld);
/* Conjugated element matrix that acts on points already in WORLD space:
   ElemOnWorld = ViewMatrix ∘ Element ∘ ViewMatrix^{-1}  */
void SvgXformBuildElemOnWorld(const char *tag, SvgMatrix *outElemWorld);
/* groups */
void SvgXformGroupPush(const char *tag);
void SvgXformGroupPop(void);

/* ---- element-local helpers (legacy scale-only; now superseded by CTM) ---- */
sword SvgShapeScaleLength(sword v, WWFixedAsDWord s);
void  SvgShapeParsePoints(const char *points, Point *pointsP, word *numPointsP);

/* ---- tag handlers (dispatch targets) ---- */
void SvgShapeHandleLine(const char *tag);
void SvgShapeHandlePolyline(const char *tag, SVGScratch *sc);
void SvgShapeHandlePolygon(const char *tag, SVGScratch *sc);
void SvgShapeHandleRect(const char *tag);
void SvgShapeHandleEllipse(const char *tag);
void SvgShapeHandleCircle(const char *tag);

/* ---- tag handlers: path with subcommands ---- */
void SvgPathHandle(const char *tag, SVGScratch *sc);
static void SvgPathHandleMoveTo   (const char **sPP, char *lastCmdP,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   sword *subStartXP, sword *subStartYP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleLineTo   (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleHLineTo  (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleVLineTo  (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleQuadratic(const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                   sword *lastQcxP, sword *lastQcyP);
static void SvgPathHandleSmoothQuadratic(const char **sPP, char lastCmd,
                                         SVGScratch *sc, word *npP,
                                         sword *lastxP, sword *lastyP,
                                         Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                         sword *lastQcxP, sword *lastQcyP);
static void SvgPathHandleCubic    (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                   sword *lastC2xP, sword *lastC2yP);
static void SvgPathHandleSmoothCubic(const char **sPP, char lastCmd,
                                     SVGScratch *sc, word *npP,
                                     sword *lastxP, sword *lastyP,
                                     Boolean *lastWasCubicP, Boolean *lastWasQuadP,
                                     sword *lastC2xP, sword *lastC2yP);
static void SvgPathHandleArc      (const char **sPP, char lastCmd,
                                   SVGScratch *sc, word *npP,
                                   sword *lastxP, sword *lastyP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleClose    (const char **sPP,
                                   Boolean *closedP,
                                   sword *lastxP, sword *lastyP,
                                   sword subStartX, sword subStartY,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);
static void SvgPathHandleUnknown  (const char **sPP,
                                   Boolean *lastWasCubicP, Boolean *lastWasQuadP);

/* ---- streamed parser entry ---- */
typedef Boolean _pascal ProgressCallback(word percent);
TransError _export _pascal ReadSVG(FileHandle srcFile, word settings, ProgressCallback *callback);
