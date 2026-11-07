/* Exercise the actual GEOS adapter, dispatcher and serializer, with a small
 * kernel double. This does not substitute for a live spooler/GEOS smoke test. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../pdfGeos.c"
static struct { void *p; unsigned locks; } blocks[32];
static unsigned live, allocations, failAllocation, streamCalls, failStream;
static FILE *out;
static struct { const byte *data; word size; } elements[64];
static word elementCount, cursor, cpX, cpY, cpFracX, cpFracY, style;
static TransMatrix transform;
static word mask = SDM_100;
static word areaMask = SDM_100;
static word textMask = SDM_100, lineStyle = LS_SOLID;
static int ready;
static byte dashInfo[12];
static dword lineWidth=2L<<16;
static byte textPattern;
static word textMode = TM_DRAW_BASE;
static word fontID = FG_SANS_SERIF;
static dword fontSize = 12L << 16;
static unsigned widthWork;
static int fractionalMetrics;
static dword trackAdvance;
/* Native path snapshots are independent serialized records. This double
 * models Begin/End's saved state and the snapshot's transformed prefixes. */
typedef struct { byte bytes[4096]; word size; } MockPath;
typedef struct {
    MockPath paths[3];
    TransMatrix matrix;
    word x,y,xf,yf, lineStyle;
    dword lineWidth;
    byte dashInfo[12];
} MockFrame;
static MockPath paths[3], building;
static MockFrame savedFrames[32], buildingFrame;
static word saveDepth, buildingCombine;
static int mainStateLive, pathStateLive, deviceStateLive, capturing;
static TransMatrix deviceTransform;
static TransMatrix pathTransform;
static word pathX,pathY,pathXF,pathYF,pathCursor,pathReady;
static const byte *farPointer, *pathSource;
static TransMatrix savedPathTransform;
static word savedPathX,savedPathY,savedPathXF,savedPathYF;
static int pathSaved;
static void storeWord(byte *p,word n) {p[0]=(byte)n;p[1]=(byte)(n>>8);}
static void identity(TransMatrix *t)
{ memset(t,0,sizeof(*t));t->TM_e11.WWF_int=t->TM_e22.WWF_int=1; }
/* Independent row-vector matrix composition, using wider host arithmetic. */
static void compose(TransMatrix *current,const byte *record)
{
    TransMatrix a,b=*current;
    int64_t av[6],bv[6],v[6];
    int i;
    memcpy(&a,record+1,sizeof(a));
    av[0]=fixed(a.TM_e11);av[1]=fixed(a.TM_e12);av[2]=fixed(a.TM_e21);av[3]=fixed(a.TM_e22);
    av[4]=(int64_t)a.TM_e31.DWF_int*65536+a.TM_e31.DWF_frac;
    av[5]=(int64_t)a.TM_e32.DWF_int*65536+a.TM_e32.DWF_frac;
    bv[0]=fixed(b.TM_e11);bv[1]=fixed(b.TM_e12);bv[2]=fixed(b.TM_e21);bv[3]=fixed(b.TM_e22);
    bv[4]=(int64_t)b.TM_e31.DWF_int*65536+b.TM_e31.DWF_frac;
    bv[5]=(int64_t)b.TM_e32.DWF_int*65536+b.TM_e32.DWF_frac;
    v[0]=(av[0]*bv[0]+av[1]*bv[2])/65536;
    v[1]=(av[0]*bv[1]+av[1]*bv[3])/65536;
    v[2]=(av[2]*bv[0]+av[3]*bv[2])/65536;
    v[3]=(av[2]*bv[1]+av[3]*bv[3])/65536;
    v[4]=(av[4]*bv[0]+av[5]*bv[2])/65536+bv[4];
    v[5]=(av[4]*bv[1]+av[5]*bv[3])/65536+bv[5];
    for(i=0;i<4;++i){word bytes[2];bytes[0]=(word)v[i];bytes[1]=(word)(v[i]>>16);memcpy((byte *)current+i*4,bytes,4);}
    current->TM_e31.DWF_int=(sdword)(v[4]>>16);current->TM_e31.DWF_frac=(word)v[4];
    current->TM_e32.DWF_int=(sdword)(v[5]>>16);current->TM_e32.DWF_frac=(word)v[5];
}
static void snapshot(MockFrame *f)
{ memcpy(f->paths,paths,sizeof(paths));f->matrix=transform;
  f->x=cpX;f->y=cpY;f->xf=cpFracX;f->yf=cpFracY;
  f->lineStyle=lineStyle;f->lineWidth=lineWidth;memcpy(f->dashInfo,dashInfo,12); }
static void restore(const MockFrame *f)
{ memcpy(paths,f->paths,sizeof(paths));transform=f->matrix;
  cpX=f->x;cpY=f->y;cpFracX=f->xf;cpFracY=f->yf;
  lineStyle=f->lineStyle;lineWidth=f->lineWidth;memcpy(dashInfo,f->dashInfo,12); }
