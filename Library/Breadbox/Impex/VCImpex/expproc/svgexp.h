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
#include <resource.h>
#include <system.h>

#include <xlatLib.h>

#include "svgcore.h"

#define VCIMPEX_SVG_INVALID_OPCODE  0xff
#define VCIMPEX_SVG_OPCODE_SIZE     1
#define VCIMPEX_SVG_WORD_SIZE       2
#define VCIMPEX_SVG_POINT_SIZE      4
#define VCIMPEX_SVG_COMMENT_HEADER_SIZE             3
#define VCIMPEX_SVG_POLY_HEADER_SIZE                3
#define VCIMPEX_SVG_FILL_POLYGON_HEADER_SIZE        4
#define VCIMPEX_SVG_CUSTOM_LINE_STYLE_HEADER_SIZE   5
#define VCIMPEX_SVG_ELEMENT_BUFFER_SIZE   4096
#define VCIMPEX_SVG_TRACE_OPCODES     1

typedef enum
{
    SVG_OPCODE_SUPPORTED_RENDERING,
    SVG_OPCODE_SUPPORTED_STATE,
    SVG_OPCODE_IGNORABLE_METADATA,
    SVG_OPCODE_UNSUPPORTED_RENDERING
} VCImpexSVGOpcodeClass;

typedef enum
{
    SVG_GEOMETRY_NONE,
    SVG_GEOMETRY_MOVE,
    SVG_GEOMETRY_LINE,
    SVG_GEOMETRY_CURVE,
    SVG_GEOMETRY_CLOSE
} VCImpexSVGGeometryType;

typedef struct
{
    Boolean subpathOpen;
    Boolean hasData;
    PointWWFixed lastPoint;
    PointWWFixed subpathStart;
} VCImpexSVGPathBuilder;

typedef struct
{
    FileHandle svgFile;
    VCISVGWriter writer;
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
    ChunkHandle scratchChunkH;
    word scratchCapacity;
    const byte *elementDataP;
    word elementSize;
} VCImpexSVGExportContext;

