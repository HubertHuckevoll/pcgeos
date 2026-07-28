#include "svgcore.h"

#define VCISVG_FIXED_ONE ((VCISVGU32)65536L)

typedef struct
{
    char *data;
    VCISVGU16 capacity;
    VCISVGU16 length;
    VCISVGU16 failed;
} VCISVGBuffer;

static VCISVGU16
VCISVGTextLength(const char *text)
{
    VCISVGU16 length;

    if (text == (void*)0)
    {
        return 0;
    }

    length = 0;
    while ((text[length] != '\0') && (length != 0xffff))
    {
        length++;
    }
    return length;
}

static int
VCISVGBufferAppendBytes(VCISVGBuffer *buffer,
                        const char *data,
                        VCISVGU16 byteCount)
{
    VCISVGU16 index;

    if ((buffer == (void*)0) || (data == (void*)0) ||
        (buffer->failed != 0))
    {
        return 0;
    }
    if ((byteCount >= buffer->capacity) ||
        (buffer->length > buffer->capacity - byteCount - 1))
    {
        buffer->failed = 1;
        return 0;
    }

    for (index = 0; index < byteCount; index++)
    {
        buffer->data[buffer->length + index] = data[index];
    }
    buffer->length += byteCount;
    buffer->data[buffer->length] = '\0';
    return 1;
}

static int
VCISVGBufferAppendText(VCISVGBuffer *buffer, const char *text)
{
    return VCISVGBufferAppendBytes(buffer, text, VCISVGTextLength(text));
}

static int
VCISVGBufferAppendFixed(VCISVGBuffer *buffer,
                        VCISVGFixed value,
                        VCISVGU16 fractionDigits)
{
    char number[24];
    VCISVGU16 length;

    if (!VCISVGFormatFixed(value, fractionDigits, number,
                           sizeof(number), &length))
    {
        buffer->failed = 1;
        return 0;
    }
    return VCISVGBufferAppendBytes(buffer, number, length);
}

static int
VCISVGWriteFixed(VCISVGWriter *writer,
                 VCISVGFixed value,
                 VCISVGU16 fractionDigits)
{
    char number[24];
    VCISVGU16 length;

    if (!VCISVGFormatFixed(value, fractionDigits, number,
                           sizeof(number), &length))
    {
        return 0;
    }
    return VCISVGWrite(writer, number, length);
}

static int
VCISVGWriteU32(VCISVGWriter *writer, VCISVGU32 value)
{
    char reversed[10];
    char number[10];
    VCISVGU16 count;
    VCISVGU16 index;

    count = 0;
    do
    {
        reversed[count++] = (char)('0' + (value % 10));
        value /= 10;
    } while (value != 0);

    for (index = 0; index < count; index++)
    {
        number[index] = reversed[count - index - 1];
    }
    return VCISVGWrite(writer, number, count);
}

static int
VCISVGWriteI32(VCISVGWriter *writer, VCISVGI32 value)
{
    VCISVGU32 magnitude;

    if (value < 0)
    {
        if (!VCISVGWriteText(writer, "-"))
        {
            return 0;
        }
        magnitude = (VCISVGU32)(-(value + 1));
        magnitude++;
    }
    else
    {
        magnitude = (VCISVGU32)value;
    }
    return VCISVGWriteU32(writer, magnitude);
}

static int
VCISVGWriteColor(VCISVGWriter *writer,
                 VCISVGU16 red,
                 VCISVGU16 green,
                 VCISVGU16 blue)
{
    static const char digits[] = "0123456789ABCDEF";
    char color[7];

    color[0] = '#';
    color[1] = digits[(red >> 4) & 0x0f];
    color[2] = digits[red & 0x0f];
    color[3] = digits[(green >> 4) & 0x0f];
    color[4] = digits[green & 0x0f];
    color[5] = digits[(blue >> 4) & 0x0f];
    color[6] = digits[blue & 0x0f];
    return VCISVGWrite(writer, color, sizeof(color));
}