static word rawSize(const byte *b)
{
    switch(b[0]) {
    case GR_APPLY_TRANSFORM: case GR_SET_TRANSFORM: return 29;
    case GR_DRAW_POINT: case GR_MOVE_TO: case GR_DRAW_LINE_TO: case GR_DRAW_RECT_TO:
    case GR_DRAW_HLINE: case GR_DRAW_VLINE: return b[0]==GR_DRAW_HLINE || b[0]==GR_DRAW_VLINE ? 7 : 5;
    case GR_BEGIN_PATH: return 5;
    case GR_DRAW_LINE:case GR_DRAW_RECT:case GR_DRAW_ELLIPSE:
    case GR_FILL_RECT:case GR_FILL_ELLIPSE:case GR_MOVE_TO_WWFIXED: return 9;
    case GR_DRAW_ROUND_RECT:case GR_FILL_ROUND_RECT: return 11;
    case GR_DRAW_ROUND_RECT_TO:case GR_FILL_ROUND_RECT_TO:return 7;
    case GR_DRAW_ARC: case GR_FILL_ARC:return 15;
    case GR_DRAW_ARC_3POINT: case GR_FILL_ARC_3POINT:return 27;
    case GR_DRAW_ARC_3POINT_TO: case GR_FILL_ARC_3POINT_TO:
    case GR_DRAW_REL_ARC_3POINT_TO:return 19;
    case GR_DRAW_CURVE:return 17;
    case GR_DRAW_CURVE_TO:return 13;
    case GR_DRAW_REL_CURVE_TO:return 25;
    case GR_REL_MOVE_TO:case GR_DRAW_REL_LINE_TO:return 9;
    case GR_DRAW_SPLINE:case GR_DRAW_SPLINE_TO:return (word)(3+u16(b+1)*4);
    case GR_DRAW_POLYLINE:case GR_DRAW_POLYGON:return (word)(3+u16(b+1)*4);
    case GR_FILL_POLYGON:return (word)(4+u16(b+1)*4);
    case GR_BRUSH_POLYLINE:return (word)(5+u16(b+1)*4);
    default:return 1;
    }
}
static void append(MockPath *p,const void *data,word n)
{ assert(p->size+n<=sizeof(p->bytes));memcpy(p->bytes+p->size,data,n);p->size+=n; }
static void prefix(MockPath *p,word combine)
{
    byte op=GR_APPLY_TRANSFORM,move[5]={GR_MOVE_TO,0,0,0,0};
    byte begin[5]={GR_BEGIN_PATH,0,0,0,0};
    p->size=0;append(p,&op,1);append(p,&transform,sizeof(transform));
    storeWord(move+1,cpX);storeWord(move+3,cpY);append(p,move,5);
    storeWord(begin+1,combine);begin[3]=(byte)combine;append(p,begin,5);
}
static void combinePath(MockPath *destination,const MockPath *source,word combine,int rule,int window)
{
    word at;
    if(combine==PCT_NULL) {destination->size=0;return;}
    if(combine==PCT_UNION && !destination->size)return;
    if(combine==PCT_REPLACE)destination->size=0;
    if(!source->size)return;
    if(destination->size)--destination->size; /* replace trailing end marker */
    at=destination->size;append(destination,source->bytes,source->size);
    destination->bytes[at+37]=(byte)(combine | (window ? 8 : 0) |
                                   (rule>=0 ? 16+32*rule : 0));
}
static void rootPlayback(const byte *b,word size)
{
    byte suffix[2]={GR_END_PATH,GR_END_GSTRING};
    if(b[0]==GR_BEGIN_PATH) {
        if(u16(b+1)==PCT_NULL) {paths[0].size=0;return;}
        assert(!capturing);snapshot(&buildingFrame);buildingCombine=u16(b+1);
        prefix(&building,buildingCombine);capturing=1;return;
    }
    if(b[0]==GR_END_PATH) {
        if(capturing) {
            append(&building,suffix,2);capturing=0;restore(&buildingFrame);
            combinePath(paths,&building,buildingCombine,-1,0);
        }
        return;
    }
    if(capturing)append(&building,b,size);
    if(b[0]==GR_SAVE_STATE) {assert(saveDepth<32);snapshot(savedFrames+saveDepth++);}
    if(b[0]==GR_RESTORE_STATE) {assert(saveDepth);restore(savedFrames+--saveDepth);}
    if(b[0]==GR_SET_CLIP_RECT || b[0]==GR_SET_WIN_CLIP_RECT) {
        MockPath rect;
        byte record[9];record[0]=GR_DRAW_RECT;memcpy(record+1,b+3,8);
        prefix(&rect,PCT_REPLACE);append(&rect,record,9);append(&rect,suffix,2);
        combinePath(paths+(b[0]==GR_SET_CLIP_RECT ? 1 : 2),&rect,u16(b+1),0,b[0]==GR_SET_WIN_CLIP_RECT);
    }
    if(b[0]==GR_SET_CLIP_PATH || b[0]==GR_SET_WIN_CLIP_PATH)
        combinePath(paths+(b[0]==GR_SET_CLIP_PATH ? 1 : 2),paths,u16(b+2),b[1],b[0]==GR_SET_WIN_CLIP_PATH);
    if(b[0]==GR_APPLY_TRANSFORM)compose(&transform,b);
    if(b[0]==GR_SET_TRANSFORM)memcpy(&transform,b+1,sizeof(transform));
}
word MockSegment(const void *p) {farPointer=p;return 1;}
Boolean GrTestPath(GStateHandle gs,word type)
{assert(gs==100 && type<3);return paths[type].size!=0;}
MemHandle GrGetPath(GStateHandle gs,word type)
{
    MemHandle h;assert(gs==100 && type<3);
    h=MemAlloc(paths[type].size,HF_DYNAMIC,HAF_LOCK);
    if(h){memcpy(MemDeref(h),paths[type].bytes,paths[type].size);MemUnlock(h);}
    return h;
}
GStateHandle GrLoadGString(word segment,byte type,word offset)
{ assert(segment==1 && type==GST_PTR && !offset);pathSource=farPointer;pathCursor=pathReady=0;return 2; }
void GrDestroyGString(GStateHandle string,GStateHandle gs,byte type)
{assert(string==2 && !gs && type==GSKT_LEAVE_DATA);pathSource=0;}
void GrSaveState(GStateHandle gs)
{assert(gs==101 && !pathSaved);pathSaved=1;savedPathTransform=pathTransform;
 savedPathX=pathX;savedPathY=pathY;savedPathXF=pathXF;savedPathYF=pathYF;}
void GrRestoreState(GStateHandle gs)
{assert(gs==101 && pathSaved);pathSaved=0;pathTransform=savedPathTransform;
 pathX=savedPathX;pathY=savedPathY;pathXF=savedPathXF;pathYF=savedPathYF;}
