/* Exercise the actual GEOS adapter, dispatcher and serializer, with a small
 * kernel double. This does not substitute for a live spooler/GEOS smoke test. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../pdfGeos.c"
static struct { void *p; unsigned locks; } blocks[32];
static unsigned live, allocations, failAllocation, streamCalls, failStream;
static FILE *out;
static struct { const byte *data; word size; } elements[64];
static word elementCount, cursor, cpX, cpY, style;
static TransMatrix transform;
static word mask = SDM_100;
static word areaMask = SDM_100;
static int ready;
MemHandle MemAlloc(word size, word flags, word af)
{
    word i;
    (void)flags;
    if (++allocations == failAllocation) return 0;
    for (i = 1; i < 32; ++i) if (!blocks[i].p) {
        blocks[i].p = calloc(1, size); assert(blocks[i].p);
        blocks[i].locks = !!(af & HAF_LOCK); ++live; assert(live<=2); return i;
    }
    abort();
}
void *MemLock(MemHandle h) { assert(h && blocks[h].p); ++blocks[h].locks; return blocks[h].p; }
void *MemDeref(MemHandle h) { assert(blocks[h].locks); return blocks[h].p; }
void MemUnlock(MemHandle h) { assert(blocks[h].locks); --blocks[h].locks; }
void MemFree(MemHandle h) { assert(h && blocks[h].p); free(blocks[h].p); memset(&blocks[h],0,sizeof(blocks[h])); --live; }
word PDFSTREAMWRITE(word token, void (*strategy)(void), const void *data, word size)
{
    (void)token; (void)strategy;
    if (++streamCalls == failStream) return 1;
    return fwrite(data,1,size,out) != size;
}
GStateHandle GrCreateState(word w)
{
    (void)w; cpX = cpY = style = 0; ready = 0;
    memset(&transform,0,sizeof(transform));
    transform.TM_e11.WWF_int = transform.TM_e22.WWF_int = 1;
    return 100;
}
void GrDestroyState(GStateHandle gs) { assert(gs == 100); }
void GrGetTransform(GStateHandle gs, TransMatrix *t) { (void)gs; *t=transform; }
dword GrGetLineColor(GStateHandle gs) { (void)gs; return 255; }
dword GrGetAreaColor(GStateHandle gs) { (void)gs; return 0xff0000UL; }
dword GrGetTextColor(GStateHandle gs) { (void)gs; return 0; }
dword GrGetLineWidth(GStateHandle gs) { (void)gs; return 2L << 16; }
word GrGetLineEnd(GStateHandle gs) { (void)gs; return 0; }
word GrGetLineJoin(GStateHandle gs) { (void)gs; return 0; }
dword GrGetMiterLimit(GStateHandle gs) { (void)gs; return 10L << 16; }
word GrGetMixMode(GStateHandle gs) { (void)gs; return MM_COPY; }
word GrGetLineStyle(GStateHandle gs) { (void)gs; return LS_SOLID; }
word GrGetLineMask(GStateHandle gs, DrawMask *m) { (void)gs;(void)m;return mask; }
word GrGetAreaMask(GStateHandle gs, DrawMask *m) { (void)gs;(void)m;return areaMask; }
word GrGetTextMask(GStateHandle gs, DrawMask *m) { return GrGetLineMask(gs,m); }
word GrGetFont(GStateHandle gs, dword *size) { (void)gs; *size=12L<<16; return 0; }
word GrGetTextStyle(GStateHandle gs) { (void)gs; return style; }
word GrGetTextMode(GStateHandle gs) { (void)gs; return TM_DRAW_BASE; }
dword GrFontMetrics(GStateHandle gs, word type) { (void)gs;(void)type;return 9L<<16; }
word GrTextWidth(GStateHandle gs, const char *s, word count) { (void)gs;(void)s;return count*7; }
void GrSetTextAttr(GStateHandle gs, const TextAttr *a) { (void)gs;style=a->styleSet; }
dword GrGetCurPos(GStateHandle gs) { (void)gs; return (dword)cpY<<16 | cpX; }
void GrMoveTo(GStateHandle gs, sword x, sword y) { (void)gs;cpX=(word)x;cpY=(word)y; }
void GrTransformWWFixed(GStateHandle gs, dword x, dword y, PointWWFixed *p)
{ (void)gs; p->PF_x.WWF_int=(sword)(x>>16);p->PF_y.WWF_int=(sword)(y>>16);p->PF_x.WWF_frac=p->PF_y.WWF_frac=0; }
byte GrGetGStringElement(GStateHandle gs, GStateHandle str, word size, void *b, word *actual)
{
    (void)gs; (void)str;
    if (cursor >= elementCount) { *actual=0; return 255; }
    *actual=elements[cursor].size;
    ready=1;
    if (size) { assert(size>=*actual); memcpy(b,elements[cursor].data,*actual); }
    return elements[cursor].data[0];
}
void GrSetGStringPos(GStateHandle str, byte type, word skip)
{ (void)str;(void)skip;assert(type==GSSPT_SKIP_1);++cursor;ready=0; }
word GrDrawGStringAtCP(GStateHandle gs, GStateHandle str, word flags, word *last)
{
    const byte *b;
    (void)gs;(void)str;assert(flags==GSC_ONE);
    if (cursor==elementCount) return GSRT_FAULT;
    if (!ready) { ready=1;*last=elements[cursor].data[0];
                 if (*last==GR_END_GSTRING) {cursor=0;ready=0;return GSRT_COMPLETE;}
                 return GSRT_ONE; }
    b=elements[cursor].data;
    /* Bitmap playback would consume callbacks/slices. The translator must
     * intercept it; the double deliberately refuses to hide that mistake. */
    assert(b[0]!=GR_DRAW_BITMAP && b[0]!=GR_DRAW_BITMAP_CP &&
           b[0]!=GR_FILL_BITMAP && b[0]!=GR_FILL_BITMAP_CP && b[0]!=GSE_BITMAP_SLICE);
    if (b[0]==GR_MOVE_TO) { cpX=u16(b+1);cpY=u16(b+3); }
    if (b[0]==GR_DRAW_LINE) { cpX=u16(b+5);cpY=u16(b+7); }
    ++cursor;
    if (cursor==elementCount) return GSRT_FAULT;
    *last=elements[cursor].data[0];
    if (*last==GR_END_GSTRING) {cursor=0;ready=0;return GSRT_COMPLETE;}
    return GSRT_ONE;
}
static void add(const void *data, word size)
{ assert(elementCount<64);elements[elementCount].data=data;elements[elementCount++].size=size; }
static MemHandle begin(void)
{
    MemHandle h;
    TransMatrix t;
    memset(&t,0,sizeof(t));t.TM_e11.WWF_int=t.TM_e22.WWF_int=1;
    h=PDFCREATE(0,0,595,842);assert(h);
    assert(PDFSTARTPAGE(h)==0);assert(PDFSETTRANSFORM(h,&t)==0);
    cursor=elementCount=0;return h;
}
static void discard(MemHandle h)
{ (void)PDFDESTROY(h);assert(!live); }
static void roundGStrings(void)
{
    byte ops[]={GR_DRAW_ROUND_RECT,GR_FILL_ROUND_RECT,
                GR_DRAW_ROUND_RECT_TO,GR_FILL_ROUND_RECT_TO};
    byte move[]={GR_MOVE_TO,10,0,20,0}, end[]={GR_END_GSTRING};
    byte full[]={0,10,0,10,0,20,0,110,0,80,0};
    byte to[]={0,10,0,110,0,80,0};
    byte malformed[12];
    char pdf[8192];
    word i, size, j;
    byte *record;
    MemHandle h;
    size_t n;
    for (i=0;i<4;++i) {
        record=i<2 ? full : to;size=i<2 ? sizeof(full) : sizeof(to);
        record[0]=ops[i];
        out=tmpfile();assert(out);h=begin();
        add(move,sizeof(move));add(record,size);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
        rewind(out);n=fread(pdf,1,sizeof(pdf)-1,out);assert(feof(out));pdf[n]=0;
        assert(strstr(pdf,"20 20 m\n"));
        assert(strstr(pdf,(i&1) ? "h f\n" : "h S\n"));
        assert(strstr(pdf,(i&1) ? "0 0 1 rg\n" : "1 0 0 RG\n"));fclose(out);
        /* 0xffff must stay unsigned and clamp to the integer half-height. */
        record[1]=record[2]=255;out=tmpfile();assert(out);h=begin();
        add(move,sizeof(move));add(record,size);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
        rewind(out);n=fread(pdf,1,sizeof(pdf)-1,out);assert(feof(out));pdf[n]=0;
        assert(strstr(pdf,"40 20 m\n"));fclose(out);record[1]=10;record[2]=0;
        out=tmpfile();assert(out);h=begin();mask=0;
        add(move,sizeof(move));add(record,size);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==((i&1) ? GSRT_COMPLETE : GSRT_FAULT));
        mask=SDM_100;discard(h);fclose(out);
        /* Both truncated and oversized operands must fail before decoding. */
        for (j=0;j<2;++j) {
            memcpy(malformed,record,size);malformed[size]=0;
            out=tmpfile();assert(out);h=begin();
            add(move,sizeof(move));add(malformed,(word)(size+(j ? 1 : -1)));
            add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
            discard(h);fclose(out);
        }
    }
}
static void putWord(byte *b, word n) { b[0]=(byte)n;b[1]=(byte)(n>>8); }
static word bitmapRecord(byte *b, byte op, word format, word width, word height,
                         word complex, word first, word rows, word dpi, const byte *data)
{
    word prefix=(op==GR_DRAW_BITMAP || op==GR_FILL_BITMAP) ? 7 : 3;
    word header=complex ? 20 : 6;
    word bytes=(word)((format==3 ? width*3 : (width+7)/8)*rows);
    byte *s=b+prefix;
    memset(b,0,prefix+header+bytes);b[0]=op;
    if(prefix==7) {putWord(b+1,7);putWord(b+3,9);}
    putWord(b+prefix-2,(word)(header+bytes));
    putWord(s,width);putWord(s+2,height);s[5]=(byte)(format | (complex ? 8 : 0));
    if(complex) {putWord(s+6,first);putWord(s+8,rows);putWord(s+12,20);
                putWord(s+16,dpi);putWord(s+18,dpi);}
    if(bytes)memcpy(s+header,data,bytes);
    return (word)(prefix+header+bytes);
}
static void bitmapGStrings(void)
{
    byte ops[]={GR_DRAW_BITMAP,GR_DRAW_BITMAP_CP,GR_FILL_BITMAP,GR_FILL_BITMAP_CP};
    byte pixels[]={255,0,0,0,255,0,0,0,255,255,255,0};
    byte bits[]={0x80,0x80,0x40,0};
    byte move[]={GR_MOVE_TO,246,255,4,0}, end[]={GR_END_GSTRING};
    byte line[]={GR_DRAW_LINE_TO,50,0,60,0};
    byte record[64],intro[64],slice0[64],slice1[64];
    char pdf[8192];
    word size,n0,n1,nh,i,j;
    MemHandle h;
    size_t n;
    for(i=0;i<4;++i) {
        size=bitmapRecord(record,ops[i],i<2 ? 3 : 0,i<2 ? 2 : 9,2,0,0,2,72,i<2 ? pixels : bits);
        out=tmpfile();assert(out);h=begin();add(move,sizeof(move));add(record,size);add(line,sizeof(line));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
        rewind(out);n=fread(pdf,1,sizeof(pdf)-1,out);assert(feof(out));pdf[n]=0;
        assert(strstr(pdf,(i&1) ? "1 0 0 1 -10 4 cm" : "1 0 0 1 7 9 cm"));
        assert(strstr(pdf,(i&1) ? "-10 4 m 50 60 l S" : "7 9 m 50 60 l S"));
        if(i<2)assert(strstr(pdf,"FF000000FF00\n0000FFFFFF00\n>\nEI"));
        else assert(strstr(pdf,"/IM true /BPC 1 /D [1 0]"));
        fclose(out);
        out=tmpfile();assert(out);h=begin();add(record,size);add(end,sizeof(end));
        mask=0; /* Image drawing must not depend on line attributes. */
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);mask=SDM_100;discard(h);fclose(out);
    }
    nh=bitmapRecord(intro,GR_DRAW_BITMAP,3,2,2,1,0,0,144,0);
    n0=bitmapRecord(slice0,GSE_BITMAP_SLICE,3,2,2,1,0,1,144,pixels);
    n1=bitmapRecord(slice1,GSE_BITMAP_SLICE,3,2,2,1,1,1,144,pixels+6);
    out=tmpfile();assert(out);h=begin();add(intro,nh);add(slice0,n0);add(slice1,n1);add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
    rewind(out);n=fread(pdf,1,sizeof(pdf)-1,out);assert(feof(out));pdf[n]=0;
    assert(strstr(pdf,"1 0 0 -1 0 1 cm\nBI /W 2 /H 2"));fclose(out);
    for(i=0;i<9;++i) {
        byte bad[64];word badSize=n1;
        memcpy(bad,slice1,n1);
        if(i==0)putWord(bad+3+6,0); /* overlapping/reordered rows */
        if(i==1)putWord(bad+3+16,72); /* changed DPI */
        if(i==2)bad[3+4]=1; /* compressed */
        if(i==3)bad[3+5]|=16; /* stored mask */
        if(i==4)badSize=bitmapRecord(bad,GSE_BITMAP_SLICE,3,2,2,1,1,0,144,0);
        if(i==5)putWord(bad+1,(word)(n1-4)); /* declared size mismatch */
        if(i==6)badSize=bitmapRecord(bad,GSE_BITMAP_SLICE,3,1,2,1,1,1,144,pixels);
        out=tmpfile();assert(out);h=begin();add(intro,nh);add(slice0,n0);
        if(i!=7)add(bad,badSize); /* missing final slice */
        if(i==8)add(slice1,n1); /* orphan slice after complete image */
        add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);
    }
    for(j=2;j<=4;++j) {
        out=tmpfile();assert(out);allocations=0;failAllocation=j;h=begin();
        add(intro,nh);add(slice0,n0);add(slice1,n1);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);failAllocation=0;fclose(out);
    }
    /* Every bitmap slice is freed before the next is allocated, even when
     * the source image and PDF output are larger than a 16-bit block. */
    {
        static byte slices[32][3095];
        static byte data[3072];
        word sizes[32];
        memset(data,0x45,sizeof(data));
        nh=bitmapRecord(intro,GR_DRAW_BITMAP,3,256,128,1,0,0,72,0);
        out=tmpfile();assert(out);h=begin();add(intro,nh);
        for(i=0;i<32;++i) {sizes[i]=bitmapRecord(slices[i],GSE_BITMAP_SLICE,3,256,128,1,(word)(i*4),4,72,data);add(slices[i],sizes[i]);}
        add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);fclose(out);
    }
    /* Empty strings are completed by the priming call, never executed twice. */
    out=tmpfile();assert(out);h=begin();add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);discard(h);fclose(out);
}

