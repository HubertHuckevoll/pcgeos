#include <string.h>

#include "../expproc/svgcore.h"

typedef struct
{
    char data[1024];
    VCISVGU16 length;
    VCISVGU16 calls;
    VCISVGU16 failAtCall;
} TestSink;

static int
TestWrite(void *userData, const char *data, VCISVGU16 byteCount)
{
    TestSink *sink;

    sink = (TestSink*)userData;
    sink->calls++;
    if (((sink->failAtCall != 0) &&
         (sink->calls >= sink->failAtCall)) ||
        (byteCount > sizeof(sink->data) - sink->length))
    {
        return 0;
    }
    memcpy(sink->data + sink->length, data, byteCount);
    sink->length += byteCount;
    return 1;
}

static int
CheckFixed(VCISVGFixed value, VCISVGU16 digits, const char *expected)
{
    char output[24];
    VCISVGU16 length;

    if (!VCISVGFormatFixed(value, digits, output,
                           sizeof(output), &length))
    {
        return 0;
    }
    return (length == strlen(expected)) &&
           (memcmp(output, expected, length) == 0);
}

static int
CheckLine(void)
{
    static const char expected[] =
        "  <line x1=\"1.5\" y1=\"-2\" x2=\"3\" y2=\"4.25\""
        " stroke=\"#112233\" stroke-width=\"1\""
        " stroke-linecap=\"butt\" stroke-linejoin=\"miter\""
        " stroke-dasharray=\"none\" stroke-miterlimit=\"4\""
        " fill=\"none\" />\n";
    TestSink sink;
    VCISVGWriter writer;
    VCISVGPoint start;
    VCISVGPoint end;
    VCISVGStyle style;

    memset(&sink, 0, sizeof(sink));
    memset(&style, 0, sizeof(style));
    VCISVGWriterInit(&writer, TestWrite, &sink);
    start.x = 0x00018000L;
    start.y = -0x00020000L;
    end.x = 0x00030000L;
    end.y = 0x00044000L;
    style.lineWidth = 0x00010000L;
    style.miterLimit = 0x00040000L;
    style.lineRed = 0x11;
    style.lineGreen = 0x22;
    style.lineBlue = 0x33;
    style.includeStroke = 1;

    if (!VCISVGEmitLine(&writer, &start, &end, &style))
    {
        return 0;
    }
    return (sink.length == sizeof(expected) - 1) &&
           (memcmp(sink.data, expected, sink.length) == 0);
}

static int
CheckSinkFailure(void)
{
    TestSink sink;
    VCISVGWriter writer;
    VCISVGPoint start;
    VCISVGPoint end;
    VCISVGStyle style;

    memset(&sink, 0, sizeof(sink));
    memset(&style, 0, sizeof(style));
    sink.failAtCall = 3;
    VCISVGWriterInit(&writer, TestWrite, &sink);
    start.x = 0;
    start.y = 0;
    end.x = 0x00010000L;
    end.y = 0x00010000L;
    style.includeStroke = 1;
    if (VCISVGEmitLine(&writer, &start, &end, &style))
    {
        return 0;
    }
    if (VCISVGEmitFooter(&writer))
    {
        return 0;
    }
    return VCISVGWriterFailed(&writer) && (sink.calls == 3);
}

int
main(void)
{
    if (!CheckFixed(0x00018000L, 2, "1.5"))
    {
        return 1;
    }
    if (!CheckFixed(-0x00008000L, 2, "-0.5"))
    {
        return 2;
    }
    if (!CheckFixed(0x0000ffffL, 2, "1"))
    {
        return 3;
    }
    if (!CheckFixed(-1L, 2, "0"))
    {
        return 4;
    }
    if (!CheckLine())
    {
        return 5;
    }
    if (!CheckSinkFailure())
    {
        return 6;
    }
    return 0;
}