void GrEndPath(GStateHandle gs)
{byte end[]={GR_END_PATH};assert(gs==100);rootPlayback(end,1);}
void GrSetNullTransform(GStateHandle gs)
{assert(gs==101);identity(&pathTransform);}
MemHandle MemAlloc(word size, word flags, word af)
{
    word i;
    (void)flags;
    if (++allocations == failAllocation) return 0;
    for (i = 1; i < 32; ++i) if (!blocks[i].p) {
        blocks[i].p = calloc(1, size); assert(blocks[i].p);
        blocks[i].locks = !!(af & HAF_LOCK); ++live; assert(live<=4); return i;
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
    (void)w;
    if(mainStateLive && (!pathSource || pathStateLive)) {
        assert(!deviceStateLive);deviceStateLive=1;identity(&deviceTransform);return 102;
    }
    if(mainStateLive){assert(!pathStateLive);pathStateLive=1;identity(&pathTransform);
        pathX=pathY=pathXF=pathYF=0;pathSaved=0;return 101;}
    mainStateLive=1;memset(paths,0,sizeof(paths));saveDepth=0;capturing=0;
    cpX = cpY = cpFracX = cpFracY = style = 0; ready = 0; textPattern = PT_SOLID;
    fontID=FG_SANS_SERIF;fontSize=12L<<16;textMode=TM_DRAW_BASE;
    lineStyle=LS_SOLID;lineWidth=2L<<16;memset(dashInfo,0,12);
    memset(&transform,0,sizeof(transform));
    transform.TM_e11.WWF_int = transform.TM_e22.WWF_int = 1;
    return 100;
}
void GrDestroyState(GStateHandle gs)
{ if(gs==102){assert(deviceStateLive);deviceStateLive=0;}
  else if(gs==101){assert(pathStateLive);pathStateLive=pathSaved=0;}
  else {assert(gs==100 && mainStateLive && !pathStateLive && !capturing);mainStateLive=0;} }
void GrGetTransform(GStateHandle gs, TransMatrix *t) { *t=gs==101 ? pathTransform : transform; }
void GrSetTransform(GStateHandle gs,const TransMatrix *t)
{ assert(gs==102 && deviceStateLive);deviceTransform=*t; }
void GrTransformDWFixed(GStateHandle gs,PointDWFixed *point)
{
    TransMatrix *t=gs==102 ? &deviceTransform : (gs==101 ? &pathTransform : &transform);
    int64_t x=(int64_t)point->PDF_x.DWF_int*65536+point->PDF_x.DWF_frac;
    int64_t y=(int64_t)point->PDF_y.DWF_int*65536+point->PDF_y.DWF_frac;
    int64_t dx=(x*fixed(t->TM_e11)+y*fixed(t->TM_e21))/65536+
               (int64_t)t->TM_e31.DWF_int*65536+t->TM_e31.DWF_frac;
    int64_t dy=(x*fixed(t->TM_e12)+y*fixed(t->TM_e22))/65536+
               (int64_t)t->TM_e32.DWF_int*65536+t->TM_e32.DWF_frac;
    point->PDF_x.DWF_int=(sdword)(dx>>16);point->PDF_x.DWF_frac=(word)dx;
    point->PDF_y.DWF_int=(sdword)(dy>>16);point->PDF_y.DWF_frac=(word)dy;
}
void GrUntransformDWFixed(GStateHandle gs,PointDWFixed *point)
{
    TransMatrix *t=gs==102 ? &deviceTransform : (gs==101 ? &pathTransform : &transform);
    double a=fixed(t->TM_e11)/65536.0,b=fixed(t->TM_e12)/65536.0;
    double c=fixed(t->TM_e21)/65536.0,d=fixed(t->TM_e22)/65536.0;
    double x=point->PDF_x.DWF_int+point->PDF_x.DWF_frac/65536.0;
    double y=point->PDF_y.DWF_int+point->PDF_y.DWF_frac/65536.0;
    int64_t dx,dy;
    x-=t->TM_e31.DWF_int+t->TM_e31.DWF_frac/65536.0;
    y-=t->TM_e32.DWF_int+t->TM_e32.DWF_frac/65536.0;
    assert(a*d-b*c);
    dx=(int64_t)((d*x-c*y)/(a*d-b*c)*65536);
    dy=(int64_t)((a*y-b*x)/(a*d-b*c)*65536);
    point->PDF_x.DWF_int=(sdword)(dx>>16);point->PDF_x.DWF_frac=(word)dx;
    point->PDF_y.DWF_int=(sdword)(dy>>16);point->PDF_y.DWF_frac=(word)dy;
}
dword GrGetLineColor(GStateHandle gs) { (void)gs; return 255; }
dword GrGetAreaColor(GStateHandle gs) { (void)gs; return 0xff0000UL; }
dword GrGetTextColor(GStateHandle gs) { (void)gs; return 0; }
dword GrMapColorIndex(GStateHandle gs, byte index)
{ assert(!gs);return (dword)index | (dword)index<<8 | (dword)index<<16; }
dword GrGetLineWidth(GStateHandle gs) { (void)gs; return lineWidth; }
void PDFGETDASH(GStateHandle gs,byte *dashP) { (void)gs;memcpy(dashP,dashInfo,12); }
word GrGetLineEnd(GStateHandle gs) { (void)gs; return 0; }
word GrGetLineJoin(GStateHandle gs) { (void)gs; return 0; }
dword GrGetMiterLimit(GStateHandle gs) { (void)gs; return 10L << 16; }
word GrGetMixMode(GStateHandle gs) { (void)gs; return MM_COPY; }
word GrGetLineStyle(GStateHandle gs) { (void)gs; return lineStyle; }
word GrGetLineMask(GStateHandle gs, DrawMask *m) { (void)gs;(void)m;return mask; }
word GrGetAreaMask(GStateHandle gs, DrawMask *m) { (void)gs;(void)m;return areaMask; }
word GrGetTextMask(GStateHandle gs, DrawMask *m) { (void)gs;(void)m;return textMask; }
word GRGETTEXTPATTERN(GStateHandle gs, MemHandle *pattern, word *size)
{
    (void)gs;*pattern=0;*size=0;
    if(textPattern==PT_CUSTOM_HATCH || textPattern==PT_CUSTOM_BITMAP) {
        *size=1;*pattern=MemAlloc(1,HF_DYNAMIC,HAF_ZERO_INIT);
    }
    return (word)(0xff00 | textPattern);
}
word GrGetFont(GStateHandle gs, dword *size) { (void)gs; *size=fontSize; return fontID; }
word GrGetTextStyle(GStateHandle gs) { (void)gs; return style; }
word GrGetTextMode(GStateHandle gs) { (void)gs; return textMode; }
dword GrFontMetrics(GStateHandle gs, word type)
{
    (void)gs;
    if(type==GFMI_UNDER_POS)return 10L*65536+16384;
    if(type==GFMI_STRIKE_POS)return 5L*65536+32768;
    if(type==GFMI_UNDER_THICKNESS)return 32768;
    return 9L<<16;
}
dword PDFTEXTWIDTHFIXED(GStateHandle gs, const char *s, word count)
{
    dword width=0;
    word i;
    byte c, previous=0;
    widthWork+=count;
    for(i=0;i<count && s[i];++i) {
        c=(byte)s[i];
        if(c==C_OPTHYPHEN) {
            if(!(textMode & TM_DRAW_OPTIONAL_HYPHENS) || (i+1<count && s[i+1])) {
                previous=c;continue;
            }
            c='-';
        }
        width+=GrCharWidth(gs,c)+trackAdvance;
        if(fractionalMetrics && previous=='A' && c=='V')width-=65536;
        previous=c;
    }
    return width;
}
dword GrCharWidth(GStateHandle gs, word ch)
{
    (void)gs;
    if(ch=='-')return 3L*65536+32768;
    if(ch==C_NONBRKHYPHEN)return 4L*65536+16384;
    return fractionalMetrics ? 7L*65536+32768 : 7L*65536;
}
word GrTextWidth(GStateHandle gs, const char *s, word count) { (void)gs;(void)s;return count*7; }
void GrSetTextAttr(GStateHandle gs, const TextAttr *a) { (void)gs;style=(style & ~a->styleClear) | a->styleSet;textMask=a->mask;textPattern=a->pattern[0];fontID=a->font;
  fontSize=(dword)(word)a->size.WBF_int*65536UL+(dword)a->size.WBF_frac*256;
  textMode=(textMode & ~a->modeClear) | a->modeSet; }
void GrGetCurPosWWFixed(GStateHandle gs, PointWWFixed *point)
{ point->PF_x.WWF_int=(sword)(gs==101 ? pathX : cpX);point->PF_y.WWF_int=(sword)(gs==101 ? pathY : cpY);
  point->PF_x.WWF_frac=gs==101 ? pathXF : cpFracX;point->PF_y.WWF_frac=gs==101 ? pathYF : cpFracY; }
dword GrGetCurPos(GStateHandle gs) { return gs==101 ? (dword)pathY<<16 | pathX : (dword)cpY<<16 | cpX; }
void GrMoveTo(GStateHandle gs, sword x, sword y) { (void)gs;cpX=(word)x;cpY=(word)y;cpFracX=cpFracY=0; }
void GrMoveToWWFixed(GStateHandle gs,dword x,dword y)
{if(gs==101){pathX=(word)(x>>16);pathXF=(word)x;pathY=(word)(y>>16);pathYF=(word)y;}
 else {cpX=(word)(x>>16);cpFracX=(word)x;cpY=(word)(y>>16);cpFracY=(word)y;}}
void GrTransformWWFixed(GStateHandle gs, dword x, dword y, PointWWFixed *p)
{ (void)gs; p->PF_x.WWF_int=(sword)(x>>16);p->PF_y.WWF_int=(sword)(y>>16);p->PF_x.WWF_frac=p->PF_y.WWF_frac=0; }
byte GrGetGStringElement(GStateHandle gs, GStateHandle str, word size, void *b, word *actual)
{
    (void)gs;
    if(str==2) { *actual=rawSize(pathSource+pathCursor);pathReady=1;
        if(size){assert(size>=*actual);memcpy(b,pathSource+pathCursor,*actual);}
        return pathSource[pathCursor]; }
    if (cursor >= elementCount) { *actual=0; return 255; }
    *actual=elements[cursor].size;
    ready=1;
    if (size) { assert(size>=*actual); memcpy(b,elements[cursor].data,*actual); }
    return elements[cursor].data[0];
}
void GrSetGStringPos(GStateHandle str, byte type, word skip)
{ (void)skip;assert(type==GSSPT_SKIP_1);
  if(str==2){pathCursor+=rawSize(pathSource+pathCursor);pathReady=0;}
  else {++cursor;ready=0;} }
static void arcPen(GStateHandle gs,const byte *b)
{
    double rx=(s16(b+7)-s16(b+3))/2.0,ry=(s16(b+9)-s16(b+5))/2.0;
    double a=s16(b+(u16(b+1)==ACT_OPEN ? 13 : 11))*3.14159265358979323846/180;
    double t=atan2(rx*sin(a),ry*cos(a));
    sword x=(sword)floor(s16(b+3)+rx+rx*cos(t)+0.5);
    sword y=(sword)floor(s16(b+5)+ry-ry*sin(t)+0.5);
    /* ArcSetCurPos rounds the selected endpoint to signed word coordinates. */
    GrMoveToWWFixed(gs,(dword)(word)x<<16,(dword)(word)y<<16);
}
word GrDrawGStringAtCP(GStateHandle gs, GStateHandle str, word flags, word *last)
{
    const byte *b;
    assert(flags==GSC_ONE);
    if(str==2) {
        b=pathSource+pathCursor;assert(gs==101);
        if(!pathReady){pathReady=1;*last=b[0];return b[0]==GR_END_GSTRING ? GSRT_COMPLETE : GSRT_ONE;}
        if(b[0]==GR_APPLY_TRANSFORM)compose(&pathTransform,b);
        if(b[0]==GR_SET_TRANSFORM)memcpy(&pathTransform,b+1,sizeof(pathTransform));
        if(b[0]==GR_MOVE_TO || b[0]==GR_DRAW_LINE_TO){pathX=u16(b+1);pathY=u16(b+3);}
        if(b[0]==GR_DRAW_LINE){pathX=u16(b+5);pathY=u16(b+7);}
        if(b[0]==GR_MOVE_TO_WWFIXED)GrMoveToWWFixed(gs,(dword)operandFixed(b+1),(dword)operandFixed(b+5));
        if(b[0]==GR_REL_MOVE_TO || b[0]==GR_DRAW_REL_LINE_TO)
            GrMoveToWWFixed(gs,((dword)pathX<<16 | pathXF)+(dword)operandFixed(b+1),
                               ((dword)pathY<<16 | pathYF)+(dword)operandFixed(b+5));
        if(b[0]==GR_DRAW_CURVE){pathX=u16(b+13);pathY=u16(b+15);}
        if(b[0]==GR_DRAW_CURVE_TO){pathX=u16(b+9);pathY=u16(b+11);}
        if(b[0]==GR_DRAW_ARC || b[0]==GR_FILL_ARC)arcPen(gs,b);
        if(b[0]==GR_DRAW_ARC_3POINT || b[0]==GR_FILL_ARC_3POINT) {
            word at=u16(b+1) ? 19 : 3;
            GrMoveToWWFixed(gs,(dword)operandFixed(b+at),(dword)operandFixed(b+at+4));
        }
        if(b[0]==GR_DRAW_POINT){pathX=u16(b+1);pathY=u16(b+3);pathXF=pathYF=0;}
        if(b[0]==GR_BRUSH_POLYLINE && u16(b+1)) {
            word at=(word)(5+(u16(b+1)-1)*4);pathX=u16(b+at);pathY=u16(b+at+2);pathXF=pathYF=0;
        }
        pathCursor+=rawSize(b);*last=pathSource[pathCursor];
        if(*last==GR_END_GSTRING){pathCursor=pathReady=0;return GSRT_COMPLETE;}
        return GSRT_ONE;
    }
    if (cursor==elementCount) return GSRT_FAULT;
    if (!ready) { ready=1;*last=elements[cursor].data[0];
                 if (*last==GR_END_GSTRING) {cursor=0;ready=0;return GSRT_COMPLETE;}
                 return GSRT_ONE; }
    b=elements[cursor].data;
    /* Bitmap playback would consume callbacks/slices. The translator must
     * intercept it; the double deliberately refuses to hide that mistake. */
    assert(b[0]!=GR_DRAW_BITMAP && b[0]!=GR_DRAW_BITMAP_CP &&
           b[0]!=GR_FILL_BITMAP && b[0]!=GR_FILL_BITMAP_CP && b[0]!=GSE_BITMAP_SLICE);
    rootPlayback(b,elements[cursor].size);
    if(b[0]==GR_SET_LINE_WIDTH)lineWidth=(dword)operandFixed(b+1);
    if(b[0]==GR_SET_LINE_STYLE) {
        static const byte counts[]={0,1,1,2,3};
        static const byte values[][6]={{0},{4,4},{1,2},{4,4,1,4},{4,4,1,4,1,4}};
        lineStyle=b[1];dashInfo[0]=counts[lineStyle];dashInfo[1]=b[2];
        memset(dashInfo+2,0,10);memcpy(dashInfo+2,values[lineStyle],dashInfo[0]*2);
    }
    if(b[0]==GR_SET_CUSTOM_LINE_STYLE) {
        lineStyle=LS_CUSTOM;dashInfo[0]=(byte)u16(b+3);dashInfo[1]=(byte)u16(b+1);
        memcpy(dashInfo+2,b+5,dashInfo[0]*2);
    }
    if (b[0]==GR_SET_TEXT_ATTR) GrSetTextAttr(gs,(const TextAttr *)(b+1));
    if (b[0]==GR_MOVE_TO) { cpX=u16(b+1);cpY=u16(b+3);cpFracX=cpFracY=0; }
    if (b[0]==GR_MOVE_TO_WWFIXED) {
        cpFracX=u16(b+1);cpX=u16(b+3);cpFracY=u16(b+5);cpY=u16(b+7);
    }
    if (b[0]==GR_DRAW_ARC || b[0]==GR_FILL_ARC)arcPen(gs,b);
    if(b[0]==GR_DRAW_ARC_3POINT || b[0]==GR_FILL_ARC_3POINT) {
        word at=u16(b+1) ? 19 : 3;
        GrMoveToWWFixed(gs,(dword)operandFixed(b+at),(dword)operandFixed(b+at+4));
    }
    if(capturing && (b[0]==GR_DRAW_ARC_3POINT_TO || b[0]==GR_FILL_ARC_3POINT_TO ||
       b[0]==GR_DRAW_REL_ARC_3POINT_TO) && u16(b+1))
        GrMoveToWWFixed(gs,(dword)operandFixed(b+11),(dword)operandFixed(b+15));
    if (b[0]==GR_DRAW_POINT)GrMoveTo(gs,s16(b+1),s16(b+3));
    if(b[0]==GR_BRUSH_POLYLINE && u16(b+1)) {
        word at=(word)(5+(u16(b+1)-1)*4);GrMoveTo(gs,s16(b+at),s16(b+at+2));
    }
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
static void putFixed(byte *b, PdfFixed n) { putWord(b,(word)n);putWord(b+2,(word)((dword)n>>16)); }
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

/* Reproduce the four functional audit defects through the actual adapter. */
static void auditRegressions(void)
{
    byte end[] = {GR_END_GSTRING};
    byte txt[] = {GR_DRAW_TEXT,60,0,60,0,3,0,'a',0xb2,'b'};
    byte field[1+sizeof(PdfTextField)+sizeof(PdfTextRun)+1];
    byte attr[25];
    /* Actual SBCS text field captured by Swat: solid 14-point bold PERSONAL. */
    byte personal[]={
        0x3e,8,0,0,0,0,0,0,0,0,10,0,78,0,0,8,0,
        0,0,0,0,0x19,0,0,0x20,0xff,8,0,0,0,0,4,0x12,
        0,14,0,0,0,100,100,0xd3,'P','E','R','S','O','N','A','L'
    };
    /* Saved flags contain unused bits (0x24), but no auto-hyphen. */
    byte lastName[]={
        0x3e,11,0,0,3,0,0,21,0,0,9,0,0xee,1,0x24,11,0,
        0,0,0,0,0x19,0,0,0,0xff,8,0,0,0,0,0,0x12,
        0,8,0,0,0,100,100,0xd8,'L','A','S','T',' ','N','A','M','E',' ',' '
    };
    PdfTextField *f = (PdfTextField *)(field+1);
    PdfTextRun *r = (PdfTextRun *)(field+1+sizeof(PdfTextField));
    char captured[8192];
    size_t n;
    word i;
    MemHandle h;
    out=tmpfile();assert(out);h=begin();
    add(personal,sizeof(personal));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"BT /F1 14 Tf") && strstr(captured,"(P)") && strstr(captured,"(L)"));
    fclose(out);
    out=tmpfile();assert(out);h=begin();
    add(lastName,sizeof(lastName));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"BT /F0 8 Tf") && strstr(captured,"(L)") && strstr(captured,"(E)"));
    fclose(out);
    lastName[14] |= 1;
    out=tmpfile();assert(out);h=begin();
    add(lastName,sizeof(lastName));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"80 30 Tm (-)"));fclose(out);
    memset(field,0,sizeof(field));field[0]=GR_DRAW_TEXT_FIELD;
    f->count=1;r->count=1;r->attr.mask=SDM_100;
    r->attr.font=FG_SANS_SERIF;r->attr.size.WBF_int=12;
    field[sizeof(field)-1]='X';
    /* TextAttr patterns enter both through text fields and standalone attrs. */
    for(i=0;i<3;++i) {
        out=tmpfile();assert(out);h=begin();r->attr.pattern[0]=i==2 ? PT_CUSTOM_HATCH : 1;
        if(i) {
            memset(attr,0,sizeof(attr));attr[0]=GR_SET_TEXT_ATTR;
            memcpy(attr+1,&r->attr,sizeof(TextAttr));
            add(attr,sizeof(attr));add(txt,sizeof(txt));
        } else add(field,sizeof(field));
        add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
        assert(PDFDESTROY(h)==PDF_UNSUPPORTED);assert(!live);fclose(out);
    }
    r->attr.pattern[0]=PT_SOLID;
    /* Text visibility must not follow the area mask in either direction. */
    for(i=0;i<2;++i) {
        out=tmpfile();assert(out);h=begin();
        textMask=i ? SDM_100 : SDM_0;areaMask=i ? SDM_0 : SDM_100;
        add(txt,sizeof(txt));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(!!strstr(captured," Tj ET") == !!i);fclose(out);
    }
    areaMask=textMask=SDM_100;
    out=tmpfile();assert(out);h=begin();
    add(txt,sizeof(txt));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"BT /F12 12 Tf"));
    assert(strstr(captured,"(\\243) Tj ET"));fclose(out);
    /* Fail only the finalization write, after the last page has succeeded. */
    out=tmpfile();assert(out);h=begin();add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==PDF_OK);
    failStream=streamCalls+1;
    assert(PDFDESTROY(h)==PDF_IO_ERROR);assert(!live);failStream=0;fclose(out);
}

