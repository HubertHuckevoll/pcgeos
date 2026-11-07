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
    b[4]=3;assert(PdfBitmapParse(b,10,&s)==PDF_UNSUPPORTED);b[4]=0;
    for (i=1;i<256;i*=2) {
        if (i==1 || i==2 || i==8 || i==16) continue;
        b[5]=(unsigned char)i;assert(PdfBitmapParse(b,10,&s)==PDF_UNSUPPORTED);
    }
    b[5]=1;assert(PdfBitmapParse(b,16,&s)==PDF_OK && s.rowBytes==5 && s.image.paletteEntries==16);
    b[5]=2;assert(PdfBitmapParse(b,24,&s)==PDF_OK && s.rowBytes==9 && s.image.paletteEntries==256);
    b[5]=0x10;assert(PdfBitmapParse(b,14,&s)==PDF_OK && s.rowBytes==4 && s.image.masked);
    assert(PdfBitmapParse(b,13,&s)==PDF_STATE_ERROR);
    memset(b,0,sizeof(b));wordOut(b,3);wordOut(b+2,1);b[5]=0x49;
    wordOut(b+8,1);wordOut(b+12,34);wordOut(b+14,20);
    wordOut(b+16,72);wordOut(b+18,72);wordOut(b+20,4);
    assert(PdfBitmapReaderOpen(&reader,b,36)==PDF_OK);
    assert(reader.slice.image.palette==b+22 && reader.slice.image.paletteEntries==4);
    assert(PdfBitmapNextRow(&reader,&row,&bytes)==PDF_OK && row==b+34 && bytes==2);
    b[5]=0x4a;assert(PdfBitmapParse(b,37,&s)==PDF_OK && s.rowBytes==3);
    wordOut(b+20,0);assert(PdfBitmapParse(b,37,&s)==PDF_STATE_ERROR);
    wordOut(b+20,257);assert(PdfBitmapParse(b,37,&s)==PDF_STATE_ERROR);wordOut(b+20,4);
    wordOut(b+12,33);assert(PdfBitmapParse(b,36,&s)==PDF_STATE_ERROR);wordOut(b+12,34);
    wordOut(b+14,19);assert(PdfBitmapParse(b,37,&s)==PDF_STATE_ERROR);
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
    memset(&spec,0,sizeof(spec));spec.width=21846;spec.height=1;spec.format=PDF_IMAGE_RGB24;
    assert(PdfImageRowBytes(&spec,&bytes)==PDF_LIMIT_ERROR);
    spec.width=21845;assert(PdfImageRowBytes(&spec,&bytes)==0 && bytes==65535);
    spec.masked=1;assert(PdfImageRowBytes(&spec,&bytes)==PDF_LIMIT_ERROR);
}
static void compression(void)
{
    unsigned char b[1024], workspace[PDF_BITMAP_WORKSPACE], packSpace[PDF_BITMAP_CHUNK+2];
    unsigned char lzg[]={0x80,'A',0x81,0x10,1,0,1,20,0x43,'B','C','D',0x40,2,'E','F',0x62,0x60};
    PdfBitmapReader reader;
    const unsigned char *chunk;
    PdfWord bytes, i, at, error;
    PdfDWord seen;
    memset(b,0,sizeof(b));wordOut(b,129);wordOut(b+2,2);b[4]=1;b[5]=2;
    b[6]=128;b[7]=0x12; /* GEOS: 129 repetitions, not a TIFF NOP. */
    b[8]=127;for(i=0;i<128;++i)b[9+i]=(unsigned char)i;b[137]=0;b[138]=128;
    assert(PdfBitmapReaderOpen(&reader,b,139)==PDF_OK);seen=0;
    packSpace[0]=packSpace[PDF_BITMAP_CHUNK+1]=0xce;
    while(reader.row<2) {
        assert(PdfBitmapNextChunk(&reader,packSpace+1,&chunk,&bytes)==PDF_OK);
        assert(packSpace[0]==0xce && packSpace[PDF_BITMAP_CHUNK+1]==0xce);
        assert(bytes && bytes<=PDF_BITMAP_CHUNK);
        for(i=0;i<bytes;++i,++seen)assert(chunk[i]==(seen<129 ? 0x12 : seen-129));
    }
    assert(seen==258);
    wordOut(b,128);assert(PdfBitmapReaderOpen(&reader,b,139)==PDF_OK);
    assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&bytes)==PDF_STATE_ERROR);
    wordOut(b,129);assert(PdfBitmapReaderOpen(&reader,b,7)==PDF_OK);
    assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&bytes)==PDF_STATE_ERROR);

    memset(b,0,sizeof(b));wordOut(b,280);wordOut(b+2,1);b[4]=2;
    memcpy(b+6,lzg,sizeof(lzg));
    assert(PdfBitmapReaderOpen(&reader,b,24)==PDF_OK);
    assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&bytes)==PDF_OK && bytes==35 && reader.row==1);
    for(i=0;i<28;++i)assert(chunk[i]=='A');
    assert(!memcmp(chunk+28,"BCDEF\0\0",7));
    for(i=0;i<4;++i) {
        memcpy(b+6,lzg,sizeof(lzg));wordOut(b,280);at=24;
        if(i==0)b[8]=0x80; /* A match cannot reference unwritten output. */
        if(i==1)at=23; /* Missing end marker. */
        if(i==2)at=25; /* Trailing data after the final row. */
        if(i==3)wordOut(b,272); /* Token overruns the decoded row. */
        assert(PdfBitmapReaderOpen(&reader,b,at)==PDF_OK);
        assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&bytes)==PDF_STATE_ERROR);
    }
    /* Long packets cross chunk boundaries and the 1024-byte history wraps. */
    memset(b,0,sizeof(b));wordOut(b,1275);wordOut(b+2,1);b[4]=2;b[5]=2;
    b[7]=0x40;b[8]=255;for(i=0;i<255;++i)b[9+i]=(unsigned char)i;at=264;
    for(i=0;i<3;++i) {b[at++]=0;b[at++]=255;b[at++]=255;}
    b[at++]=0x43;b[at++]=0;b[at++]=1;b[at++]=2;
    b[at++]=3;b[at++]=255;b[at++]=252;b[at++]=0x60;seen=0;
    assert(PdfBitmapReaderOpen(&reader,b,at)==PDF_OK);
    while(reader.row<1) {
        assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&bytes)==PDF_OK);
        for(i=0;i<bytes;++i,++seen)assert(chunk[i]==(seen<1023 ? seen%255 : seen-1023));
    }
    assert(seen==1275);
    /* The largest indexed scanline still needs only 128 PackBits bytes. */
    memset(b,0,sizeof(b));wordOut(b,65535);wordOut(b+2,1);b[4]=1;b[5]=2;
    for(i=0;i<508;++i) {b[6+i*2]=128;b[7+i*2]=0xab;}
    b[1022]=254;b[1023]=0xab;seen=0;
    assert(PdfBitmapReaderOpen(&reader,b,sizeof(b))==PDF_OK);
    while(reader.row<1) {
        error=PdfBitmapNextChunk(&reader,packSpace+1,&chunk,&bytes);assert(error==PDF_OK);
        assert(packSpace[0]==0xce && packSpace[PDF_BITMAP_CHUNK+1]==0xce);
        for(i=0;i<bytes;++i)assert(chunk[i]==0xab);
        seen+=bytes;
    }
    assert(seen==65535);
}
int main(int argc,char **argv)
{
    PdfDocument p;
    PdfImage im;
    PdfBitmapReader reader;
    const unsigned char *chunk;
    PdfWord chunkBytes;
    unsigned char workspace[PDF_BITMAP_WORKSPACE], packed[39];
    unsigned char lzgRgb[]={2,0,2,0,2,3,0xfc,255,0,0,0,255,0,0x60,
                                       0xfc,0,0,255,255,255,0,0x60};
    PdfImageSpec rgb={2,2,PDF_IMAGE_RGB24,0,0,0}, mono={9,2,PDF_IMAGE_STENCIL1,0,0,0};
    unsigned char palette[]={255,0,0,0,255,0,0,0,255,255,255,0};
    PdfImageSpec index4={3,1,PDF_IMAGE_INDEX4,4,palette,0}, index8={4,1,PDF_IMAGE_INDEX8,4,palette,0};
    PdfImageSpec maskedRGB={9,3,PDF_IMAGE_RGB24,0,0,1}, maskedIndex={3,1,PDF_IMAGE_INDEX4,2,palette,1};
    PdfImageSpec maskedMono={9,1,PDF_IMAGE_STENCIL1,0,0,1};
    unsigned char maskStore[6], maskedRow[29], maskedIndices[]={0xa0,0x0f,0x1f};
    unsigned char maskedBits[]={0xff,0x80,0xaa,0x80};
    unsigned char nibbles[]={0x01,0x2f}, indices[]={0,1,2,3};
    unsigned char top[]={255,0,0,0,255,0}, bottom[]={0,0,255,255,255,0};
    unsigned char bits0[]={0x80,0x80}, bits1[]={0x40,0};
    unsigned char row[768];
    PdfDWord before;
    unsigned i,j;
    assert(argc==2);parser();compression();
    out=fopen(argv[1],"wb");assert(out);setup(&p);
    assert(PdfBitmapReaderOpen(&reader,lzgRgb,sizeof(lzgRgb))==PDF_OK);
    PdfImageBegin(&p,&im,&reader.slice.image,50,50,120L*65536,120L*65536);
    while(reader.row<reader.slice.rows) {
        assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&chunkBytes)==PDF_OK);
        PdfImageRowPart(&p,&im,chunk,chunkBytes);
    }
    PdfImageEnd(&p,&im);
    PdfRaw(&p,"0 0 1 rg 50 200 90 20 re f\n1 0 0 rg\n");
    PdfImageBegin(&p,&im,&mono,50,200,90L*65536,20L*65536);
    PdfImageRow(&p,&im,bits0,2);PdfImageRow(&p,&im,bits1,2);PdfImageEnd(&p,&im);
    PdfImageBegin(&p,&im,&index4,50,300,150L*65536,20L*65536);
    PdfImageRow(&p,&im,nibbles,2);PdfImageEnd(&p,&im);
    memset(packed,0,sizeof(packed));wordOut(packed,4);wordOut(packed+2,1);
    packed[4]=1;packed[5]=0x4a;wordOut(packed+8,1);wordOut(packed+12,34);
    wordOut(packed+14,20);wordOut(packed+16,72);wordOut(packed+18,72);
    wordOut(packed+20,4);memcpy(packed+22,palette,12);packed[34]=3;memcpy(packed+35,indices,4);
    assert(PdfBitmapReaderOpen(&reader,packed,sizeof(packed))==PDF_OK);
    PdfImageBegin(&p,&im,&reader.slice.image,50,350,100L*65536,20L*65536);
    assert(PdfBitmapNextChunk(&reader,workspace,&chunk,&chunkBytes)==PDF_OK);
    PdfImageRowPart(&p,&im,chunk,chunkBytes);PdfImageEnd(&p,&im);
    PdfRaw(&p,"0 0 1 rg 50 400 100 30 re f\n");
    PdfImageBeginMasked(&p,&im,&maskedRGB,50,400,90L*65536,30L*65536,maskStore);
    memset(maskedRow,0,sizeof(maskedRow));for(j=0;j<9;++j)maskedRow[2+j*3]=255;
    for(i=0;i<3;++i) {
        maskedRow[0]=i==0 ? 0xaa : (i==1 ? 0x55 : 0);maskedRow[1]=i==0 ? 0x80 : 0x7f;
        PdfImageRowPart(&p,&im,maskedRow,1);PdfImageRowPart(&p,&im,maskedRow+1,28);
    }
    PdfImageEnd(&p,&im);
    PdfRaw(&p,"0 0 1 rg 50 450 100 20 re f\n");
    PdfImageBeginMasked(&p,&im,&maskedIndex,50,450,90L*65536,20L*65536,maskStore);
    PdfImageRow(&p,&im,maskedIndices,3);PdfImageEnd(&p,&im);
    PdfRaw(&p,"0 0 1 rg 50 500 90 10 re f\n1 0 0 rg\n");
    PdfImageBeginMasked(&p,&im,&maskedMono,50,500,90L*65536,10L*65536,maskStore);
    PdfImageRow(&p,&im,maskedBits,4);PdfImageEnd(&p,&im);
    maskedRGB.width=43;maskedRGB.height=1;
    memset(row,0,135);memset(row,255,6);row[5]=0xe0;
    for(j=0;j<43;++j)row[6+j*3]=255;
    PdfRaw(&p,"0 0 1 rg 200 400 88 10 re f\n");
    PdfImageBeginMasked(&p,&im,&maskedRGB,200,400,86L*65536,10L*65536,maskStore);
    PdfImageRowPart(&p,&im,row,128);PdfImageRowPart(&p,&im,row+128,7);PdfImageEnd(&p,&im);
    PdfEndPage(&p);PdfBeginPage(&p);
    rgb.width=256;rgb.height=64;memset(row,0,sizeof(row));
    /* Contains literal whitespace/EI bytes: ASCIIHex cannot terminate early. */
    row[0]=' ';row[1]='E';row[2]='I';
    PdfRaw(&p,"q 1 0.2 0.3 1 0 0 cm\n");
    PdfImageBegin(&p,&im,&rgb,50,50,256L*65536,64L*65536);
    for(i=0;i<64;++i)PdfImageRow(&p,&im,row,sizeof(row));
    PdfImageEnd(&p,&im);PdfRaw(&p,"Q\n");PdfEndPage(&p);PdfFinish(&p);assert(!p.error);fclose(out);

    rgb.width=rgb.height=2;
    out=tmpfile();assert(out);setup(&p);indices[3]=4;
    PdfImageBegin(&p,&im,&index8,0,0,65536,65536);PdfImageRow(&p,&im,indices,4);
    assert(p.error==PDF_STATE_ERROR);fclose(out);
    out=tmpfile();assert(out);setup(&p);maskedIndices[0]=0x40;
    PdfImageBeginMasked(&p,&im,&maskedIndex,0,0,65536,65536,maskStore);
    PdfImageRow(&p,&im,maskedIndices,3);assert(p.error==PDF_STATE_ERROR);fclose(out);
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
