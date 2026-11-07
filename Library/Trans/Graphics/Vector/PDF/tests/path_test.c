/* Native path/clip adapter fixtures, using the shared kernel boundary double. */
#define main gstringChecksMain
#include "gstring_test.c"
#undef main

static byte startPath[]={GR_BEGIN_PATH,1,0,1,0};
static byte finishPath[]={GR_END_PATH}, finishString[]={GR_END_GSTRING};
static byte fillOdd[]={GR_FILL_PATH,0}, fillWinding[]={GR_FILL_PATH,1};
static byte strokePath[]={GR_DRAW_PATH};
static byte moveSquare[]={GR_MOVE_TO,20,0,20,0};
static byte edge1[]={GR_DRAW_LINE_TO,120,0,20,0};
static byte edge2[]={GR_DRAW_LINE_TO,120,0,120,0};
static byte edge3[]={GR_DRAW_LINE_TO,20,0,120,0};
static byte closeSquare[]={GR_CLOSE_SUB_PATH};
static byte hole[]={GR_DRAW_POLYGON,4,0,40,0,40,0,100,0,40,0,100,0,100,0,40,0,100,0};

static void addDonut(void)
{
    add(startPath,sizeof(startPath));add(moveSquare,sizeof(moveSquare));
    add(edge1,sizeof(edge1));add(edge2,sizeof(edge2));add(edge3,sizeof(edge3));add(closeSquare,1);
    add(hole,sizeof(hole));add(finishPath,1);add(fillOdd,2);add(strokePath,1);
}
static void pathChecks(void)
{
    MemHandle h;
    unsigned i;
    static const unsigned failures[]={2,7,8};
    byte malformed[]={GR_DRAW_LINE,0,0,0,0,1,0,1};
    out=tmpfile();assert(out);allocations=0;h=begin();
    addDonut();add(finishString,1);assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);assert(PDFDESTROY(h)==0);fclose(out);
    /* Representative failures at capture, snapshot and snapshot-element allocation. */
    for(i=0;i<sizeof(failures)/sizeof(failures[0]);++i) {
        out=tmpfile();assert(out);allocations=0;failAllocation=failures[i];h=begin();
        addDonut();add(finishString,1);assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
        assert(PDFDESTROY(h)!=0);assert(!live && !pathStateLive && !mainStateLive);
        failAllocation=0;fclose(out);
    }
    out=tmpfile();assert(out);h=begin();
    add(startPath,5);add(malformed,sizeof(malformed));add(finishPath,1);add(finishString,1);
    assert(PDFGSTRING(h,1,0)==GSRT_FAULT);assert(PDFDESTROY(h)==PDF_STATE_ERROR);fclose(out);
    out=tmpfile();assert(out);h=begin();
    for(i=0;i<4;++i)addDonut();
    add(finishString,1);
    failStream=streamCalls+1;assert(PDFGSTRING(h,1,0)==GSRT_FAULT);
    assert(PDFDESTROY(h)==PDF_IO_ERROR);assert(!live);failStream=0;fclose(out);
}
int main(int argc,char **argv)
{
    MemHandle h;
    TransMatrix identityMatrix;
    byte save[]={GR_SAVE_STATE},restoreState[]={GR_RESTORE_STATE};
    byte parent[]={GR_SET_CLIP_RECT,1,0,160,0,20,0,200,0,60,0};
    byte child[]={GR_SET_CLIP_RECT,1,0,220,0,20,0,4,1,60,0};
    byte bar[]={GR_FILL_RECT,160,0,20,0,4,1,60,0};
    byte nullApp[]={GR_SET_CLIP_RECT,0,0,0,0,0,0,0,0,0,0};
    byte nullWin[]={GR_SET_WIN_CLIP_RECT,0,0,0,0,0,0,0,0,0,0};
    byte win[]={GR_SET_WIN_CLIP_RECT,1,0,24,1,20,0,84,1,100,0};
    byte circle[]={GR_DRAW_ELLIPSE,24,1,20,0,124,1,120,0};
    byte clipPath[]={GR_SET_CLIP_PATH,0,1,0};
    byte circlePaint[]={GR_FILL_RECT,24,1,20,0,124,1,120,0};
    byte transformedSquare[]={GR_DRAW_RECT,10,0,140,0,30,0,160,0};
    byte transformRecord[29],identityRecord[29];
    byte firstClip[]={GR_SET_CLIP_RECT,1,0,10,0,20,0,60,0,80,0};
    byte nextClip[]={GR_SET_CLIP_RECT,3,0,50,0,20,0,100,0,80,0};
    byte paint[]={GR_FILL_RECT,0,0,0,0,120,0,120,0};
    assert(argc==2);pathChecks();out=fopen(argv[1],"wb");assert(out);h=begin();
    addDonut();
    add(parent,sizeof(parent));add(save,1);add(child,sizeof(child));add(bar,sizeof(bar));
    add(restoreState,1);add(bar,sizeof(bar));add(nullApp,sizeof(nullApp));
    add(win,sizeof(win));add(startPath,5);add(circle,sizeof(circle));add(finishPath,1);
    add(clipPath,sizeof(clipPath));add(circlePaint,sizeof(circlePaint));
    add(nullApp,sizeof(nullApp));add(nullWin,sizeof(nullWin));
    identity(&identityMatrix);identityRecord[0]=GR_SET_TRANSFORM;
    memcpy(identityRecord+1,&identityMatrix,sizeof(identityMatrix));
    identityMatrix.TM_e11.WWF_int=2;identityMatrix.TM_e31.DWF_int=20;
    transformRecord[0]=GR_SET_TRANSFORM;memcpy(transformRecord+1,&identityMatrix,sizeof(identityMatrix));
    add(transformRecord,29);add(startPath,5);add(transformedSquare,sizeof(transformedSquare));
    add(finishPath,1);add(fillWinding,2);add(finishString,1);
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);
    assert(PDFSTARTPAGE(h)==0);identity(&identityMatrix);assert(PDFSETTRANSFORM(h,&identityMatrix)==0);
    cursor=elementCount=0;
    identityMatrix.TM_e31.DWF_int=20;memcpy(transformRecord+1,&identityMatrix,sizeof(identityMatrix));
    add(transformRecord,29);add(firstClip,sizeof(firstClip));add(identityRecord,29);
    add(nextClip,sizeof(nextClip));add(paint,sizeof(paint));add(finishString,1);
    assert(PDFGSTRING(h,1,0)==GSRT_COMPLETE);assert(PDFENDPAGE(h)==0);
    assert(PDFDESTROY(h)==0);assert(!live);fclose(out);
    puts("path: retained fill/stroke, holes, scope replacement, native clip intersection, transforms and failures passed");
    return 0;
}