static void textPrecision(void)
{
    byte field[70], end[]={GR_END_GSTRING};
    byte move[]={GR_MOVE_TO_WWFIXED,0,64,60,0,0,128,100,0};
    byte cpText[]={GR_DRAW_TEXT_CP,1,0,'Z'};
    byte attr[25];
    PdfTextField *f=(PdfTextField *)(field+1);
    PdfTextRun *first=(PdfTextRun *)(field+15);
    PdfTextRun *second=(PdfTextRun *)(field+43);
    char captured[8192];
    size_t n;
    MemHandle h;
    word i;
    memset(field,0,sizeof(field));field[0]=GR_DRAW_TEXT_FIELD;
    f->count=3;f->x.WBF_int=60;f->x.WBF_frac=64;
    f->y.WBF_int=100;f->y.WBF_frac=128;
    f->baseline.WBF_int=12;f->baseline.WBF_frac=192;
    first->count=2;first->attr.mask=SDM_100;
    second->count=1;second->attr.mask=SDM_100;
    first->attr.font=second->attr.font=FG_SANS_SERIF;
    first->attr.size.WBF_int=second->attr.size.WBF_int=12;
    field[41]='A';field[42]='V';field[69]='W';
    for(i=0;i<3;++i) {
        out=tmpfile();assert(out);h=begin();fractionalMetrics=1;widthWork=0;
        trackAdvance=i==2 ? 16384 : 0;
        first->attr.mask=i==1 ? SDM_0 : SDM_100;
        add(field,sizeof(field));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(widthWork==5); /* Linear work, including a hidden first run. */
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        if(i==2) {
            assert(strstr(captured,"60.5 113.25 Tm (A)"));
            assert(strstr(captured,"67.25 113.25 Tm (V)"));
            assert(strstr(captured,"75 113.25 Tm (W)"));
        } else {
            if(!i) {
                assert(strstr(captured,"60.25 113.25 Tm (A)"));
                assert(strstr(captured,"66.75 113.25 Tm (V)"));
            } else assert(!strstr(captured,"Tm (A)"));
            assert(strstr(captured,"74.25 113.25 Tm (W)"));
        }
        fclose(out);
    }
    fractionalMetrics=0;trackAdvance=0;
    for(i=0;i<3;++i) {
        static const word families[]={FG_SANS_SERIF,FG_SERIF,FG_MONO};
        static const char *fonts[]={"BT /F0 ","BT /F4 ","BT /F8 "};
        out=tmpfile();assert(out);h=begin();
        first->attr.font=second->attr.font=families[i];
        first->attr.mask=SDM_100;add(field,sizeof(field));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(strstr(captured,fonts[i]));fclose(out);
    }
    /* Both native bars share text color/mask. Cap the first run's bars
     * without clamping the next run's fractional pen position. */
    first->attr.font=second->attr.font=FG_SANS_SERIF;
    first->attr.styleClear=second->attr.styleClear=0xff;
    first->attr.styleSet=TS_UNDERLINE | TS_STRIKE_THRU;
    f->limit=72;fractionalMetrics=1;areaMask=SDM_0;
    for(i=0;i<2;++i) {
        out=tmpfile();assert(out);h=begin();
        first->attr.mask=i ? SDM_0 : SDM_100;
        add(field,sizeof(field));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        if(!i) {
            assert(strstr(captured,"60.25 114.5 11.75 0.5 re f"));
            assert(strstr(captured,"60.25 109.75 11.75 0.5 re f"));
        } else assert(!strstr(captured,"re f"));
        assert(strstr(captured,"74.25 113.25 Tm (W)"));fclose(out);
    }
    fractionalMetrics=0;areaMask=SDM_100;
    first->attr.mask=SDM_100;first->attr.styleSet=TS_UNDERLINE;
    memset(attr,0,sizeof(attr));attr[0]=GR_SET_TEXT_ATTR;
    memcpy(attr+1,&first->attr,sizeof(TextAttr));
    out=tmpfile();assert(out);h=begin();
    add(attr,sizeof(attr));add(move,sizeof(move));add(cpText,sizeof(cpText));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"60.25 100.5 Tm (Z)"));
    assert(strstr(captured,"60.25 101.75 7 0.5 re f"));fclose(out);style=0;
}