static int
VCISVGStyleIsValid(const VCISVGStyle *style)
{
    if (style == (void*)0)
    {
        return 0;
    }
    if (style->dashCount > VCISVG_MAX_DASH_VALUES)
    {
        return 0;
    }
    return 1;
}

static int
VCISVGWriteStyle(VCISVGWriter *writer, const VCISVGStyle *style)
{
    const char *cap;
    const char *join;
    const char *fillRule;
    VCISVGU16 index;

    if (!VCISVGStyleIsValid(style))
    {
        return 0;
    }

    if (style->includeStroke != 0)
    {
        if (!VCISVGWriteText(writer, " stroke=\"") ||
            !VCISVGWriteColor(writer, style->lineRed,
                              style->lineGreen, style->lineBlue) ||
            !VCISVGWriteText(writer, "\" stroke-width=\"") ||
            !VCISVGWriteFixed(writer, style->lineWidth, 2) ||
            !VCISVGWriteText(writer, "\" stroke-linecap=\""))
        {
            return 0;
        }

        cap = "butt";
        if (style->lineCap == VCISVG_CAP_ROUND)
        {
            cap = "round";
        }
        else if (style->lineCap == VCISVG_CAP_SQUARE)
        {
            cap = "square";
        }
        if (!VCISVGWriteText(writer, cap) ||
            !VCISVGWriteText(writer, "\" stroke-linejoin=\""))
        {
            return 0;
        }

        join = "miter";
        if (style->lineJoin == VCISVG_JOIN_ROUND)
        {
            join = "round";
        }
        else if (style->lineJoin == VCISVG_JOIN_BEVEL)
        {
            join = "bevel";
        }
        if (!VCISVGWriteText(writer, join) ||
            !VCISVGWriteText(writer, "\" stroke-dasharray=\""))
        {
            return 0;
        }

        if (style->dashCount == 0)
        {
            if (!VCISVGWriteText(writer, "none"))
            {
                return 0;
            }
        }
        else
        {
            for (index = 0; index < style->dashCount; index++)
            {
                if ((index != 0) && !VCISVGWriteText(writer, " "))
                {
                    return 0;
                }
                if (!VCISVGWriteFixed(writer, style->dashValues[index], 2))
                {
                    return 0;
                }
            }
        }

        if (!VCISVGWriteText(writer, "\" stroke-miterlimit=\"") ||
            !VCISVGWriteFixed(writer, style->miterLimit, 2) ||
            !VCISVGWriteText(writer, "\""))
        {
            return 0;
        }
        if ((style->dashCount != 0) && (style->hasDashOffset != 0))
        {
            if (!VCISVGWriteText(writer, " stroke-dashoffset=\"") ||
                !VCISVGWriteFixed(writer, style->dashOffset, 2) ||
                !VCISVGWriteText(writer, "\""))
            {
                return 0;
            }
        }
        if ((style->nonScalingStroke != 0) &&
            !VCISVGWriteText(writer,
                             " vector-effect=\"non-scaling-stroke\""))
        {
            return 0;
        }
    }
    else if (!VCISVGWriteText(writer, " stroke=\"none\""))
    {
        return 0;
    }

    if (style->includeFill != 0)
    {
        if (!VCISVGWriteText(writer, " fill=\""))
        {
            return 0;
        }
        if (style->filled != 0)
        {
            if (!VCISVGWriteColor(writer, style->fillRed,
                                  style->fillGreen, style->fillBlue))
            {
                return 0;
            }
        }
        else if (!VCISVGWriteText(writer, "none"))
        {
            return 0;
        }

        fillRule = (style->fillRule == VCISVG_FILL_EVENODD) ?
                   "evenodd" : "nonzero";
        if (!VCISVGWriteText(writer, "\" fill-rule=\"") ||
            !VCISVGWriteText(writer, fillRule) ||
            !VCISVGWriteText(writer, "\""))
        {
            return 0;
        }
    }
    else if (!VCISVGWriteText(writer, " fill=\"none\""))
    {
        return 0;
    }

    return 1;
}

