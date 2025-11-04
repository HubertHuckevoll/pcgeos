#ifndef __VCIMPEX_SVGEXP_H_
#define __VCIMPEX_SVGEXP_H_

#include <geos.h>
#include <heap.h>
#include <lmem.h>
#include <library.h>
#include <graphics.h>
#include <gstring.h>
#include <file.h>
#include <color.h>
#include <localize.h>
#include <Ansi/string.h>
#include <Ansi/stdio.h>
#include <Ansi/stdlib.h>
#include <resource.h>
#include <system.h>
#include <math.h>

#include <xlatLib.h>

#define VCIMPEX_SVG_MAX_POLY_POINTS   512
#define VCIMPEX_SVG_ELEMENT_BUFFER_SIZE   4096

typedef struct
{
    FileHandle svgFile;
    RectDWord bounds;
    WWFixedAsDWord lineWidth;
    RGBColorAsDWord lineColor;
    RGBColorAsDWord fillColor;
    MemHandle bufferHeapH;
} VCImpexSVGExportContext;

/* Pending rectangle coalescing state */
typedef struct {
    Boolean active;
    /* geometry already transformed to world coords */
    PointWWFixed corner1;
    PointWWFixed corner3;
    /* style captured at time of ops */
    WWFixedAsDWord strokeWidth;
    RGBColorAsDWord strokeColor;
    RGBColorAsDWord fillColor;
    Boolean haveStroke;
    Boolean haveFill;
} VCImpexSVGPendingRect;

Boolean _pascal VCImpexSVGWriteHeader(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteFooter(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteLineElement(VCImpexSVGExportContext *context, const PointWWFixed *startPoint, const PointWWFixed *endPoint);
Boolean _pascal VCImpexSVGWriteRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, Boolean filled);
Boolean _pascal VCImpexSVGWriteRoundRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, const WWFixed *radiusX, const WWFixed *radiusY, Boolean filled);
Boolean _pascal VCImpexSVGWritePolygonElement(VCImpexSVGExportContext *context, const PointWWFixed *points, word pointCount, Boolean closeShape, Boolean filled);
Boolean _pascal VCImpexSVGWriteEllipseElement(VCImpexSVGExportContext *context,
                                              const WWFixed *cx,
                                              const WWFixed *cy,
                                              const WWFixed *rx,
                                              const WWFixed *ry,
                                              Boolean filled,
                                              const TransMatrix *tm);
Boolean _pascal VCImpexSVGWriteCubicPathElement(VCImpexSVGExportContext *context,
                                                const PointWWFixed *start,
                                                const PointWWFixed *cp1,
                                                const PointWWFixed *cp2,
                                                const PointWWFixed *end);
Boolean _pascal VCImpexSVGWriteArcElement(VCImpexSVGExportContext *context,
                                          WWFixedAsDWord cx,
                                          WWFixedAsDWord cy,
                                          WWFixedAsDWord rx,
                                          WWFixedAsDWord ry,
                                          word startAngleDeg,
                                          word endAngleDeg,
                                          ArcCloseType closeType,
                                          Boolean filled,
                                          const TransMatrix *tm);
Boolean _pascal VCImpexSVGUpdateDrawingState(GStateHandle gstate, VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteRawString(VCImpexSVGExportContext *context, const char *text);
void _pascal VCImpexSVGTransformPointFromInt(GStateHandle gstate, const Point *sourcePoint, PointWWFixed *targetPoint);
void _pascal VCImpexSVGTransformPointFromFixed(GStateHandle gstate, const PointWWFixed *sourcePoint, PointWWFixed *targetPoint);
void _pascal VCImpexSVGTransformRelativePoint(GStateHandle gstate, const PointWWFixed *deltaPoint, PointWWFixed *targetPoint);
WWFixedAsDWord _pascal VCImpexSVGPackWWFixed(const WWFixed *value);
void _pascal VCImpexSVGCopyPointWWFixed(PointWWFixed *destination, const PointWWFixed *source);

/* Internal helpers for coalescing */
void _pascal VCImpexSVGInitPendingRect(VCImpexSVGPendingRect *pending);
Boolean _pascal VCImpexSVGFlushPendingRect(VCImpexSVGExportContext *context, VCImpexSVGPendingRect *pending);

#endif