static void textHyphens(void)
{
    byte field[72], end[]={GR_END_GSTRING};
    PdfTextField *f=(PdfTextField *)(field+1);
    PdfTextRun *first=(PdfTextRun *)(field+15);
    PdfTextRun *second=(PdfTextRun *)(field+45);
    char captured[8192];
    size_t n;
    MemHandle h;
    word i;
    memset(field,0,sizeof(field));field[0]=GR_DRAW_TEXT_FIELD;
    f->count=5;f->x.WBF_int=60;f->x.WBF_frac=64;
    f->y.WBF_int=100;f->baseline.WBF_int=12;f->limit=0xffff;
    first->count=4;second->count=1;
    first->attr.mask=second->attr.mask=SDM_100;
    first->attr.styleClear=second->attr.styleClear=0xff;
    first->attr.styleSet=TS_UNDERLINE;second->attr.styleSet=TS_BOLD;
    first->attr.font=FG_SANS_SERIF;second->attr.font=FG_MONO;
    first->attr.size.WBF_int=second->attr.size.WBF_int=12;
    first->attr.modeClear=second->attr.modeClear=0xff;
    first->attr.modeSet=second->attr.modeSet=TM_DRAW_BASE;
    field[41]='A';field[42]=C_OPTHYPHEN;field[43]='V';field[44]=C_OPTHYPHEN;
    field[71]='W';fractionalMetrics=1;trackAdvance=16384;
    for(i=0;i<3;++i) {
        first->attr.modeSet=TM_DRAW_BASE | (i ? TM_DRAW_OPTIONAL_HYPHENS : 0);
        f->flags=i==2 ? 0x25 : 0x24;
        out=tmpfile();assert(out);h=begin();add(field,sizeof(field));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(strstr(captured,"68.25 112 Tm (V)"));
        assert(!strstr(captured,"\\037"));
        if(!i) {
            assert(!strstr(captured,"Tm (-)"));
            assert(strstr(captured,"76 112 Tm (W)"));
        } else {
            assert(strstr(captured,"76 112 Tm (-)"));
            assert(strstr(captured,"79.75 112 Tm (W)"));
        }
        if(i==2)assert(strstr(captured,"BT /F9 12 Tf 1 0 0 -1 87.5 112 Tm (-)"));
        fclose(out);
    }
    /* Keep native nonbreaking-hyphen advance, even if its font width differs. */
    field[41]=C_NONBRKHYPHEN;field[42]='X';field[43]='Y';field[44]='Z';f->flags=0;
    out=tmpfile();assert(out);h=begin();add(field,sizeof(field));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"60.5 112 Tm (-)"));
    assert(strstr(captured,"65 112 Tm (X)"));fclose(out);
    fractionalMetrics=0;trackAdvance=0;
}

