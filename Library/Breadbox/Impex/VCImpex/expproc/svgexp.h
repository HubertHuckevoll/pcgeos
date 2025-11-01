#ifndef __VCIMPEX_SVGEXP_H_
#define __VCIMPEX_SVGEXP_H_

#include <geos.h>
#include <graphics.h>
#include <gstring.h>
#include <file.h>
#include <color.h>
#include <localize.h>
#include <Ansi/string.h>
#include <Ansi/stdio.h>

#include <xlatLib.h>

#define VCIMPEX_SVG_MAX_POLY_POINTS   256
#define VCIMPEX_SVG_ELEMENT_BUFFER_SIZE   1024

typedef struct
{
    FileHandle svgFile;
    RectDWord bounds;
    WWFixedAsDWord lineWidth;
    RGBColorAsDWord lineColor;
    RGBColorAsDWord fillColor;
    MemHandle bufferHeapH;
} VCImpexSVGExportContext;

Boolean _pascal VCImpexSVGWriteHeader(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteFooter(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteLineElement(VCImpexSVGExportContext *context, const PointWWFixed *startPoint, const PointWWFixed *endPoint);
Boolean _pascal VCImpexSVGWriteRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, Boolean filled);
Boolean _pascal VCImpexSVGWritePolygonElement(VCImpexSVGExportContext *context, const PointWWFixed *points, word pointCount, Boolean closeShape, Boolean filled);
Boolean _pascal VCImpexSVGUpdateDrawingState(GStateHandle gstate, VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteRawString(VCImpexSVGExportContext *context, const char *text);
void _pascal VCImpexSVGTransformPointFromInt(GStateHandle gstate, const Point *sourcePoint, PointWWFixed *targetPoint);
void _pascal VCImpexSVGTransformPointFromFixed(GStateHandle gstate, const PointWWFixed *sourcePoint, PointWWFixed *targetPoint);
void _pascal VCImpexSVGTransformRelativePoint(GStateHandle gstate, const PointWWFixed *deltaPoint, PointWWFixed *targetPoint);
WWFixedAsDWord _pascal VCImpexSVGPackWWFixed(const WWFixed *value);
void _pascal VCImpexSVGCopyPointWWFixed(PointWWFixed *destination, const PointWWFixed *source);

#endif
