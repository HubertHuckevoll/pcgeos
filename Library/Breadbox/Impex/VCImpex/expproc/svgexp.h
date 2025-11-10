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
#define VCIMPEX_SVG_TRACE_OPCODES     1

typedef struct
{
    FileHandle svgFile;
    RectDWord bounds;
    WWFixedAsDWord lineWidth;
    RGBColorAsDWord lineColor;
    RGBColorAsDWord fillColor;
    LineJoin lineJoin;
    LineEnd lineCap;
    WWFixedAsDWord miterLimit;
    LineStyle lineStyle;
    word dashPairCount;
    word dashSkipCount;
    word dashPattern[MAX_DASH_ARRAY_PAIRS * 2];
    RegionFillRule fillRule;
    MemHandle bufferHeapH;
} VCImpexSVGExportContext;

Boolean _pascal VCImpexSVGWriteHeader(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteFooter(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteLineElement(VCImpexSVGExportContext *context, const PointWWFixed *startPoint, const PointWWFixed *endPoint);
Boolean _pascal VCImpexSVGWriteRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, Boolean includeStroke, Boolean includeFill, Boolean filled);
Boolean _pascal VCImpexSVGWriteRoundRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, const WWFixed *radiusX, const WWFixed *radiusY, Boolean includeStroke, Boolean includeFill, Boolean filled);
Boolean _pascal VCImpexSVGWritePolygonElement(VCImpexSVGExportContext *context,
                                             const PointWWFixed *points,
                                             word pointCount,
                                             Boolean closeShape,
                                             Boolean filled,
                                             RegionFillRule fillRule);
Boolean _pascal VCImpexSVGWriteEllipseElement(VCImpexSVGExportContext *context,
                                              const WWFixed *cx,
                                              const WWFixed *cy,
                                              const WWFixed *rx,
                                              const WWFixed *ry,
                                              Boolean includeStroke,
                                              Boolean includeFill,
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
void _pascal VCImpexSVGFormatFixed(WWFixedAsDWord value, char *buffer, word fractionDigits);
Boolean _pascal VCImpexSVGStyleToAttributes(VCImpexSVGExportContext *context,
                                            Boolean includeStroke,
                                            Boolean includeFill,
                                            Boolean filled,
                                            RegionFillRule fillRule,
                                            char *buffer,
                                            word bufferSize);
ChunkHandle _pascal VCImpexSVGAllocBuffer(VCImpexSVGExportContext *context, word size);
void _pascal VCImpexSVGFreeBuffer(VCImpexSVGExportContext *context, ChunkHandle chunk);

#endif