static void deviceGStrings(void)
{
    byte brush[]={GR_BRUSH_POLYLINE,2,0,4,2,12,0,12,0,24,0,12,0};
    byte dot[]={GR_DRAW_POINT,12,0,12,0},end[]={GR_END_GSTRING};
    byte record[29]={GR_SET_TRANSFORM};
    byte start[]={GR_BEGIN_PATH,PCT_REPLACE,0,0,0},finish[]={GR_END_PATH},stroke[]={GR_DRAW_PATH};
    TransMatrix t;
    MemHandle h;
    char captured[8192];
    size_t n;
    unsigned i;
    for(i=0;i<3;++i) {
        out=tmpfile();assert(out);h=PDFCREATE(0,0,595,842);assert(h);
        assert(PDFSTARTPAGE(h)==0);cursor=elementCount=0;
        identity(&t);
        if(i) {
            /* Rotate/scale the physical page and scale the GString. The nib
             * remains four by two device pixels, rather than scaling with it. */
            t.TM_e11.WWF_int=t.TM_e22.WWF_int=0;t.TM_e12.WWF_int=2;t.TM_e21.WWF_int=-1;
            t.TM_e31.DWF_int=100;
        }
        assert(PDFSETTRANSFORM(h,&t)==PDF_OK);
        if(i) {
            identity(&t);t.TM_e11.WWF_int=2;t.TM_e22.WWF_int=3;
            memcpy(record+1,&t,sizeof(t));add(record,sizeof(record));
        }
        if(i==2)add(start,5);
        add(brush,sizeof(brush));
        if(i==2){add(finish,1);add(stroke,1);}
        else {lineStyle=LS_DOTTED;lineWidth=500L*65536;}
        add(dot,sizeof(dot));add(end,1);
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);
        assert(!deviceStateLive && !live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;fclose(out);
        assert(strstr(captured,"0.24 0 0 0.24 0 0 cm"));
        assert(strstr(captured,i ? "267 200 4 202 re f" : "50 50 54 2 re f"));
        assert(strstr(captured,i ? "267 200 1 1 re f" : "50 50 1 1 re f"));
    }
}
static void threePointGStrings(void)
{
    byte arc[27],move[9]={GR_MOVE_TO_WWFIXED},end[]={GR_END_GSTRING};
    byte tail[]={GR_DRAW_LINE_TO,40,0,40,0};
    byte beginPath[]={GR_BEGIN_PATH,PCT_REPLACE,0,0,0},endPath[]={GR_END_PATH};
    byte stroke[]={GR_DRAW_PATH};
    const byte ops[]={GR_DRAW_ARC_3POINT,GR_FILL_ARC_3POINT,GR_DRAW_ARC_3POINT_TO,
                      GR_FILL_ARC_3POINT_TO,GR_DRAW_REL_ARC_3POINT_TO};
    char captured[4096];
    size_t n;
    unsigned i;
    word size;
    MemHandle h;
    putFixed(move+1,200L*65536);putFixed(move+5,100L*65536);
    for(i=0;i<sizeof(ops);++i) {
        memset(arc,0,sizeof(arc));arc[0]=ops[i];arc[1]=ACT_CHORD;
        size=i<2 ? 27 : 19;
        if(i<2) { putFixed(arc+3,200L*65536);putFixed(arc+7,100L*65536); }
        putFixed(arc+(i<2 ? 11 : 3),(i==4 ? -100L : 100L)*65536);
        putFixed(arc+(i<2 ? 15 : 7),(i==4 ? -100L : 0L)*65536);
        putFixed(arc+(i<2 ? 19 : 11),(i==4 ? -200L : 0L)*65536);
        putFixed(arc+(i<2 ? 23 : 15),i==4 ? 0 : 100L*65536);
        out=tmpfile();assert(out);h=begin();add(move,9);add(arc,size);add(tail,5);add(end,1);
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;fclose(out);
        assert(strstr(captured,"200 100 m") && strstr(captured,"100 0 c"));
        assert(strstr(captured,i==4 ? "-200 0 m 40 40 l" : "0 100 m 40 40 l"));
        out=tmpfile();assert(out);h=begin();add(move,9);add(beginPath,5);add(arc,size);
        add(tail,5);add(endPath,1);add(stroke,1);add(end,1);
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);
        assert(!live && !pathStateLive && !mainStateLive);fclose(out);
    }
    for(i=0;i<3;++i) {
        arc[0]=i==2 ? GR_FILL_ARC_3POINT_TO : GR_DRAW_ARC_3POINT_TO;
        arc[1]=i==1 ? 3 : ACT_OPEN;
        out=tmpfile();assert(out);h=begin();add(arc,i ? 19 : 18);add(end,1);
        assert(PDFGSTRING(h,1,0)==GSRT_FAULT);assert(PDFDESTROY(h)==PDF_STATE_ERROR);
        assert(!live);fclose(out);
    }
}
static void arcPointGStrings(void)
{
    byte arc[]={GR_DRAW_ARC,ACT_OPEN,0,10,0,20,0,210,0,120,0,0,0,90,0};
    byte dot[]={GR_DRAW_POINT,25,0,35,0},dotCP[]={GR_DRAW_POINT_CP};
    byte end[]={GR_END_GSTRING},lineTo[]={GR_DRAW_LINE_TO,10,0,20,0};
    byte beginPath[]={GR_BEGIN_PATH,PCT_REPLACE,0,0,0},endPath[]={GR_END_PATH};
    byte close[]={GR_CLOSE_SUB_PATH},stroke[]={GR_DRAW_PATH};
    MemHandle h;
    char captured[4096];
    size_t n;
    unsigned i;
    out=tmpfile();assert(out);h=begin();mask=0;lineStyle=LS_CUSTOM;
    add(dot,sizeof(dot));add(dotCP,1);add(end,1);
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;fclose(out);
    assert(strstr(captured,"0 0 1 rg") && strstr(captured,"104 146 1 1 re f"));
    mask=SDM_100;lineStyle=LS_SOLID;
    /* An open arc and LineTo share a subpath; CloseSubPath restores its start. */
    out=tmpfile();assert(out);h=begin();add(beginPath,5);add(arc,15);add(lineTo,5);
    add(close,1);add(lineTo,5);add(endPath,1);add(stroke,1);add(end,1);
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;fclose(out);
    assert(strstr(captured,"210 70 m") && strstr(captured,"110 20 c"));
    assert(strstr(captured,"10 20 l\n") && !strstr(captured,"110 20 m"));
    for(i=0;i<3;++i) {
        out=tmpfile();assert(out);h=begin();
        arc[0]=i==1 ? GR_FILL_ARC : GR_DRAW_ARC;arc[1]=i==2 ? 3 : ACT_OPEN;
        add(arc,i ? 15 : 14);add(end,1);
        assert(PDFGSTRING(h,1,0)==GSRT_FAULT);assert(PDFDESTROY(h)==PDF_STATE_ERROR);
        assert(!live && !pathStateLive && !mainStateLive);fclose(out);
    }
}
static void maskedGStrings(void)
{
    byte record[40], indexed[41], end[]={GR_END_GSTRING};
    byte *dataP;
    byte pixels[]={0x80,255,0,0,0,255,0,0x40,0,0,255,255,255,0};
    char captured[8192];
    size_t n;
    word codec, row, pos;
    MemHandle h;
    for(codec=0;codec<=2;++codec) {
        memset(record,0,sizeof(record));record[0]=GR_DRAW_BITMAP;
        putWord(record+7,2);putWord(record+9,2);record[11]=(byte)codec;record[12]=0x13;pos=13;
        for(row=0;row<2;++row) {
            if(codec)record[pos++]=codec==1 ? 6 : 0xfe;
            memcpy(record+pos,pixels+row*7,7);pos+=7;
            if(codec==2)record[pos++]=0x60;
        }
        putWord(record+5,(word)(pos-7));
        out=tmpfile();assert(out);h=begin();add(record,pos);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(strstr(captured,"0 0 1 1 re\n") && strstr(captured,"1 0 1 1 re\n"));
        assert(strstr(captured,"FF000000FF00\n>\nEI"));fclose(out);
    }
    memset(indexed,0,sizeof(indexed));indexed[0]=GR_DRAW_BITMAP;putWord(indexed+5,34);
    dataP=indexed+7;putWord(dataP,2);putWord(dataP+2,2);dataP[5]=0x5a;putWord(dataP+8,2);
    putWord(dataP+12,28);putWord(dataP+14,20);putWord(dataP+16,72);putWord(dataP+18,72);
    putWord(dataP+20,2);dataP[22]=255;dataP[26]=255;
    dataP[28]=0x80;dataP[30]=255;dataP[31]=0x40;dataP[32]=255;dataP[33]=1;
    out=tmpfile();assert(out);h=begin();add(indexed,sizeof(indexed));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"/Indexed /DeviceRGB 255 <FF000000FF00"));
    assert(strstr(captured,"00FF\n>\nEI") && strstr(captured,"FF01\n>\nEI"));fclose(out);
    out=tmpfile();assert(out);h=begin();failAllocation=allocations+2;
    add(record,pos);add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
    assert(PDFDESTROY(h)==PDF_LIMIT_ERROR);assert(!live);failAllocation=0;fclose(out);
}