static int
VCISVGWriteMatrix(VCISVGWriter *writer, const VCISVGMatrix *matrix)
{
    if ((matrix == (void*)0) || (matrix->present == 0))
    {
        return 1;
    }

    return VCISVGWriteText(writer, " transform=\"matrix(") &&
           VCISVGWriteFixed(writer, matrix->a, 6) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, matrix->b, 6) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, matrix->c, 6) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, matrix->d, 6) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, matrix->e, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, matrix->f, 2) &&
           VCISVGWriteText(writer, ")\"");
}

void
VCISVGWriterInit(VCISVGWriter *writer,
                 VCISVGSink sink,
                 void *userData)
{
    if (writer == (void*)0)
    {
        return;
    }

    writer->sink = sink;
    writer->userData = userData;
    writer->failed = 0;
}

int
VCISVGWriterFailed(const VCISVGWriter *writer)
{
    return ((writer == (void*)0) || (writer->failed != 0));
}

int
VCISVGWrite(VCISVGWriter *writer,
            const char *data,
            VCISVGU16 byteCount)
{
    if ((writer == (void*)0) || (writer->sink == (void*)0) ||
        (data == (void*)0) || (writer->failed != 0))
    {
        return 0;
    }
    if (byteCount == 0)
    {
        return 1;
    }
    if (!writer->sink(writer->userData, data, byteCount))
    {
        writer->failed = 1;
        return 0;
    }
    return 1;
}

int
VCISVGWriteText(VCISVGWriter *writer, const char *text)
{
    if (text == (void*)0)
    {
        return 0;
    }
    return VCISVGWrite(writer, text, VCISVGTextLength(text));
}

int
VCISVGFormatFixed(VCISVGFixed value,
                  VCISVGU16 fractionDigits,
                  char *buffer,
                  VCISVGU16 bufferSize,
                  VCISVGU16 *length)
{
    char integerDigits[10];
    char fraction[6];
    VCISVGU32 magnitude;
    VCISVGU32 integerPart;
    VCISVGU32 fractionPart;
    VCISVGU32 product;
    VCISVGU16 integerCount;
    VCISVGU16 fractionCount;
    VCISVGU16 outputLength;
    VCISVGU16 index;
    VCISVGU16 negative;
    VCISVGU16 carry;

    if ((buffer == (void*)0) || (length == (void*)0) ||
        (bufferSize == 0) || (fractionDigits > 6))
    {
        return 0;
    }

    negative = (value < 0) ? 1 : 0;
    if (negative != 0)
    {
        magnitude = (VCISVGU32)(-(value + 1));
        magnitude++;
    }
    else
    {
        magnitude = (VCISVGU32)value;
    }

    integerPart = magnitude >> 16;
    fractionPart = magnitude & 0xffff;
    fractionCount = fractionDigits;
    for (index = 0; index < fractionDigits; index++)
    {
        product = fractionPart * 10;
        fraction[index] = (char)('0' + (product >> 16));
        fractionPart = product & 0xffff;
    }

    product = fractionPart * 10;
    carry = ((product >> 16) >= 5) ? 1 : 0;
    index = fractionCount;
    while ((carry != 0) && (index != 0))
    {
        index--;
        if (fraction[index] == '9')
        {
            fraction[index] = '0';
        }
        else
        {
            fraction[index]++;
            carry = 0;
        }
    }
    if (carry != 0)
    {
        integerPart++;
    }
    while ((fractionCount != 0) &&
           (fraction[fractionCount - 1] == '0'))
    {
        fractionCount--;
    }
    if ((integerPart == 0) && (fractionCount == 0))
    {
        negative = 0;
    }

    integerCount = 0;
    do
    {
        integerDigits[integerCount++] =
            (char)('0' + (integerPart % 10));
        integerPart /= 10;
    } while (integerPart != 0);

    outputLength = negative + integerCount;
    if (fractionCount != 0)
    {
        outputLength += 1 + fractionCount;
    }
    if (outputLength >= bufferSize)
    {
        return 0;
    }

    index = 0;
    if (negative != 0)
    {
        buffer[index++] = '-';
    }
    while (integerCount != 0)
    {
        buffer[index++] = integerDigits[--integerCount];
    }
    if (fractionCount != 0)
    {
        buffer[index++] = '.';
        for (integerCount = 0; integerCount < fractionCount; integerCount++)
        {
            buffer[index++] = fraction[integerCount];
        }
    }
    buffer[index] = '\0';
    *length = index;
    return 1;
}

