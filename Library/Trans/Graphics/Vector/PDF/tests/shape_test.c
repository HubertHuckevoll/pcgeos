/* Independent geometric checks of the production shape emitter. Floating
 * point is used only by this host test, never by the GEOS implementation. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
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
static void arcCapture(char *buffer, size_t capacity, int x1, int y1,
                        int x2, int y2, int start, int end, int close, int fill)
{
    PdfDocument p;
    size_t n;
    memset(&p,0,sizeof(p));p.inPage=1;out=tmpfile();assert(out);
    PdfArc(&p,x1,y1,x2,y2,start,end,close,fill,(void *)0);PdfFlush(&p);assert(!p.error);
    rewind(out);n=fread(buffer,1,capacity-1,out);assert(feof(out));buffer[n]=0;fclose(out);
}
static void arcGeometry(int x1,int y1,int x2,int y2,int start,int end)
{
    char buffer[2048],reverse[2048];
    const char *s;
    double x,y,c[6],t,u,px,py,radial,angle,expectedX,expectedY;
    double cx=((double)x1+x2)/2,cy=((double)y1+y2)/2;
    double rx=((double)x2-x1)/2,ry=((double)y2-y1)/2;
    int consumed,count=0,sample;
    arcCapture(buffer,sizeof(buffer),x1,y1,x2,y2,start,end,0,0);
    arcCapture(reverse,sizeof(reverse),x2,y2,x1,y1,start,end,0,0);
    assert(!strcmp(buffer,reverse));assert(!strstr(buffer,"cm"));
    assert(sscanf(buffer,"%lf %lf m%n",&x,&y,&consumed)==2);s=buffer+consumed;
    /* GEOS angles are radial, rather than ellipse parameters. */
    angle=start*3.14159265358979323846/180;
    t=atan2(rx*sin(angle),ry*cos(angle));
    expectedX=cx+rx*cos(t);expectedY=cy-ry*sin(t);
    assert(fabs(x-expectedX)<rx*0.00008+0.00004);
    assert(fabs(y-expectedY)<ry*0.00008+0.00004);
    while(sscanf(s," %lf %lf %lf %lf %lf %lf c%n",
                 &c[0],&c[1],&c[2],&c[3],&c[4],&c[5],&consumed)==6) {
        s+=consumed;++count;
        for(sample=0;sample<=20;++sample) {
            t=sample/20.0;u=1-t;
            px=u*u*u*x+3*u*u*t*c[0]+3*u*t*t*c[2]+t*t*t*c[4];
            py=u*u*u*y+3*u*u*t*c[1]+3*u*t*t*c[3]+t*t*t*c[5];
            assert(px>=x1-0.00002 && px<=x2+0.00002);
            assert(py>=y1-0.00002 && py<=y2+0.00002);
            radial=sqrt(((px-cx)/rx)*((px-cx)/rx)+((py-cy)/ry)*((py-cy)/ry));
            assert(fabs(radial-1)<0.0005);
        }
        x=c[4];y=c[5];
    }
    assert(count>=1 && count<=5 && !strcmp(s,"\nS\n"));
    angle=end*3.14159265358979323846/180;
    t=atan2(rx*sin(angle),ry*cos(angle));
    assert(fabs(x-cx-rx*cos(t))<rx*0.00008+0.00004);
    assert(fabs(y-cy+ry*sin(t))<ry*0.00008+0.00004);
}
static void threePointGeometry(const double *v)
{
    PdfDocument p;
    PdfFixed points[6];
    char buffer[4096];
    const char *s;
    size_t n;
    double ux=v[2]-v[0],uy=v[3]-v[1],vx=v[4]-v[0],vy=v[5]-v[1];
    double cross=ux*vy-uy*vx, a=(ux*ux+uy*uy)/2,b=(vx*vx+vy*vy)/2;
    double cx=v[0]+(a*vy-b*uy)/cross,cy=v[1]+(b*ux-a*vx)/cross;
    double radius=hypot(v[0]-cx,v[1]-cy),x,y,c[6],t,u,px,py;
    int i,used,count=0,middle=0;
    for(i=0;i<6;++i)points[i]=(PdfFixed)(v[i]*65536);
    memset(&p,0,sizeof(p));p.inPage=1;out=tmpfile();assert(out);
    PdfThreePointArc(&p,points,0,0);PdfFlush(&p);assert(!p.error);
    rewind(out);n=fread(buffer,1,sizeof(buffer)-1,out);buffer[n]=0;assert(feof(out));fclose(out);
    assert(sscanf(buffer,"%lf %lf m%n",&x,&y,&used)==2);s=buffer+used;
    assert(fabs(x-v[0])<0.00002 && fabs(y-v[1])<0.00002);
    while(sscanf(s," %lf %lf %lf %lf %lf %lf c%n",
                 &c[0],&c[1],&c[2],&c[3],&c[4],&c[5],&used)==6) {
        s+=used;++count;
        for(i=0;i<=20;++i) {
            t=i/20.0;u=1-t;
            px=u*u*u*x+3*u*u*t*c[0]+3*u*t*t*c[2]+t*t*t*c[4];
            py=u*u*u*y+3*u*u*t*c[1]+3*u*t*t*c[3]+t*t*t*c[5];
            assert(fabs(hypot(px-cx,py-cy)-radius)<radius*0.001+0.002);
        }
        x=c[4];y=c[5];
        if(fabs(x-v[2])<0.00002 && fabs(y-v[3])<0.00002)middle=1;
    }
    assert(count>=2 && count<=6 && middle && !strcmp(s,"\nS\n"));
    assert(fabs(x-v[4])<0.00002 && fabs(y-v[5])<0.00002);
}
static void brushGeometry(int x1,int y1,int x2,int y2)
{
    PdfDocument p;
    unsigned char got[32][32]={{0}},expected[32][32]={{0}};
    char buffer[4096];
    const char *s;
    size_t n;
    int x,y,w,h,used,i,j,dx,dy,major,minor,step,m,px,py,sign;
    memset(&p,0,sizeof(p));p.inPage=1;out=tmpfile();assert(out);
    PdfBrushSegment(&p,x1,y1,x2,y2,4,2);PdfFlush(&p);assert(!p.error);
    rewind(out);n=fread(buffer,1,sizeof(buffer)-1,out);buffer[n]=0;assert(feof(out));fclose(out);
    s=buffer;
    while(sscanf(s," %d %d %d %d re f%n",&x,&y,&w,&h,&used)==4) {
        s+=used;assert(x>=0 && y>=0 && x+w<=32 && y+h<=32);
        for(i=x;i<x+w;++i)for(j=y;j<y+h;++j)got[j][i]=1;
    }
    /* Independent analytic pixel positions, ordered along the positive major
     * axis, with native half-way ties toward the minor-axis endpoint. */
    dx=abs(x2-x1);dy=abs(y2-y1);
    if((dx>=dy && x2<x1) || (dy>dx && y2<y1)) {
        i=x1;x1=x2;x2=i;i=y1;y1=y2;y2=i;
    }
    major=dx>=dy ? dx : dy;minor=dx>=dy ? dy : dx;
    sign=(dx>=dy ? y2>=y1 : x2>=x1) ? 1 : -1;
    for(step=0;step<=major;++step) {
        m=major ? (2*step*minor+major)/(2*major) : 0;
        px=x1+(dx>=dy ? step : sign*m);py=y1+(dx>=dy ? sign*m : step);
        for(i=px;i<px+4;++i)for(j=py;j<py+2;++j)expected[j][i]=1;
    }
    assert(!memcmp(got,expected,sizeof(got)));
}
int main(int argc, char **argv)
{
    PdfDocument p;
    char buffer[2048];
    PdfDWord position;
    PdfFixed line3[6]={-2147483647L-1,-2147483647L-1,0,0,2147418112L,2147418112L};
    PdfFixed flat3[6]={0,0,65536000L,0,131072000L,1};
    PdfFixed drawn3[6]={19660800L,45875200L,26214400L,39321600L,32768000L,45875200L};
    const double arc3[][6]={{200,100,100,0,0,100},{0,100,100,0,200,100},
        {200,100,100,200,100,0},{10.5,20.25,80,10,100,100},
        {0,0,0.25,0.5,1,0},{-10000,-10000,0,0,10000,-10000}};
    unsigned i;
    for(i=0;i<sizeof(arc3)/sizeof(arc3[0]);++i)threePointGeometry(arc3[i]);
    memset(&p,0,sizeof(p));p.inPage=1;out=tmpfile();assert(out);
    PdfThreePointArc(&p,line3,1,1);PdfFlush(&p);assert(!p.error);
    rewind(out);assert(fread(buffer,1,sizeof(buffer),out)>0);fclose(out);
    memset(&p,0,sizeof(p));p.inPage=1;
    PdfThreePointArc(&p,flat3,0,0);assert(p.error==PDF_LIMIT_ERROR);
    memset(&p,0,sizeof(p));p.inPage=1;
    PdfThreePointArc(&p,line3,0,1);assert(p.error==PDF_STATE_ERROR);
    brushGeometry(4,4,20,10);brushGeometry(20,10,4,4);
    brushGeometry(4,20,20,14);brushGeometry(20,14,4,20);
    brushGeometry(4,4,10,20);brushGeometry(10,20,4,4);
    brushGeometry(20,4,14,20);brushGeometry(14,20,20,4);
    brushGeometry(4,4,20,4);brushGeometry(4,4,4,20);brushGeometry(4,4,4,4);
    assert(argc == 2);
    arcGeometry(10,20,210,120,30,210);
    arcGeometry(-7,-13,0,0,-45,45);
    arcGeometry(0,0,1,1,1,359);
    arcGeometry(-32768,-32768,32767,32767,-32768,32767);
    arcGeometry(-32768,32766,32767,32767,1,359);
    arcGeometry(0,0,150,90,37,37);
    arcCapture(buffer,sizeof(buffer),10,20,210,120,0,90,1,0);
    assert(strstr(buffer,"h\nS\n") && !strstr(buffer,"l\n"));
    arcCapture(buffer,sizeof(buffer),10,20,210,120,0,90,2,1);
    assert(strstr(buffer,"110 70 l\nh\nf\n"));
    arcCapture(buffer,sizeof(buffer),10,20,210,120,0,90,0,-1);
    assert(!strstr(buffer,"S") && !strstr(buffer,"h\n"));
    arcCapture(buffer,sizeof(buffer),10,20,10,20,0,90,1,1);
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
    PdfArc(&p,300,250,500,350,30,300,0,0,(void *)0);
    PdfArc(&p,300,450,500,550,30,300,2,1,(void *)0);
    PdfThreePointArc(&p,drawn3,1,1);
    PdfEndPage(&p); PdfFinish(&p); assert(!p.error); fclose(out);
    puts("shape: geometry, word limits, constant stroke, degenerate bounds and I/O passed");
    return 0;
}