static void compressedGStrings(void)
{
    byte record[32], end[]={GR_END_GSTRING};
    byte wide[]={GR_DRAW_BITMAP,0,0,0,0,8,0,129,0,1,0,1,2,128,0x12};
    byte pixels[]={255,0,0,0,255,0,0,0,255,255,255,0};
    byte *data;
    char captured[8192];
    size_t n;
    word codec, row, pos;
    MemHandle h;
    for(codec=1;codec<=2;++codec) {
        memset(record,0,sizeof(record));record[0]=GR_DRAW_BITMAP;
        data=record+7;putWord(data,2);putWord(data+2,2);data[4]=(byte)codec;data[5]=3;pos=13;
        for(row=0;row<2;++row) {
            record[pos++]=codec==1 ? 5 : 0xfc;
            memcpy(record+pos,pixels+row*6,6);pos+=6;
            if(codec==2)record[pos++]=0x60;
        }
        putWord(record+5,(word)(pos-7));
        out=tmpfile();assert(out);h=begin();add(record,pos);add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(strstr(captured,"FF000000FF00\n0000FFFFFF00\n>\nEI"));fclose(out);
    }
    out=tmpfile();assert(out);h=begin();add(wide,sizeof(wide));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);fclose(out);
    out=tmpfile();assert(out);h=begin();failAllocation=allocations+3;
    add(wide,sizeof(wide));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);assert(PDFDESTROY(h)==PDF_LIMIT_ERROR);
    assert(!live);failAllocation=0;fclose(out);
}

static void indexedGStrings(void)
{
    byte simple[14]={GR_DRAW_BITMAP,0,0,0,0,7,0,1,0,1,0,0,1,0x1f};
    byte intro[35], slice[27], repeated[35], end[]={GR_END_GSTRING};
    byte *b;
    char captured[8192];
    size_t n;
    word i;
    MemHandle h;
    for(i=1;i<=2;++i) {
        simple[12]=(byte)i;out=tmpfile();assert(out);h=begin();
        add(simple,sizeof(simple));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
        rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
        assert(strstr(captured,i==1 ? "/Indexed /DeviceRGB 15 <000000010101" :
                                    "/Indexed /DeviceRGB 255 <000000010101"));fclose(out);
    }
    memset(intro,0,sizeof(intro));intro[0]=GR_DRAW_BITMAP;putWord(intro+5,28);
    b=intro+7;putWord(b,2);putWord(b+2,2);b[5]=0x4a;
    putWord(b+12,28);putWord(b+14,20);putWord(b+16,72);putWord(b+18,72);
    putWord(b+20,2);b[22]=255;b[26]=255; /* red, green */
    memset(slice,0,sizeof(slice));slice[0]=GSE_BITMAP_SLICE;putWord(slice+1,24);
    b=slice+3;putWord(b,2);putWord(b+2,2);b[5]=0x0a;putWord(b+8,2);
    putWord(b+12,20);putWord(b+16,72);putWord(b+18,72);b[21]=b[22]=1;
    out=tmpfile();assert(out);h=begin();
    add(intro,sizeof(intro));add(slice,sizeof(slice));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"/Indexed /DeviceRGB 255 <FF000000FF00000000"));
    assert(strstr(captured,"0001\n0100\n>\nEI"));fclose(out);
    memset(repeated,0,sizeof(repeated));repeated[0]=GSE_BITMAP_SLICE;putWord(repeated+1,32);
    memcpy(repeated+3,intro+7,28);putWord(repeated+11,2);memcpy(repeated+31,slice+23,4);
    for(i=0;i<2;++i) {
        if(i)repeated[25]=0; /* Changed palettes cannot share one PDF image. */
        out=tmpfile();assert(out);h=begin();
        add(intro,sizeof(intro));add(repeated,sizeof(repeated));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==(i ? GSRT_FAULT : GSRT_COMPLETE));
        if(!i)assert(PDFENDPAGE(h)==PDF_OK);
        assert(PDFDESTROY(h)==(i ? PDF_UNSUPPORTED : PDF_OK));assert(!live);fclose(out);
    }
    /* The temporary default palette must fail cleanly when memory is short. */
    out=tmpfile();assert(out);h=begin();failAllocation=allocations+2;
    add(simple,sizeof(simple));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);assert(PDFDESTROY(h)==PDF_LIMIT_ERROR);
    assert(!live);failAllocation=0;fclose(out);
}

static void lineDashes(void)
{
    byte builtin[]={GR_SET_LINE_STYLE,LS_DASHDOT,2};
    byte custom[]={GR_SET_CUSTOM_LINE_STYLE,1,0,2,0,3,1,2,4};
    byte width[]={GR_SET_LINE_WIDTH,0,128,1,0};
    byte save[]={GR_SAVE_STATE}, restore[]={GR_RESTORE_STATE}, end[]={GR_END_GSTRING};
    byte line[]={GR_DRAW_LINE,10,0,20,0,100,0,20,0};
    const char *standard="[8 8 2 8 ] 4 d";
    char captured[8192], *at;
    size_t n;
    MemHandle h;
    word i;
    out=tmpfile();assert(out);h=begin();
    add(builtin,sizeof(builtin));add(line,sizeof(line));add(save,sizeof(save));
    add(custom,sizeof(custom));add(width,sizeof(width));add(line,sizeof(line));
    add(restore,sizeof(restore));add(line,sizeof(line));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    at=strstr(captured,standard);assert(at);
    at=strstr(at+1,"[4.5 1.5 3 6 ] 1.5 d");assert(at);
    assert(strstr(at+1,standard));fclose(out);
    /* A hairline must still emit positive dash lengths. */
    memset(width+1,0,4);
    out=tmpfile();assert(out);h=begin();
    add(custom,sizeof(custom));add(width,sizeof(width));add(line,sizeof(line));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==PDF_OK);assert(PDFDESTROY(h)==PDF_OK);assert(!live);
    rewind(out);n=fread(captured,1,sizeof(captured)-1,out);captured[n]=0;
    assert(strstr(captured,"[0.1875 0.0625 0.125 0.25 ] 0.0625 d"));fclose(out);
    for(i=0;i<2;++i) {
        custom[i ? 5 : 3]=0; /* Zero factor or zero pair count. */
        out=tmpfile();assert(out);h=begin();add(custom,sizeof(custom));add(line,sizeof(line));add(end,sizeof(end));
        assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
        assert(PDFDESTROY(h)==PDF_STATE_ERROR);assert(!live);fclose(out);custom[3]=2;
    }
}