int
VCISVGFormatPathMove(const VCISVGPoint *point,
                     char *buffer,
                     VCISVGU16 bufferSize,
                     VCISVGU16 *length)
{
    VCISVGBuffer output;

    if ((point == (void*)0) || (buffer == (void*)0) ||
        (length == (void*)0))
    {
        return 0;
    }
    output.data = buffer;
    output.capacity = bufferSize;
    output.length = 0;
    output.failed = 0;
    if (bufferSize != 0)
    {
        buffer[0] = '\0';
    }

    VCISVGBufferAppendText(&output, "M ");
    VCISVGBufferAppendFixed(&output, point->x, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, point->y, 2);
    VCISVGBufferAppendText(&output, " ");
    *length = output.length;
    return (output.failed == 0);
}

int
VCISVGFormatPathLine(const VCISVGPoint *point,
                     char *buffer,
                     VCISVGU16 bufferSize,
                     VCISVGU16 *length)
{
    VCISVGBuffer output;

    if ((point == (void*)0) || (buffer == (void*)0) ||
        (length == (void*)0))
    {
        return 0;
    }
    output.data = buffer;
    output.capacity = bufferSize;
    output.length = 0;
    output.failed = 0;
    if (bufferSize != 0)
    {
        buffer[0] = '\0';
    }

    VCISVGBufferAppendText(&output, "L ");
    VCISVGBufferAppendFixed(&output, point->x, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, point->y, 2);
    VCISVGBufferAppendText(&output, " ");
    *length = output.length;
    return (output.failed == 0);
}

int
VCISVGFormatPathCubic(const VCISVGPoint *control1,
                      const VCISVGPoint *control2,
                      const VCISVGPoint *end,
                      char *buffer,
                      VCISVGU16 bufferSize,
                      VCISVGU16 *length)
{
    VCISVGBuffer output;

    if ((control1 == (void*)0) || (control2 == (void*)0) ||
        (end == (void*)0) || (buffer == (void*)0) ||
        (length == (void*)0))
    {
        return 0;
    }
    output.data = buffer;
    output.capacity = bufferSize;
    output.length = 0;
    output.failed = 0;
    if (bufferSize != 0)
    {
        buffer[0] = '\0';
    }

    VCISVGBufferAppendText(&output, "C ");
    VCISVGBufferAppendFixed(&output, control1->x, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, control1->y, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, control2->x, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, control2->y, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, end->x, 2);
    VCISVGBufferAppendText(&output, " ");
    VCISVGBufferAppendFixed(&output, end->y, 2);
    VCISVGBufferAppendText(&output, " ");
    *length = output.length;
    return (output.failed == 0);
}

int
VCISVGEmitHeader(VCISVGWriter *writer,
                 VCISVGI32 left,
                 VCISVGI32 top,
                 VCISVGU32 width,
                 VCISVGU32 height)
{
    return VCISVGWriteText(writer,
                           "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n") &&
           VCISVGWriteText(writer,
                           "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\"\n") &&
           VCISVGWriteText(writer, "     width=\"") &&
           VCISVGWriteU32(writer, width) &&
           VCISVGWriteText(writer, "\" height=\"") &&
           VCISVGWriteU32(writer, height) &&
           VCISVGWriteText(writer, "\" viewBox=\"") &&
           VCISVGWriteI32(writer, left) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteI32(writer, top) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteU32(writer, width) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteU32(writer, height) &&
           VCISVGWriteText(writer, "\">\n");
}

