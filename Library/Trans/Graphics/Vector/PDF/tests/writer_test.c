/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     PDF Host Regression Tests
FILE:       writer_test.c

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    main - Write a sample two-page PDF document

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Exercise the production serializer with a non-seekable sink.
    Check PDF object emission, fixed numbers and stream failures.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Run the production serializer against a non-seekable sink. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../pdfWriter.h"
static FILE *out;
static unsigned calls, failCall;
PdfWord PdfSink(PdfDocument *p, const void *data, PdfWord size)
{
    (void)p;
    ++calls;
    if (calls == failCall) return 1;
    return fwrite(data, 1, size, out) != size;
}

static void init(PdfDocument *p)
{
    memset(p, 0, sizeof(*p));
    p->width = 595;
    p->height = 842;
    PdfBegin(p);
}

int main(int argc, char **argv)
{
    PdfDocument p;
    PdfFixed m[6] = {65536, 0, 0, 65536, 0, 0};
    unsigned i;
    assert(argc == 2);
    out = fopen(argv[1], "wb");
    assert(out);
    init(&p);
    PdfBeginPage(&p);
    PdfPageMatrix(&p, m);
    PdfApplyPageMatrix(&p);
    PdfRaw(&p, "q 1 0 0 RG 2 w 30 30 m 300 120 l S Q\n");
    PdfRaw(&p, "q 0 0 1 rg 60 180 140 80 re f Q\n");
    PdfText(&p, 60L * 65536, 150L * 65536, 18L * 65536, 0,
            (const unsigned char *)"Native PDF (GEOS) \\ page 1", 26);
    for (i = 0; i < 5000; ++i) PdfRaw(&p, "% streamed padding\n");
    PdfEndPage(&p);
    PdfBeginPage(&p);
    PdfPageMatrix(&p, m);
    PdfApplyPageMatrix(&p);
    PdfRaw(&p, "30 30 m 80 20 160 220 300 200 c S\n");
    PdfText(&p, 60L * 65536, 150L * 65536, 18L * 65536, 1,
            (const unsigned char *)"Second page", 11);
    PdfRaw(&p, "% fixed extremes ");
    PdfNumber(&p, INT32_MIN);
    PdfNumber(&p, -1);
    PdfNumber(&p, INT32_MAX);
    PdfRaw(&p, "\n");
    PdfEndPage(&p);
    PdfFinish(&p);
    assert(p.error == PDF_OK);
    assert(fclose(out) == 0);
    PdfBeginPage(&p);
    assert(p.error == PDF_STATE_ERROR);

    out = tmpfile();
    assert(out);
    init(&p);
    for (i = 0; i < PDF_MAX_PAGES; ++i) {
        PdfBeginPage(&p);
        PdfEndPage(&p);
    }

    PdfBeginPage(&p);
    assert(p.error == PDF_LIMIT_ERROR);
    fclose(out);

    out = tmpfile();
    assert(out);
    init(&p);
    PdfBeginPage(&p);
    PdfBeginPage(&p);
    assert(p.error == PDF_STATE_ERROR);
    fclose(out);
    out = tmpfile();
    assert(out);
    init(&p);
    PdfBeginPage(&p);
    PdfPageMatrix(&p, m);
    PdfPageMatrix(&p, m);
    assert(p.error == PDF_STATE_ERROR);
    fclose(out);
    out = tmpfile();
    assert(out);
    init(&p);
    PdfFinish(&p);
    assert(p.error == PDF_STATE_ERROR);
    fclose(out);
    out = tmpfile();
    assert(out);
    init(&p);
    p.position = UINT32_MAX;
    PdfRaw(&p, "x");
    assert(p.error == PDF_LIMIT_ERROR);
    fclose(out);

    /* Every stream-write failure must latch; no EOF may hide an error. */
    for (i = 1; i < 8; ++i) {
        out = tmpfile();
        assert(out);
        calls = 0;
        failCall = i;
        init(&p);
        PdfBeginPage(&p);
        while (calls < i && !p.error) PdfRaw(&p, "0 0 m 1 1 l S\n");
        assert(p.error == PDF_IO_ERROR);
        {
            unsigned failedAt = calls;
            PdfEndPage(&p);
            PdfFinish(&p);
          assert(calls == failedAt);
        }
        fclose(out);
    }
    puts("writer: multipage, limits, lifecycle and sink errors passed");
    return 0;
}