int main(int argc,char **argv)
{
    MemHandle h;
    byte save[]={GR_SAVE_STATE}, restore[]={GR_RESTORE_STATE};
    byte clip[]={GR_SET_CLIP_RECT,1,0, 20,0,20,0, 244,1,188,2};
    byte line[]={GR_DRAW_LINE,30,0,30,0, 44,1,120,0};
    byte rect[]={GR_FILL_RECT,60,0,180,0, 200,0,4,1};
    byte ellipse[]={GR_DRAW_ELLIPSE,60,0,44,1, 4,1,144,1};
    byte filled[]={GR_FILL_ELLIPSE,44,1,44,1, 144,1,194,1};
    byte txt[]={GR_DRAW_TEXT,60,0,150,0, 5,0, 'H','e','l','l','o'};
    byte ff[]={GR_NEW_PAGE,0}, end[]={GR_END_GSTRING};
    byte imageRecord[64], monoRecord[64];
    byte rgbPixels[]={255,0,0,0,255,0,0,0,255,255,255,0};
    byte monoPixels[]={0x80,0x80,0x40,0};
    word imageSize, monoSize;
    byte field[1+sizeof(PdfTextField)+sizeof(PdfTextRun)+5];
    PdfTextField *f=(PdfTextField *)(field+1);
    PdfTextRun *r=(PdfTextRun *)(field+1+sizeof(PdfTextField));
    unsigned i;
    assert(argc==2);assert(sizeof(PdfTextField)==14);assert(sizeof(TextAttr)==23);
    out=fopen(argv[1],"wb");assert(out);
    imageSize=bitmapRecord(imageRecord,GR_DRAW_BITMAP,3,2,2,1,0,2,2,rgbPixels);
    monoSize=bitmapRecord(monoRecord,GR_DRAW_BITMAP_CP,0,9,2,1,0,2,9,monoPixels);
    h=begin();add(imageRecord,imageSize);add(save,sizeof(save));add(clip,sizeof(clip));add(line,sizeof(line));
    add(rect,sizeof(rect));add(ellipse,sizeof(ellipse));add(filled,sizeof(filled));
    add(txt,sizeof(txt));add(restore,sizeof(restore));add(ff,sizeof(ff));
    assert(PDFGSTRING(h,1,GSC_NEW_PAGE)==GSRT_NEW_PAGE);
    assert(cursor==elementCount);assert(PDFENDPAGE(h)==0);
    assert(PDFSTARTPAGE(h)==0);
    { TransMatrix t;memset(&t,0,sizeof(t));t.TM_e11.WWF_int=t.TM_e22.WWF_int=1;
      t.TM_e31.DWF_int=10;assert(PDFSETTRANSFORM(h,&t)==0); }
    cursor=elementCount=0;memset(field,0,sizeof(field));
    field[0]=GR_DRAW_TEXT_FIELD;f->count=5;f->x.WBF_int=60;f->y.WBF_int=100;
    f->baseline.WBF_int=12;r->count=5;r->attr.styleSet=TS_BOLD;
    memcpy(field+sizeof(field)-5,"World",5);
    add(monoRecord,monoSize);add(field,sizeof(field));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,GSC_NEW_PAGE)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);fclose(out);

    /* Missing final marker must remain a fault (never EPS's fault->complete). */
    out=tmpfile();h=begin();add(line,sizeof(line));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);
    out=tmpfile();h=begin();mask=0;add(line,sizeof(line));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);mask=SDM_100;discard(h);fclose(out);
    /* Filled ellipses use area attributes even when the line mask is empty. */
    out=tmpfile();h=begin();mask=0;add(filled,sizeof(filled));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);mask=SDM_100;
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);fclose(out);
    out=tmpfile();h=begin();areaMask=0;add(filled,sizeof(filled));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);areaMask=SDM_100;discard(h);fclose(out);
    out=tmpfile();h=begin();add(restore,sizeof(restore));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);
    out=tmpfile();h=begin();add(save,sizeof(save));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);
    out=tmpfile();h=begin();clip[1]=PCT_UNION;add(clip,sizeof(clip));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);clip[1]=PCT_REPLACE;
    out=tmpfile();h=begin();
    { byte bitmap[]={80};add(bitmap,sizeof(bitmap));add(end,sizeof(end));
      assert(PDFGSTRING(h,1,0)==GSRT_FAULT); }
    discard(h);fclose(out);
    out=tmpfile();h=begin();add(ellipse,sizeof(ellipse)-1);add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h);fclose(out);
    out=tmpfile();h=begin();
    { TransMatrix t;memset(&t,0,sizeof(t));t.TM_e31.DWF_int=32768;
      assert(PDFSETTRANSFORM(h,&t)==PDF_LIMIT_ERROR); }
    discard(h);fclose(out);
    for(i=1;i<=2;++i) {
        out=tmpfile();allocations=0;failAllocation=i;
        if(i==1) { assert(!PDFCREATE(0,0,595,842));assert(!live); }
        else { h=begin();add(line,sizeof(line));add(end,sizeof(end));
               assert(PDFGSTRING(h,1,0)==GSRT_FAULT);discard(h); }
        failAllocation=0;fclose(out);
    }
    out=tmpfile();streamCalls=0;failStream=1;
    assert(!PDFCREATE(0,0,595,842));assert(!live);failStream=0;fclose(out);
    roundGStrings();bitmapGStrings();
    puts("gstring: pages, fields, shapes, bitmap/slice dispatch, clipping and cleanup passed");
    return 0;
}