Boolean _pascal VCImpexSVGInitWriter(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteHeader(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteFooter(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWriteLineElement(VCImpexSVGExportContext *context, const PointWWFixed *startPoint, const PointWWFixed *endPoint, const TransMatrix *tm);
Boolean _pascal VCImpexSVGWriteRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, Boolean includeStroke, Boolean includeFill, Boolean filled, const TransMatrix *tm);
Boolean _pascal VCImpexSVGWriteRoundRectElement(VCImpexSVGExportContext *context, const PointWWFixed *corner1, const PointWWFixed *corner3, word radiusX, word radiusY, Boolean includeStroke, Boolean includeFill, Boolean filled, const TransMatrix *tm);
Boolean _pascal VCImpexSVGWritePolygonBegin(VCImpexSVGExportContext *context,
                                            Boolean closeShape);
Boolean _pascal VCImpexSVGWritePolygonPoint(VCImpexSVGExportContext *context,
                                            const PointWWFixed *point);
Boolean _pascal VCImpexSVGWritePolygonEnd(VCImpexSVGExportContext *context,
                                          Boolean filled,
                                          RegionFillRule fillRule,
                                          const TransMatrix *tm);
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
                                                const PointWWFixed *end,
                                                const TransMatrix *tm);
Boolean _pascal VCImpexSVGWriteArcElement(VCImpexSVGExportContext *context,
                                          WWFixedAsDWord cx,
                                          WWFixedAsDWord cy,
                                          WWFixedAsDWord rx,
                                          WWFixedAsDWord ry,
                                          sword startAngleDeg,
                                          sword endAngleDeg,
                                          ArcCloseType closeType,
                                          Boolean filled,
                                          const TransMatrix *tm);
Boolean _pascal VCImpexSVGWritePathBegin(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWritePathMove(VCImpexSVGExportContext *context,
                                        const PointWWFixed *point);
Boolean _pascal VCImpexSVGWritePathLine(VCImpexSVGExportContext *context,
                                        const PointWWFixed *point);
Boolean _pascal VCImpexSVGWritePathCubic(VCImpexSVGExportContext *context,
                                         const PointWWFixed *control1,
                                         const PointWWFixed *control2,
                                         const PointWWFixed *end);
Boolean _pascal VCImpexSVGWritePathClose(VCImpexSVGExportContext *context);
Boolean _pascal VCImpexSVGWritePathEnd(VCImpexSVGExportContext *context,
                                       Boolean fillPath,
                                       Boolean strokePath,
                                       RegionFillRule fillRule,
                                       const TransMatrix *tm);
Boolean _pascal VCImpexSVGUpdateDrawingState(GStateHandle gstate, VCImpexSVGExportContext *context);
void _pascal VCImpexSVGPointFromInt(const Point *sourcePoint,
                                    PointWWFixed *targetPoint);
WWFixedAsDWord _pascal VCImpexSVGPackWWFixed(const WWFixed *value);
void _pascal VCImpexSVGCopyPointWWFixed(PointWWFixed *destination, const PointWWFixed *source);
Boolean _pascal VCImpexSVGEnsureScratch(VCImpexSVGExportContext *context,
                                        word size);
VCImpexSVGOpcodeClass _pascal
VCImpexSVGClassifyOpcode(word elementType);
void* _pascal VCImpexSVGAs(const void *raw, word expectedOpcode);
Boolean _pascal VCImpexSVGIsLineOpcode(word elementType);
Boolean _pascal VCImpexSVGIsRectangleOpcode(word elementType);
Boolean _pascal VCImpexSVGIsRoundRectOpcode(word elementType);
Boolean _pascal VCImpexSVGIsEllipseOpcode(word elementType);
Boolean _pascal VCImpexSVGIsCurveOpcode(word elementType);
Boolean _pascal VCImpexSVGIsArcOpcode(word elementType);
Boolean _pascal VCImpexSVGIsPolygonOpcode(word elementType);
Boolean _pascal VCImpexSVGIsPathOpcode(word elementType);
Boolean _pascal VCImpexSVGIsStyleStateOpcode(word elementType);
word _pascal VCImpexSVGValidateElement(const byte *elementData,
                                       word elementType,
                                       word elementSize);
word _pascal VCImpexSVGReadElement(VCImpexSVGExportContext *context,
                                   GStateHandle playbackGState,
                                   GStateHandle sourceGState,
                                   word expectedType);
void _pascal VCImpexSVGReleaseElement(VCImpexSVGExportContext *context);
word _pascal VCImpexSVGDecodeGeometry(
    word elementType,
    const PointWWFixed *currentPosition,
    const byte *elementData,
    word elementSize,
    VCImpexSVGGeometryType *geometryType,
    PointWWFixed *startPoint,
    PointWWFixed *control1,
    PointWWFixed *control2,
    PointWWFixed *endPoint);
void _pascal VCImpexSVGSetWWFixedComponent(
    WWFixed *component,
    WWFixedAsDWord value);
word _pascal VCImpexSVGReadWord(const byte *data, word offset);
sword _pascal VCImpexSVGReadSword(const byte *data, word offset);
void _pascal VCImpexSVGReadWWFixed(const byte *data,
                                   word offset,
                                   WWFixed *value);
Boolean _pascal VCImpexSVGPathBuilderMoveTo(
    VCImpexSVGExportContext *context,
    VCImpexSVGPathBuilder *builder,
    const PointWWFixed *point);
Boolean _pascal VCImpexSVGPathBuilderLineTo(
    VCImpexSVGExportContext *context,
    VCImpexSVGPathBuilder *builder,
    const PointWWFixed *startPoint,
    const PointWWFixed *endPoint);
Boolean _pascal VCImpexSVGPathBuilderCurveTo(
    VCImpexSVGExportContext *context,
    VCImpexSVGPathBuilder *builder,
    const PointWWFixed *startPoint,
    const PointWWFixed *control1,
    const PointWWFixed *control2,
    const PointWWFixed *endPoint);
Boolean _pascal VCImpexSVGPathBuilderClose(
    VCImpexSVGExportContext *context,
    VCImpexSVGPathBuilder *builder);

#endif