int main(int argc,char **argv)
{
    MemHandle h;
    byte save[]={GR_SAVE_STATE}, restore[]={GR_RESTORE_STATE};
    byte clip[]={GR_SET_CLIP_RECT,1,0, 20,0,20,0, 244,1,188,2};
    byte line[]={GR_DRAW_LINE,30,0,30,0, 44,1,120,0};
    byte rect[]={GR_FILL_RECT,60,0,180,0, 200,0,4,1};
    byte border[]={GR_DRAW_RECT,60,0,180,0,200,0,4,1};
    char captured[4096];
    size_t capturedSize;
    byte ellipse[]={GR_DRAW_ELLIPSE,60,0,44,1, 4,1,144,1};
    byte filled[]={GR_FILL_ELLIPSE,44,1,44,1, 144,1,194,1};
    byte txt[]={GR_DRAW_TEXT,60,0,150,0, 5,0, 'H','e','l','l','o'};
    byte ff[]={GR_NEW_PAGE,0}, end[]={GR_END_GSTRING};
    byte math[]={GR_DRAW_TEXT,60,0,165,0,3,0,'a',0xb2,'b'};
    byte areaPattern[]={GR_SET_AREA_PATTERN,PT_SOLID,255};
    byte textPattern[]={GR_SET_TEXT_PATTERN,PT_SOLID,0};
    byte pattern[4];
    /* Native wire bytes: 14-byte GDF_saved, then 26-byte TFStyleRuns.
     * Build these independently of the decoder's packed C structures.
     * Nonzero alignment bytes must never become characters. */
    byte wireField[]={
        GR_DRAW_TEXT_FIELD,6,0, 0,60,0, 0,100,0, 0,12,0, 0,0,0,
        5,0,
        0,0,0,0, SDM_100,0,0, 0,0,0,0, 0,0,0, 0,0,
        0,12,0, 0,0, 100,100,0x94,
        'H','a','l','l','o',
        1,0,
        0,0,0,0, SDM_100,0,0, TS_BOLD,0,0,0, 0,0,0, 0,0,
        0,12,0, 0,0, 100,100,0xee,
        '!'
    };
    unsigned j;
    byte imageRecord[64], monoRecord[64];
    byte rgbPixels[]={255,0,0,0,255,0,0,0,255,255,255,0};
    byte monoPixels[]={0x80,0x80,0x40,0};
    word imageSize, monoSize;
    byte field[1+sizeof(PdfTextField)+sizeof(PdfTextRun)+5];
    PdfTextField *f=(PdfTextField *)(field+1);
    PdfTextRun *r=(PdfTextRun *)(field+1+sizeof(PdfTextField));
    unsigned i;
    assert(argc==2);assert(sizeof(PdfTextField)==14);assert(sizeof(TextAttr)==23);assert(sizeof(PdfTextRun)==26);
    out=fopen(argv[1],"wb");assert(out);
    imageSize=bitmapRecord(imageRecord,GR_DRAW_BITMAP,3,2,2,1,0,2,2,rgbPixels);
    monoSize=bitmapRecord(monoRecord,GR_DRAW_BITMAP_CP,0,9,2,1,0,2,9,monoPixels);
    h=begin();add(imageRecord,imageSize);add(save,sizeof(save));add(areaPattern,sizeof(areaPattern));add(clip,sizeof(clip));add(line,sizeof(line));
    add(rect,sizeof(rect));add(ellipse,sizeof(ellipse));add(filled,sizeof(filled));
    add(txt,sizeof(txt));add(math,sizeof(math));add(restore,sizeof(restore));add(ff,sizeof(ff));
    assert(PDFGSTRING(h,1,GSC_NEW_PAGE)==GSRT_NEW_PAGE);
    assert(cursor==elementCount);assert(PDFENDPAGE(h)==0);
    assert(PDFSTARTPAGE(h)==0);
    { TransMatrix t;memset(&t,0,sizeof(t));t.TM_e11.WWF_int=t.TM_e22.WWF_int=1;
      t.TM_e31.DWF_int=10;assert(PDFSETTRANSFORM(h,&t)==0); }
    cursor=elementCount=0;memset(field,0,sizeof(field));
    field[0]=GR_DRAW_TEXT_FIELD;f->count=5;f->x.WBF_int=60;f->y.WBF_int=100;
    f->baseline.WBF_int=12;r->count=5;r->attr.styleSet=TS_BOLD;r->attr.mask=SDM_100;
    r->attr.font=FG_SANS_SERIF;r->attr.size.WBF_int=12;
    memcpy(field+sizeof(field)-5,"World",5);
    add(monoRecord,monoSize);add(textPattern,sizeof(textPattern));add(field,sizeof(field));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,GSC_NEW_PAGE)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);fclose(out);

    out=tmpfile();assert(out);h=begin();assert(sizeof(wireField)==73);
    add(wireField,sizeof(wireField));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
    rewind(out);capturedSize=fread(captured,1,sizeof(captured)-1,out);
    assert(feof(out));captured[capturedSize]=0;
    assert(strstr(captured,"(H)") && strstr(captured,"(o)") && strstr(captured,"(!)"));
    assert(!strstr(captured,"\\224") && !strstr(captured,"\\356"));fclose(out);

    /* GeoWrite emits solid pattern resets inside saved graphics states.
     * Non-solid and malformed records must fail without masking the cause
     * with the unfinished save/restore stack on the error path. */
    for (i=0;i<2;++i) {
        pattern[0]=i ? GR_SET_TEXT_PATTERN : GR_SET_AREA_PATTERN;
        pattern[2]=255;pattern[3]=0;
        for (j=1;j<=7;++j) {
            pattern[1]=j==7 ? 255 : (byte)j;
            out=tmpfile();assert(out);h=begin();
            add(save,sizeof(save));add(save,sizeof(save));
            add(pattern,3);add(end,sizeof(end));
            assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
            assert(PDFENDPAGE(h)==PDF_UNSUPPORTED);
            assert(PDFDESTROY(h)==PDF_UNSUPPORTED);assert(!live);fclose(out);
        }
        pattern[1]=PT_SOLID;
        for (j=0;j<4;++j) {
            out=tmpfile();assert(out);h=begin();
            add(save,sizeof(save));add(pattern,(word)(j==3 ? 4 : j));
            add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
            assert(PDFDESTROY(h)==PDF_STATE_ERROR);assert(!live);fclose(out);
        }
    }

    /* Invisible borders must not reject the following text. Text-field runs
     * supply their own masks, independently of inherited line/text masks. */
    for (i=0;i<2;++i) {
        out=tmpfile();assert(out);h=begin();mask=SDM_0;lineStyle=1;
        textMask=SDM_0;
        add(border,sizeof(border));
        if (i) add(field,sizeof(field));
        else {textMask=SDM_100;add(txt,sizeof(txt));}
        add(end,sizeof(end));assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
        assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
        rewind(out);capturedSize=fread(captured,1,sizeof(captured)-1,out);
        assert(feof(out));captured[capturedSize]=0;
        assert(strstr(captured,"BT /F") && strstr(captured,"%%EOF"));fclose(out);
        mask=SDM_100;lineStyle=LS_SOLID;textMask=SDM_100;
    }
    /* Empty area and text masks also succeed; malformed invisible geometry
     * still fails, and a partial visible mask remains unsupported. */
    out=tmpfile();assert(out);h=begin();areaMask=SDM_0;textMask=SDM_0;
    add(rect,sizeof(rect));add(txt,sizeof(txt));add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);assert(!live);
    rewind(out);capturedSize=fread(captured,1,sizeof(captured)-1,out);
    assert(feof(out));captured[capturedSize]=0;
    assert(!strstr(captured,"BT /F"));fclose(out);
    areaMask=SDM_100;textMask=SDM_100;
    out=tmpfile();assert(out);h=begin();mask=SDM_0;
    add(border,sizeof(border)-1);add(end,sizeof(end));
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
    assert(PDFDESTROY(h)==PDF_STATE_ERROR);assert(!live);fclose(out);mask=SDM_100;

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
    out=tmpfile();h=begin();
    { byte unionClip[11];memcpy(unionClip,clip,sizeof(clip));unionClip[1]=PCT_UNION;
      add(clip,sizeof(clip));add(unionClip,sizeof(unionClip));add(line,sizeof(line));add(end,sizeof(end));
      assert(PDFGSTRING(h,1,0)==GSRT_FAULT); }
    discard(h);fclose(out);
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
    deviceGStrings();threePointGStrings();arcPointGStrings();roundGStrings();bitmapGStrings();indexedGStrings();compressedGStrings();maskedGStrings();auditRegressions();textPrecision();textHyphens();lineDashes();
    puts("gstring: pages, fields, solid patterns, shapes, bitmap/slice dispatch, clipping and cleanup passed");
    return 0;
}