int
VCISVGEmitFooter(VCISVGWriter *writer)
{
    return VCISVGWriteText(writer, "</svg>\n");
}

int
VCISVGEmitLine(VCISVGWriter *writer,
               const VCISVGPoint *start,
               const VCISVGPoint *end,
               const VCISVGStyle *style)
{
    if ((start == (void*)0) || (end == (void*)0) ||
        !VCISVGStyleIsValid(style))
    {
        return 0;
    }

    return VCISVGWriteText(writer, "  <line x1=\"") &&
           VCISVGWriteFixed(writer, start->x, 2) &&
           VCISVGWriteText(writer, "\" y1=\"") &&
           VCISVGWriteFixed(writer, start->y, 2) &&
           VCISVGWriteText(writer, "\" x2=\"") &&
           VCISVGWriteFixed(writer, end->x, 2) &&
           VCISVGWriteText(writer, "\" y2=\"") &&
           VCISVGWriteFixed(writer, end->y, 2) &&
           VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitRect(VCISVGWriter *writer,
               const VCISVGRect *rect,
               VCISVGU16 rounded,
               const VCISVGStyle *style,
               const VCISVGMatrix *matrix)
{
    if ((rect == (void*)0) || !VCISVGStyleIsValid(style))
    {
        return 0;
    }

    if (!VCISVGWriteText(writer, "  <rect x=\"") ||
        !VCISVGWriteFixed(writer, rect->x, 2) ||
        !VCISVGWriteText(writer, "\" y=\"") ||
        !VCISVGWriteFixed(writer, rect->y, 2) ||
        !VCISVGWriteText(writer, "\" width=\"") ||
        !VCISVGWriteFixed(writer, rect->width, 2) ||
        !VCISVGWriteText(writer, "\" height=\"") ||
        !VCISVGWriteFixed(writer, rect->height, 2) ||
        !VCISVGWriteText(writer, "\""))
    {
        return 0;
    }
    if (rounded != 0)
    {
        if (!VCISVGWriteText(writer, " rx=\"") ||
            !VCISVGWriteFixed(writer, rect->radiusX, 2) ||
            !VCISVGWriteText(writer, "\" ry=\"") ||
            !VCISVGWriteFixed(writer, rect->radiusY, 2) ||
            !VCISVGWriteText(writer, "\""))
        {
            return 0;
        }
    }
    return VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitEllipse(VCISVGWriter *writer,
                  const VCISVGPoint *center,
                  VCISVGFixed radiusX,
                  VCISVGFixed radiusY,
                  const VCISVGStyle *style,
                  const VCISVGMatrix *matrix)
{
    if ((center == (void*)0) || !VCISVGStyleIsValid(style))
    {
        return 0;
    }

    return VCISVGWriteText(writer, "  <ellipse cx=\"") &&
           VCISVGWriteFixed(writer, center->x, 2) &&
           VCISVGWriteText(writer, "\" cy=\"") &&
           VCISVGWriteFixed(writer, center->y, 2) &&
           VCISVGWriteText(writer, "\" rx=\"") &&
           VCISVGWriteFixed(writer, radiusX, 2) &&
           VCISVGWriteText(writer, "\" ry=\"") &&
           VCISVGWriteFixed(writer, radiusY, 2) &&
           VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitCubic(VCISVGWriter *writer,
                const VCISVGPoint *start,
                const VCISVGPoint *control1,
                const VCISVGPoint *control2,
                const VCISVGPoint *end,
                const VCISVGStyle *style,
                const VCISVGMatrix *matrix)
{
    if ((start == (void*)0) || (control1 == (void*)0) ||
        (control2 == (void*)0) || (end == (void*)0) ||
        !VCISVGStyleIsValid(style))
    {
        return 0;
    }

    return VCISVGWriteText(writer, "  <path d=\"M ") &&
           VCISVGWriteFixed(writer, start->x, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, start->y, 2) &&
           VCISVGWriteText(writer, " C ") &&
           VCISVGWriteFixed(writer, control1->x, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, control1->y, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, control2->x, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, control2->y, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, end->x, 2) &&
           VCISVGWriteText(writer, " ") &&
           VCISVGWriteFixed(writer, end->y, 2) &&
           VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitArc(VCISVGWriter *writer,
              const VCISVGArc *arc,
              const VCISVGStyle *style,
              const VCISVGMatrix *matrix)
{
    if ((arc == (void*)0) || !VCISVGStyleIsValid(style))
    {
        return 0;
    }

    if (!VCISVGWriteText(writer, "  <path d=\"M "))
    {
        return 0;
    }
    if (arc->filled && (arc->closeType == VCISVG_ARC_PIE))
    {
        if (!VCISVGWriteFixed(writer, arc->center.x, 2) ||
            !VCISVGWriteText(writer, " ") ||
            !VCISVGWriteFixed(writer, arc->center.y, 2) ||
            !VCISVGWriteText(writer, " L "))
        {
            return 0;
        }
    }
    if (!VCISVGWriteFixed(writer, arc->start.x, 2) ||
        !VCISVGWriteText(writer, " ") ||
        !VCISVGWriteFixed(writer, arc->start.y, 2) ||
        !VCISVGWriteText(writer, " A ") ||
        !VCISVGWriteFixed(writer, arc->radiusX, 2) ||
        !VCISVGWriteText(writer, " ") ||
        !VCISVGWriteFixed(writer, arc->radiusY, 2) ||
        !VCISVGWriteText(writer, " 0 ") ||
        !VCISVGWriteU32(writer, arc->largeArc ? 1 : 0) ||
        !VCISVGWriteText(writer, " ") ||
        !VCISVGWriteU32(writer, arc->sweep ? 1 : 0) ||
        !VCISVGWriteText(writer, " ") ||
        !VCISVGWriteFixed(writer, arc->end.x, 2) ||
        !VCISVGWriteText(writer, " ") ||
        !VCISVGWriteFixed(writer, arc->end.y, 2))
    {
        return 0;
    }
    if (arc->filled && !VCISVGWriteText(writer, " Z"))
    {
        return 0;
    }
    return VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitPolygonBegin(VCISVGWriter *writer, VCISVGU16 closed)
{
    return VCISVGWriteText(writer,
                           closed ? "  <polygon points=\"" :
                                    "  <polyline points=\"");
}

int
VCISVGEmitPolygonPoint(VCISVGWriter *writer,
                       const VCISVGPoint *point)
{
    if (point == (void*)0)
    {
        return 0;
    }
    return VCISVGWriteFixed(writer, point->x, 2) &&
           VCISVGWriteText(writer, ",") &&
           VCISVGWriteFixed(writer, point->y, 2) &&
           VCISVGWriteText(writer, " ");
}

int
VCISVGEmitPolygonEnd(VCISVGWriter *writer,
                     const VCISVGStyle *style,
                     const VCISVGMatrix *matrix)
{
    if (!VCISVGStyleIsValid(style))
    {
        return 0;
    }
    return VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}

int
VCISVGEmitPath(VCISVGWriter *writer,
               const char *pathData,
               VCISVGU16 pathLength,
               const VCISVGStyle *style,
               const VCISVGMatrix *matrix)
{
    if ((pathData == (void*)0) || !VCISVGStyleIsValid(style))
    {
        return 0;
    }
    return VCISVGWriteText(writer, "  <path d=\"") &&
           VCISVGWrite(writer, pathData, pathLength) &&
           VCISVGWriteText(writer, "\"") &&
           VCISVGWriteStyle(writer, style) &&
           VCISVGWriteMatrix(writer, matrix) &&
           VCISVGWriteText(writer, " />\n");
}
