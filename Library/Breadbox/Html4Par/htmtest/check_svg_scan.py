#!/usr/bin/env python3
"""Compile and exercise the scanner used by Html4Par."""

from pathlib import Path
import subprocess
import tempfile


source = (Path(__file__).resolve().parents[1] / "htmlpars/htmlpars.goc").read_text()
start = source.index("Boolean LOCAL ScanSVGContent()")
opening = source.index("{", start)
depth = 0
for end in range(opening, len(source)):
    if source[end] == "{":
        depth += 1
    elif source[end] == "}":
        depth -= 1
        if depth == 0:
            break
scanner = source[start : end + 1]

harness = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef int Boolean;
typedef unsigned int word;
typedef unsigned char byte;
typedef unsigned long dword;
#define LOCAL
#define TRUE 1
#define FALSE 0
static const unsigned char *inputP;
static unsigned inputLen, inputPos;
static unsigned long svgSourceLen;
static Boolean svgHasShape, svgUnsupported;
static Boolean G_abortParse, G_hitAllocLimit;
static unsigned char capturedSource[721000];
static int HTMLgetcLow(void)
{
    return inputPos < inputLen ? inputP[inputPos++] : EOF;
}
static Boolean SVGAppend(int c)
{
    capturedSource[svgSourceLen++] = (unsigned char)c;
    return TRUE;
}
''' + scanner + r'''
static void check(const char *s, unsigned n, Boolean complete,
                  unsigned consumed, unsigned long captured,
                  Boolean hasShape, Boolean unsupported)
{
    Boolean result;
    inputP = (const unsigned char *)s;
    inputLen = n;
    inputPos = 0;
    svgSourceLen = 5; /* the already captured <svg> opener */
    svgHasShape = svgUnsupported = FALSE;
    G_abortParse = G_hitAllocLimit = FALSE;
    result = ScanSVGContent();
    if (result != complete || inputPos != consumed ||
        svgSourceLen != captured)
        fprintf(stderr, "scan mismatch: result=%d consumed=%u bytes=%lu "
                "expected=%d,%u,%lu\n", result, inputPos, svgSourceLen,
                complete, consumed, captured);
    assert(result == complete);
    assert(inputPos == consumed);
    assert(svgSourceLen == captured);
    assert(!memcmp(capturedSource + 5, s, consumed));
    assert(svgHasShape == hasShape);
    assert(svgUnsupported == unsupported);
}
int main(void)
{
    char large[16390];
    static char deep[720902];
    unsigned i;
    const char nested[] =
      "<g><svg viewBox=\"0 0 10 10\"><path/></svg></g></svg>";
    const char selfClosed[] = "<svg/><path/></svg><p>after</p>";
    const char selfClosedSpace[] = "<svg / ><path/></svg><p>after</p>";
    const char utf8[] = "<g data-x=\"\xc3\xa4\">\r\n<path/></g></svg>";
    const char quoted[] = "<g data-x=\"a > b\"><path/></g></svg>";
    const char commented[] =
      "<!-- </svg> --><svg width=\"4\"><path/></svg></svg>";
    check(selfClosed, sizeof(selfClosed)-1, TRUE, 19, 24, TRUE, FALSE);
    check(selfClosedSpace, sizeof(selfClosedSpace)-1, TRUE, 21, 26,
          TRUE, FALSE);
    check(utf8, sizeof(utf8)-1, TRUE, sizeof(utf8)-1, sizeof(utf8)-1+5,
          TRUE, FALSE);
    check(nested, sizeof(nested)-1, TRUE, sizeof(nested)-1,
          sizeof(nested)-1+5,
          TRUE, FALSE);
    check(quoted, sizeof(quoted)-1, TRUE, sizeof(quoted)-1,
          sizeof(quoted)-1+5,
          TRUE, FALSE);
    check(commented, sizeof(commented)-1, TRUE, sizeof(commented)-1,
          sizeof(commented)-1+5, TRUE, FALSE);
    check("<use href=\"#icon\"/></svg>", 25, TRUE, 25, 30,
          FALSE, TRUE);
    check("<g>", 3, FALSE, 3, 8, FALSE, FALSE);
    check("</svg><p>", 9, TRUE, 6, 11, FALSE, FALSE);
    memset(large, ' ', sizeof(large));
    memcpy(large + 16381, "</svg>", 6);
    check(large, 16387, TRUE, 16387, 16392, FALSE, FALSE);
    for (i = 0; i < 65536; i++)
        memcpy(deep + 5*i, "<svg>", 5);
    for (i = 0; i < 65537; i++)
        memcpy(deep + 327680 + 6*i, "</svg>", 6);
    check(deep, 720902, TRUE, 720902, 720907, FALSE, FALSE);
    return 0;
}
'''

with tempfile.TemporaryDirectory() as directory:
    c_file = Path(directory) / "check_svg_scan.c"
    binary = Path(directory) / "check_svg_scan"
    c_file.write_text(harness)
    subprocess.run(["cc", "-std=c89", "-Wall", "-Wextra", "-Werror",
                    str(c_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
