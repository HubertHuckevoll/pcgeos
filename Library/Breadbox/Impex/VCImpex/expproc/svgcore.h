#ifndef __VCIMPEX_SVGCORE_H_
#define __VCIMPEX_SVGCORE_H_

typedef signed short VCISVGI16;
typedef unsigned short VCISVGU16;
#if defined(__WATCOMC__) && !defined(__386__)
typedef signed long VCISVGI32;
typedef unsigned long VCISVGU32;
#else
typedef signed int VCISVGI32;
typedef unsigned int VCISVGU32;
#endif

typedef char VCISVGCheckI16[(sizeof(VCISVGI16) == 2) ? 1 : -1];
typedef char VCISVGCheckU16[(sizeof(VCISVGU16) == 2) ? 1 : -1];
typedef char VCISVGCheckI32[(sizeof(VCISVGI32) == 4) ? 1 : -1];
typedef char VCISVGCheckU32[(sizeof(VCISVGU32) == 4) ? 1 : -1];

#define VCISVG_MAX_DASH_VALUES 10

#define VCISVG_CAP_BUTT         0
#define VCISVG_CAP_ROUND        1
#define VCISVG_CAP_SQUARE       2

#define VCISVG_JOIN_MITER       0
#define VCISVG_JOIN_ROUND       1
#define VCISVG_JOIN_BEVEL       2

#define VCISVG_FILL_NONZERO     0
#define VCISVG_FILL_EVENODD     1

#define VCISVG_ARC_OPEN         0
#define VCISVG_ARC_CHORD        1
#define VCISVG_ARC_PIE          2

typedef int (*VCISVGSink)(void *userData,
                          const char *data,
                          VCISVGU16 byteCount);

typedef struct
{
    VCISVGSink sink;
    void *userData;
    VCISVGU16 failed;
} VCISVGWriter;

typedef VCISVGI32 VCISVGFixed;

typedef struct
{
    VCISVGFixed x;
    VCISVGFixed y;
} VCISVGPoint;

typedef struct
{
    VCISVGFixed a;
    VCISVGFixed b;
    VCISVGFixed c;
    VCISVGFixed d;
    VCISVGFixed e;
    VCISVGFixed f;
} VCISVGMatrix;

typedef struct
{
    VCISVGFixed lineWidth;
    VCISVGFixed miterLimit;
    VCISVGU16 lineRed;
    VCISVGU16 lineGreen;
    VCISVGU16 lineBlue;
    VCISVGU16 fillRed;
    VCISVGU16 fillGreen;
    VCISVGU16 fillBlue;
    VCISVGU16 lineCap;
    VCISVGU16 lineJoin;
    VCISVGU16 dashCount;
    VCISVGFixed dashValues[VCISVG_MAX_DASH_VALUES];
    VCISVGFixed dashOffset;
    VCISVGU16 hasDashOffset;
    VCISVGU16 includeStroke;
    VCISVGU16 includeFill;
    VCISVGU16 filled;
    VCISVGU16 fillRule;
} VCISVGStyle;

typedef struct
{
    VCISVGFixed x;
    VCISVGFixed y;
    VCISVGU32 width;
    VCISVGU32 height;
    VCISVGU32 radiusX;
    VCISVGU32 radiusY;
} VCISVGRect;

typedef struct
{
    VCISVGPoint center;
    VCISVGPoint start;
    VCISVGPoint middle;
    VCISVGPoint end;
    VCISVGFixed radiusX;
    VCISVGFixed radiusY;
    VCISVGU16 largeArc;
    VCISVGU16 sweep;
    VCISVGU16 closeType;
    VCISVGU16 fullCircle;
} VCISVGArc;

void VCISVGWriterInit(VCISVGWriter *writer,
                      VCISVGSink sink,
                      void *userData);
int VCISVGWriterFailed(const VCISVGWriter *writer);
int VCISVGWrite(VCISVGWriter *writer,
                const char *data,
                VCISVGU16 byteCount);
int VCISVGWriteText(VCISVGWriter *writer, const char *text);

int VCISVGFormatFixed(VCISVGFixed value,
                      VCISVGU16 fractionDigits,
                      char *buffer,
                      VCISVGU16 bufferSize,
                      VCISVGU16 *length);
int VCISVGNormalizeArcAngles(VCISVGI16 startAngle,
                             VCISVGI16 endAngle,
                             VCISVGU16 *normalizedStart,
                             VCISVGU16 *normalizedEnd,
                             VCISVGU16 *sweepDegrees,
                             VCISVGU16 *fullCircle);

int VCISVGEmitHeader(VCISVGWriter *writer,
                     VCISVGI32 left,
                     VCISVGI32 top,
                     VCISVGU32 width,
                     VCISVGU32 height);
int VCISVGEmitFooter(VCISVGWriter *writer);
int VCISVGEmitLine(VCISVGWriter *writer,
                   const VCISVGPoint *start,
                   const VCISVGPoint *end,
                   const VCISVGStyle *style,
                   const VCISVGMatrix *matrix);
int VCISVGEmitRect(VCISVGWriter *writer,
                   const VCISVGRect *rect,
                   VCISVGU16 rounded,
                   const VCISVGStyle *style,
                   const VCISVGMatrix *matrix);
int VCISVGEmitEllipse(VCISVGWriter *writer,
                      const VCISVGPoint *center,
                      VCISVGFixed radiusX,
                      VCISVGFixed radiusY,
                      const VCISVGStyle *style,
                      const VCISVGMatrix *matrix);
int VCISVGEmitCubic(VCISVGWriter *writer,
                    const VCISVGPoint *start,
                    const VCISVGPoint *control1,
                    const VCISVGPoint *control2,
                    const VCISVGPoint *end,
                    const VCISVGStyle *style,
                    const VCISVGMatrix *matrix);
int VCISVGEmitArc(VCISVGWriter *writer,
                  const VCISVGArc *arc,
                  const VCISVGStyle *style,
                  const VCISVGMatrix *matrix);
int VCISVGEmitPolygonBegin(VCISVGWriter *writer,
                           VCISVGU16 closed);
int VCISVGEmitPolygonPoint(VCISVGWriter *writer,
                           const VCISVGPoint *point);
int VCISVGEmitPolygonEnd(VCISVGWriter *writer,
                         const VCISVGStyle *style,
                         const VCISVGMatrix *matrix);
int VCISVGEmitPathBegin(VCISVGWriter *writer);
int VCISVGEmitPathMove(VCISVGWriter *writer,
                       const VCISVGPoint *point);
int VCISVGEmitPathLine(VCISVGWriter *writer,
                       const VCISVGPoint *point);
int VCISVGEmitPathCubic(VCISVGWriter *writer,
                        const VCISVGPoint *control1,
                        const VCISVGPoint *control2,
                        const VCISVGPoint *end);
int VCISVGEmitPathClose(VCISVGWriter *writer);
int VCISVGEmitPathEnd(VCISVGWriter *writer,
                      const VCISVGStyle *style,
                      const VCISVGMatrix *matrix);

#endif
