/* Canonical image writer and GEOS-storage parser, tested independently of the
 * GString double. PDF image decoding is verified by pdfimages/Poppler too. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../pdfBitmap.h"
static FILE *out;
static unsigned calls, failCall;
PdfWord PdfSink(PdfDocument *p, const void *data, PdfWord size)
{
    (void)p;
    if (++calls == failCall) return 1;
    return fwrite(data,1,size,out) != size;
}
static void wordOut(unsigned char *b, unsigned v) { b[0]=(unsigned char)v;b[1]=(unsigned char)(v>>8); }
static void setup(PdfDocument *p)
{ memset(p,0,sizeof(*p));p->width=595;p->height=842;PdfBegin(p);PdfBeginPage(p); }
static void parser(void)
{
    unsigned char b[64]={9,0,2,0,0,0, 0x80,0, 0x40,0};
    PdfBitmapSlice s;
    PdfBitmapReader reader;
    const unsigned char *row;
    PdfFixed extent;
    PdfWord bytes;
    PdfImageSpec spec;
    unsigned i;
    assert(PdfBitmapParse(b,10,&s)==PDF_OK);
    assert(s.image.format==PDF_IMAGE_STENCIL1 && s.rowBytes==2 && s.rows==2 && s.xDpi==72);
    assert(PdfBitmapReaderOpen(&reader,b,10)==0);
    assert(PdfBitmapNextRow(&reader,&row,&bytes)==0 && row==b+6 && bytes==2);
    assert(PdfBitmapNextRow(&reader,&row,&bytes)==0 && row==b+8 && bytes==2);
    assert(PdfBitmapNextRow(&reader,&row,&bytes)==PDF_STATE_ERROR);
    for (i=0;i<6;++i) assert(PdfBitmapParse(b,(PdfWord)i,&s)==PDF_STATE_ERROR);
    assert(PdfBitmapParse(b,9,&s)==PDF_STATE_ERROR);
    assert(PdfBitmapParse(b,11,&s)==PDF_STATE_ERROR);
    b[4]=1;assert(PdfBitmapParse(b,10,&s)==PDF_UNSUPPORTED);b[4]=0;
    for (i=1;i<256;i*=2) {
        if (i==8) continue;
        b[5]=(unsigned char)i;assert(PdfBitmapParse(b,10,&s)==PDF_UNSUPPORTED);
    }
    memset(b,0,sizeof(b));wordOut(b,2);wordOut(b+2,2);b[5]=11;
    wordOut(b+8,1);wordOut(b+12,20);wordOut(b+16,144);wordOut(b+18,36);
    for(i=0;i<6;++i)b[20+i]=(unsigned char)(i*50);
    assert(PdfBitmapParse(b,26,&s)==PDF_OK && s.rowBytes==6 && s.rows==1 && s.complex);
    wordOut(b+6,1);assert(PdfBitmapParse(b,26,&s)==PDF_OK && s.firstRow==1);
    wordOut(b+6,2);assert(PdfBitmapParse(b,26,&s)==PDF_STATE_ERROR);wordOut(b+6,0);
    wordOut(b+12,19);assert(PdfBitmapParse(b,26,&s)==PDF_STATE_ERROR);wordOut(b+12,20);
    wordOut(b+16,0);assert(PdfBitmapParse(b,26,&s)==PDF_STATE_ERROR);wordOut(b+16,144);
    wordOut(b+8,0);assert(PdfBitmapParse(b,20,&s)==PDF_OK); /* HugeBitmap intro */
    assert(PdfBitmapExtent(300,300,&extent)==0 && extent==72L*65536);
    assert(PdfBitmapExtent(1,144,&extent)==0 && extent==32768);
    assert(PdfBitmapExtent(65535,65535,&extent)==0 && extent==72L*65536);
    assert(PdfBitmapExtent(65535,1,&extent)==PDF_LIMIT_ERROR);
    assert(PdfBitmapExtent(0,72,&extent)==PDF_STATE_ERROR);
    assert(PdfBitmapExtent(1,0,&extent)==PDF_STATE_ERROR);
    spec.width=21846;spec.height=1;spec.format=PDF_IMAGE_RGB24;
    assert(PdfImageRowBytes(&spec,&bytes)==PDF_LIMIT_ERROR);
    spec.width=21845;assert(PdfImageRowBytes(&spec,&bytes)==0 && bytes==65535);
}
int main(int argc,char **argv)
{
    PdfDocument p;
    PdfImage im;
    PdfImageSpec rgb={2,2,PDF_IMAGE_RGB24}, mono={9,2,PDF_IMAGE_STENCIL1};
    unsigned char top[]={255,0,0,0,255,0}, bottom[]={0,0,255,255,255,0};
    unsigned char bits0[]={0x80,0x80}, bits1[]={0x40,0};
    unsigned char row[768];
    PdfDWord before;
    unsigned i,j;
    assert(argc==2);parser();
    out=fopen(argv[1],"wb");assert(out);setup(&p);
    PdfImageBegin(&p,&im,&rgb,50,50,120L*65536,120L*65536);
    PdfImageRow(&p,&im,top,6);PdfImageRow(&p,&im,bottom,6);PdfImageEnd(&p,&im);
    PdfRaw(&p,"0 0 1 rg 50 200 90 20 re f\n1 0 0 rg\n");
    PdfImageBegin(&p,&im,&mono,50,200,90L*65536,20L*65536);
    PdfImageRow(&p,&im,bits0,2);PdfImageRow(&p,&im,bits1,2);PdfImageEnd(&p,&im);
    PdfEndPage(&p);PdfBeginPage(&p);
    rgb.width=256;rgb.height=64;memset(row,0,sizeof(row));
    /* Contains literal whitespace/EI bytes: ASCIIHex cannot terminate early. */
    row[0]=' ';row[1]='E';row[2]='I';
    PdfRaw(&p,"q 1 0.2 0.3 1 0 0 cm\n");
    PdfImageBegin(&p,&im,&rgb,50,50,256L*65536,64L*65536);
    for(i=0;i<64;++i)PdfImageRow(&p,&im,row,sizeof(row));
    PdfImageEnd(&p,&im);PdfRaw(&p,"Q\n");PdfEndPage(&p);PdfFinish(&p);assert(!p.error);fclose(out);

    rgb.width=rgb.height=2;
    for(i=0;i<6;++i) {
        out=tmpfile();assert(out);setup(&p);
        PdfImageBegin(&p,&im,&rgb,0,0,65536,65536);
        if(i==0) PdfImageRow(&p,&im,top,5);
        if(i==1) PdfImageEnd(&p,&im);
        if(i==2) PdfEndPage(&p);
        if(i==3) PdfImageBegin(&p,&im,&rgb,0,0,65536,65536);
        if(i==4) PdfImageRow(&p,&im,0,6);
        if(i==5) {PdfImageRow(&p,&im,top,6);PdfImageRow(&p,&im,bottom,6);PdfImageRow(&p,&im,top,6);}
        assert(p.error==PDF_STATE_ERROR);before=p.position;PdfFinish(&p);assert(p.position==before);fclose(out);
    }
    for(i=1;i<=4;++i) {
        out=tmpfile();assert(out);setup(&p);PdfFlush(&p);calls=0;failCall=i;
        rgb.width=256;rgb.height=64;
        PdfImageBegin(&p,&im,&rgb,0,0,65536,65536);
        for(j=0;j<64 && !p.error;++j)PdfImageRow(&p,&im,row,sizeof(row));
        PdfImageEnd(&p,&im);PdfFlush(&p);assert(p.error==PDF_IO_ERROR);
        before=p.position;PdfEndPage(&p);PdfFinish(&p);assert(p.position==before);
        failCall=0;fclose(out);
    }
    puts("bitmap: storage/DPI validation, canonical rows, image lifetime and I/O passed");
    return 0;
}
