/* Check rounded-rectangle geometry independently of its integer emitter. */
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

static void capture(char *buffer, int x1, int y1, int x2, int y2,
                    PdfWord radius, int fill)
{
    PdfDocument p;
    size_t n;
    memset(&p, 0, sizeof(p));
    p.inPage = 1;
    out = tmpfile();
    assert(out);
    PdfRoundRect(&p, x1, y1, x2, y2, radius, fill);
    PdfFlush(&p);
    assert(!p.error);
    rewind(out);
    n = fread(buffer, 1, 2047, out);
    assert(feof(out));
    buffer[n] = 0;
    fclose(out);
}

static void geometry(int x1, int y1, int x2, int y2, PdfWord radius)
{
    char buffer[2048], other[2048];
    const char *s;
    double r = radius, width = (double)x2-x1, height = (double)y2-y1;
    double x, y, a, b, c[6], cx, cy, t, u, px, py, radial, dx, dy;
    int curve, sample, used;
    if (r > floor(width/2)) r = floor(width/2);
    if (r > floor(height/2)) r = floor(height/2);
    assert(r > 0);
    capture(buffer, x1, y1, x2, y2, radius, 0);
    capture(other, x2, y1, x1, y2, radius, 0);
    assert(!strcmp(buffer, other));
    capture(other, x1, y2, x2, y1, radius, 0);
    assert(!strcmp(buffer, other));
    capture(other, x2, y2, x1, y1, (PdfWord)r, 0);
    assert(!strcmp(buffer, other));
    assert(!strstr(buffer, "cm") && !strstr(buffer, " w"));
    assert(sscanf(buffer, "%lf %lf m%n", &x, &y, &used) == 2);
    assert(fabs(x-(x1+r)) < 0.00002 && fabs(y-y1) < 0.00002);
    s = buffer + used;
    for (curve = 0; curve < 4; ++curve) {
        assert(sscanf(s, " %lf %lf l%n", &a, &b, &used) == 2);
        s += used;
        /* Four edges must be straight and axis aligned, ending at tangencies. */
        assert(fabs((a-x)*(b-y)) < 0.00002);
        cx = curve < 2 ? x2-r : x1+r;
        cy = (curve == 0 || curve == 3) ? y1+r : y2-r;
        if (curve == 0) assert(fabs(a-cx)<0.00002 && fabs(b-y1)<0.00002);
        if (curve == 1) assert(fabs(a-x2)<0.00002 && fabs(b-cy)<0.00002);
        if (curve == 2) assert(fabs(a-cx)<0.00002 && fabs(b-y2)<0.00002);
        if (curve == 3) assert(fabs(a-x1)<0.00002 && fabs(b-cy)<0.00002);
        x = a;
        y = b;
        assert(sscanf(s, " %lf %lf %lf %lf %lf %lf c%n",
               &c[0], &c[1], &c[2], &c[3], &c[4], &c[5], &used) == 6);
               s += used;
        /* Each end tangent must be perpendicular to its corner radius. */
        dx = c[0]-x;
        dy = c[1]-y;
        assert(fabs(dx*(x-cx)+dy*(y-cy)) < 0.001);
        dx = c[4]-c[2];
        dy = c[5]-c[3];
        assert(fabs(dx*(c[4]-cx)+dy*(c[5]-cy)) < 0.001);
        for (sample = 0; sample <= 100; ++sample) {
            t = sample / 100.0;
            u = 1-t;
            px = u*u*u*x + 3*u*u*t*c[0] + 3*u*t*t*c[2] + t*t*t*c[4];
            py = u*u*u*y + 3*u*u*t*c[1] + 3*u*t*t*c[3] + t*t*t*c[5];
            assert(px >= x1-0.00002 && px <= x2+0.00002);
            assert(py >= y1-0.00002 && py <= y2+0.00002);
            radial = sqrt((px-cx)*(px-cx)+(py-cy)*(py-cy))/r;
            assert(fabs(radial-1) < 0.0004);
        }
        x = c[4];
        y = c[5];
    }
    assert(fabs(x-(x1+r))<0.00002 && fabs(y-y1)<0.00002);
    assert(!strcmp(s, "\nh S\n"));
}

int main(int argc, char **argv)
{
    PdfDocument p;
    PdfDWord position;
    char buffer[2048];
    assert(argc == 2);
    geometry(10, 20, 210, 120, 20);
    geometry(-7,-13,0,0,65535); /* unsigned radius, odd integer half-extents */
    geometry(0, 0, 2, 2, 1);
    geometry(-32768, -32768, 32767, 32767, 65535);
    geometry(-32768, 32765, 32767, 32767, 65535);
    capture(buffer, 10, 20, 110, 80, 0, 0);
    assert(!strcmp(buffer,"10 20 100 60 re S\n"));
    capture(buffer, 10, 20, 110, 80, 0, 1);
    assert(!strcmp(buffer,"10 20 100 60 re f\n"));
    capture(buffer, 0, 0, 1, 1, 65535, 0);
    assert(!strcmp(buffer,"0 0 1 1 re S\n"));
    capture(buffer, 10, 20, 10, 80, 65535, 1);
    assert(!strcmp(buffer,"10 20 0 60 re f\n"));
    capture(buffer, 10, 20, 110, 20, 65535, 0);
    assert(!strcmp(buffer,"10 20 100 0 re S\n"));
    capture(buffer, 10, 20, 10, 20, 65535, 0);
    assert(!strcmp(buffer,"10 20 0 0 re S\n"));
    capture(buffer, 10, 20, 110, 80, 10, 1);
    assert(strstr(buffer,"h f\n"));
    memset(&p, 0, sizeof(p));
    PdfRoundRect(&p, 0, 0, 10, 10, 1, 0);
    assert(p.error == PDF_STATE_ERROR);
    memset(&p, 0, sizeof(p));
    p.inPage = 1;
    out = tmpfile();
    assert(out);
    failSink = 1;
    PdfRoundRect(&p, -32768, -32768, 32767, 32767, 65535, 0);
    PdfFlush(&p);
    assert(p.error == PDF_IO_ERROR);
    position = p.position;
    PdfRoundRect(&p, 0, 0, 10, 10, 1, 0);
    assert(p.position==position);
    failSink = 0;
    fclose(out);

    out=fopen(argv[1],"wb");
    assert(out);
    memset(&p, 0, sizeof(p));
    p.width = 595;
    p.height = 842;
    PdfBegin(&p);
    PdfBeginPage(&p);
    PdfRaw(&p,"2 w 1 0 0 RG\n");
    PdfRoundRect(&p, 50, 50, 350, 150, 20, 0);
    PdfRaw(&p,"0 0 1 rg\n");
    PdfRoundRect(&p, 50, 200, 150, 400, 65535, 1);
    PdfRoundRect(&p, 200, 200, 350, 350, 65535, 0);
    PdfEndPage(&p);
    PdfBeginPage(&p);
    PdfRaw(&p,"q 0.8 0.3 -0.2 1 120 80 cm 3 w\n");
    PdfRoundRect(&p, 0, 0, 300, 100, 30, 0);
    PdfRaw(&p,"Q\n");
    PdfRoundRect(&p, 50, 300, 51, 500, 65535, 0);
    PdfEndPage(&p);
    PdfFinish(&p);
    assert(!p.error);
    fclose(out);
    puts("roundrect: tangencies, radius clamp, word limits, degeneracies and I/O passed");
    return 0;
}
