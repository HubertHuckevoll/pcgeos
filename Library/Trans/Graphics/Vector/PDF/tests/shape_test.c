/* Independent geometric checks of the production shape emitter. Floating
 * point is used only by this host test, never by the GEOS implementation. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "../pdfWriter.h"
static FILE *out;
static int failSink;
PdfWord PdfSink(PdfDocument *p, const void *data, PdfWord size)
{
    (void)p;
    if (failSink) return PDF_IO_ERROR;
    return fwrite(data, 1, size, out) != size;
}
static void capture(char *buffer, size_t capacity, int x1, int y1,
                    int x2, int y2, int fill)
{
    PdfDocument p;
    size_t n;
    memset(&p, 0, sizeof(p)); p.inPage = 1;
    out = tmpfile(); assert(out);
    PdfEllipse(&p, x1, y1, x2, y2, fill); PdfFlush(&p);
    assert(!p.error);
    rewind(out); n = fread(buffer, 1, capacity - 1, out);
    assert(feof(out)); buffer[n] = 0; fclose(out);
}
static void geometry(int x1, int y1, int x2, int y2)
{
    char buffer[2048], reverse[2048];
    const char *s;
    double x, y, c[6], t, u, px, py, radial;
    double cx = ((double)x1 + x2) / 2, cy = ((double)y1 + y2) / 2;
    double rx = ((double)x2 - x1) / 2, ry = ((double)y2 - y1) / 2;
    int consumed, curve, sample;
    capture(buffer, sizeof(buffer), x1, y1, x2, y2, 0);
    capture(reverse, sizeof(reverse), x2, y2, x1, y1, 0);
    assert(strcmp(buffer, reverse) == 0);
    /* No local CTM or line-width operator may distort the inherited stroke. */
    assert(!strstr(buffer, "cm") && !strstr(buffer, " w"));
    assert(sscanf(buffer, "%lf %lf m%n", &x, &y, &consumed) == 2);
    assert(fabs(x - x2) < 0.00002 && fabs(y - cy) < 0.00002);
    s = buffer + consumed;
    for (curve = 0; curve < 4; ++curve) {
        assert(sscanf(s, " %lf %lf %lf %lf %lf %lf c%n",
               &c[0], &c[1], &c[2], &c[3], &c[4], &c[5], &consumed) == 6);
        s += consumed;
        for (sample = 0; sample <= 100; ++sample) {
            t = sample / 100.0; u = 1 - t;
            px = u*u*u*x + 3*u*u*t*c[0] + 3*u*t*t*c[2] + t*t*t*c[4];
            py = u*u*u*y + 3*u*u*t*c[1] + 3*u*t*t*c[3] + t*t*t*c[5];
            assert(px >= x1 - 0.00002 && px <= x2 + 0.00002);
            assert(py >= y1 - 0.00002 && py <= y2 + 0.00002);
            radial = sqrt(((px-cx)/rx)*((px-cx)/rx) +
                          ((py-cy)/ry)*((py-cy)/ry));
            assert(fabs(radial - 1) < 0.0004);
        }
        x = c[4]; y = c[5];
    }
    assert(fabs(x - x2) < 0.00002 && fabs(y - cy) < 0.00002);
    assert(strcmp(s, "\nh S\n") == 0);
}
int main(int argc, char **argv)
{
    PdfDocument p;
    char buffer[2048];
    PdfDWord position;
    assert(argc == 2);
    geometry(10, 20, 210, 120);
    geometry(-7, -13, 0, 0); /* odd dimensions, fractional center/radii */
    geometry(0, 0, 1, 1);
    geometry(-32768, -32768, 32767, 32767);
    geometry(-32768, 32766, 32767, 32767); /* extreme aspect ratio */
    capture(buffer, sizeof(buffer), 10, 20, 30, 40, 1);
    assert(strstr(buffer, "h f\n"));
    capture(buffer, sizeof(buffer), 10, 20, 10, 40, 0);
    assert(strcmp(buffer, "10 20 m 10 40 l S\n") == 0);
    capture(buffer, sizeof(buffer), 10, 20, 30, 20, 0);
    assert(strcmp(buffer, "10 20 m 30 20 l S\n") == 0);
    capture(buffer, sizeof(buffer), 10, 20, 10, 20, 1);
    assert(!buffer[0]);
    memset(&p, 0, sizeof(p));
    PdfEllipse(&p, 0, 0, 10, 10, 0); assert(p.error == PDF_STATE_ERROR);
    out = tmpfile(); assert(out);
    memset(&p, 0, sizeof(p)); p.inPage = 1; failSink = 1;
    PdfEllipse(&p, -32768, -32768, 32767, 32767, 0); PdfFlush(&p);
    assert(p.error == PDF_IO_ERROR); position = p.position;
    PdfEllipse(&p, 0, 0, 10, 10, 0); assert(p.position == position);
    failSink = 0; fclose(out);

    out = fopen(argv[1], "wb"); assert(out);
    memset(&p, 0, sizeof(p)); p.width = 595; p.height = 842; PdfBegin(&p);
    PdfBeginPage(&p);
    PdfRaw(&p, "2 w 1 0 0 RG\n"); PdfEllipse(&p, 50, 50, 350, 150, 0);
    PdfRaw(&p, "0 0 1 rg\n"); PdfEllipse(&p, 50, 200, 150, 400, 1);
    PdfEndPage(&p);
    PdfBeginPage(&p);
    PdfRaw(&p, "q 0.8 0.3 -0.2 1 120 80 cm 3 w 0 0.6 0 RG\n");
    PdfEllipse(&p, 0, 0, 300, 100, 0); PdfRaw(&p, "Q\n");
    PdfEllipse(&p, 50, 300, 51, 500, 0);
    PdfEndPage(&p); PdfFinish(&p); assert(!p.error); fclose(out);
    puts("shape: geometry, word limits, constant stroke, degenerate bounds and I/O passed");
    return 0;
}
