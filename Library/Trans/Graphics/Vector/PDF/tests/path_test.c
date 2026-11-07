/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     PDF Host Regression Tests
FILE:       path_test.c

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    main - Exercise native paths and clipping operations

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Validate path replay, fills, clips and transform behavior.
    Reuse the GEOS test double from gstring_test.c.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Native path/clip adapter fixtures, using the shared kernel boundary double. */
#define main gstringChecksMain
#include "gstring_test.c"
#undef main

static byte startPath[] = {GR_BEGIN_PATH, 1, 0, 1, 0};
static byte finishPath[] = {GR_END_PATH}, finishString[] = {GR_END_GSTRING};
static byte fillOdd[] = {GR_FILL_PATH, 0}, fillWinding[] = {GR_FILL_PATH, 1};
static byte strokePath[] = {GR_DRAW_PATH};
static byte moveSquare[] = {GR_MOVE_TO, 20, 0, 20, 0};
static byte edge1[] = {GR_DRAW_LINE_TO, 120, 0, 20, 0};
static byte edge2[] = {GR_DRAW_LINE_TO, 120, 0, 120, 0};
static byte edge3[] = {GR_DRAW_LINE_TO, 20, 0, 120, 0};
static byte closeSquare[] = {GR_CLOSE_SUB_PATH};
static byte hole[] = {GR_DRAW_POLYGON, 4, 0, 40, 0, 40, 0, 100, 0, 40, 0, 100, 0, 100, 0, 40, 0, 100, 0};

static void addDonut(void)
{
    add(startPath, sizeof(startPath));
    add(moveSquare, sizeof(moveSquare));
    add(edge1, sizeof(edge1));
    add(edge2, sizeof(edge2));
    add(edge3, sizeof(edge3));
    add(closeSquare, 1);
    add(hole, sizeof(hole));
    add(finishPath, 1);
    add(fillOdd, 2);
    add(strokePath, 1);
}

/* A native region fixture for (donut OR overlapping rectangle) AND a clip.
 * Its hole and solid spans cross the 2048-row conversion-strip boundary. */
static const word unionRegion[] = {
    1875, 1875, 2249, 2291, 1874, EOREGREC,
    1999, 1875, 2207, EOREGREC,
    2041, 1875, 1999, 2083, 2207, EOREGREC,
    2166, 1875, 1999, 2042, 2249, EOREGREC,
    2207, 1875, 2249, EOREGREC,
    2291, 1875, 2207, EOREGREC, EOREGREC
};

static void addUnionClip(void)
{
    static byte outer[] = {GR_DRAW_RECT, 194, 1, 194, 1, 18, 2, 38, 2};
    static byte resetTransform[] = {GR_SET_NULL_TRANSFORM};
    static byte inner[] = {GR_DRAW_RECT, 224, 1, 224, 1, 244, 1, 8, 2};
    static byte overlap[] = {GR_DRAW_RECT, 234, 1, 234, 1, 38, 2, 18, 2};
    static byte replace[] = {GR_SET_WIN_CLIP_PATH, 0, PCT_REPLACE, 0};
    static byte unite[] = {GR_SET_WIN_CLIP_PATH, 1, PCT_UNION, 0};
    static byte intersect[] = {GR_SET_WIN_CLIP_RECT, PCT_INTERSECTION, 0,
                       194, 1, 194, 1, 28, 2, 38, 2};
    static byte paint[] = {GR_FILL_RECT, 194, 1, 194, 1, 38, 2, 38, 2};
    static byte clear[] = {GR_SET_WIN_CLIP_RECT, PCT_NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    add(startPath, 5);
    add(resetTransform, 1);
    add(outer, sizeof(outer));
    add(inner, sizeof(inner));
    add(finishPath, 1);
    add(replace, sizeof(replace));
    add(startPath, 5);
    add(overlap, sizeof(overlap));
    add(finishPath, 1);
    add(unite, sizeof(unite));
    add(intersect, sizeof(intersect));
    add(paint, sizeof(paint));
    add(clear, sizeof(clear));
}

static void pathChecks(void)
{
    MemHandle h;
    PdfDocument *p;
    unsigned i;
    byte scope;
    static const unsigned failures[] = {2, 7, 8};
    byte malformed[] = {GR_DRAW_LINE, 0, 0, 0, 0, 1, 0, 1};
    /* Captured GeoWrite heading, including the native TextAttr padding byte. */
    byte heading[] = {
        0x3e, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0x0c, 0, 0xb3, 0, 0,
        0x14, 0, 0x0f, 0, 0, 0, 0x19, 0, 0, 0x10, 0xff, 8, 0, 0, 0,
        0, 4, 0x12, 0, 0x10, 0, 0, 0, 0x64, 0x64, 0xd7,
        'S', 'E', 'C', 'T', 'I', 'O', 'N', ' ', 'H', 'E', 'A', 'D', 'I',
        'N', 'G', ' ', 'H', 'E', 'R', 'E'
    };

    /* The same captured heading can now be consumed as native outlines.
     * Truncated fields and unavailable outline fonts still fail explicitly. */
    for (i = 0; i < 6; ++i) {
        heading[24] = TS_ITALIC | (i == 4 ? TS_SUPERSCRIPT :
                                 i == 5 ? TS_SUBSCRIPT : 0);
        out = tmpfile();
        assert(out);
        h = begin();
        glyphCalls = 0;
        glyphError = i == 3 ? PDF_UNSUPPORTED : 0;
        add(startPath, sizeof(startPath));
        add(heading, (word)(sizeof(heading) - (i == 2)));
        add(finishPath, 1);
        if (i == 1 || i >= 3) add(strokePath, 1);
        add(finishString, 1);
        assert(PDFGSTRING(h, 1, 0) == (i == 2 || i == 3 ? GSRT_FAULT : GSRT_COMPLETE));
        if (i != 2 && i != 3) assert(PDFENDPAGE(h) == PDF_OK);
        assert(PDFDESTROY(h) == (i == 2 ? PDF_STATE_ERROR :
                                i == 3 ? PDF_UNSUPPORTED : PDF_OK));
        if (i == 1) assert(glyphCalls == 20 && glyphFont == 0x1204 && glyphStyle == TS_ITALIC);
        if (i >= 4) {
            assert(glyphCalls == 20 && glyphStyle == TS_ITALIC);
            assert(fixed(glyphTransform.TM_e11) == 32768);
            assert(fixed(glyphTransform.TM_e22) == -32768);
            assert(glyphTransform.TM_e32.DWF_int == (i == 4 ? 8 : 13));
        }
        assert(!glyphLive);
        glyphError = 0;
        assert(!live && !pathStateLive && !mainStateLive);
        fclose(out);
    }
    out = tmpfile();
    assert(out);
    h = begin();
    addUnionClip();
    add(finishString, 1);
    regionEmpty = 1;
    assert(PDFGSTRING(h, 1, 0) == GSRT_COMPLETE);
    regionEmpty = 0;
    assert(PDFENDPAGE(h) == PDF_OK && PDFDESTROY(h) == PDF_OK);
    assert(!live && !pathStateLive && !mainStateLive);
    fclose(out);
    out = tmpfile();
    assert(out);
    h = begin();
    {
        static byte unitePath[] = {GR_BEGIN_PATH, PCT_UNION, 0, 0, 0};
        add(startPath, 5);
        add(moveSquare, sizeof(moveSquare));
        add(edge1, sizeof(edge1));
        add(edge2, sizeof(edge2));
        add(finishPath, 1);
        add(unitePath, 5);
        add(hole, sizeof(hole));
        add(finishPath, 1);
        add(fillWinding, 2);
    }
    add(finishString, 1);
    assert(PDFGSTRING(h, 1, 0) == GSRT_COMPLETE);
    assert(regionCalls == 2 && regionSections == 4);
    assert(regionRules[0] == 1 && regionRules[1] == 1);
    assert(PDFENDPAGE(h) == PDF_OK && PDFDESTROY(h) == PDF_OK);
    assert(!live && !pathStateLive && !mainStateLive);
    fclose(out);
    /* A snapshot must not restore the reader's section frame, or leave a
     * recorded save open when the section ends. */
    for (i = 0; i < 2; ++i) {
        out = tmpfile();
        assert(out);
        h = begin();
        assert(GrCreateState(0) == 100);
        p = MemLock(h);
        prefix(paths + GPT_WIN_CLIP, PCT_REPLACE);
        scope = i ? GR_SAVE_STATE : GR_RESTORE_STATE;
        append(paths + GPT_WIN_CLIP, &scope, 1);
        append(paths + GPT_WIN_CLIP, finishPath, 1);
        append(paths + GPT_WIN_CLIP, finishString, 1);
        nativePath(p, 100, GPT_WIN_CLIP, 2);
        assert(p->error == PDF_STATE_ERROR);
        MemUnlock(h);
        GrDestroyState(100);
        assert(PDFDESTROY(h) == PDF_STATE_ERROR);
        assert(!live && !pathStateLive && !mainStateLive);
        fclose(out);
    }
    out = tmpfile();
    assert(out);
    allocations = 0;
    h = begin();
    addDonut();
    add(finishString, 1);
    assert(PDFGSTRING(h, 1, 0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);
    assert(PDFDESTROY(h)==0);
    fclose(out);
    /* Representative failures at capture, snapshot and snapshot-element allocation. */
    for (i = 0;i<sizeof(failures)/sizeof(failures[0]);++i) {
        out = tmpfile();
        assert(out);
        allocations = 0;
        failAllocation = failures[i];
        h = begin();
        addDonut();
        add(finishString, 1);
        assert(PDFGSTRING(h, 1, 0)==GSRT_FAULT);
        assert(PDFDESTROY(h)!=0);
        assert(!live && !pathStateLive && !mainStateLive);
        failAllocation = 0;
        fclose(out);
    }
    out = tmpfile();
    assert(out);
    h = begin();
    add(startPath, 5);
    add(malformed, sizeof(malformed));
    add(finishPath, 1);
    add(finishString, 1);
    assert(PDFGSTRING(h, 1, 0)==GSRT_FAULT);
    assert(PDFDESTROY(h)==PDF_STATE_ERROR);
    fclose(out);
    out = tmpfile();
    assert(out);
    h = begin();
    for (i = 0;i<4;++i)addDonut();
    add(finishString, 1);
    failStream = streamCalls+1;
    assert(PDFGSTRING(h, 1, 0)==GSRT_FAULT);
    assert(PDFDESTROY(h)==PDF_IO_ERROR);
    assert(!live);
    failStream = 0;
    fclose(out);
}

int main(int argc, char **argv)
{
    MemHandle h;
    TransMatrix identityMatrix;
    byte save[] = {GR_SAVE_STATE}, restoreState[] = {GR_RESTORE_STATE};
    byte parent[] = {GR_SET_CLIP_RECT, 1, 0, 160, 0, 20, 0, 200, 0, 60, 0};
    byte child[] = {GR_SET_CLIP_RECT, 1, 0, 220, 0, 20, 0, 4, 1, 60, 0};
    byte bar[] = {GR_FILL_RECT, 160, 0, 20, 0, 4, 1, 60, 0};
    byte nullApp[] = {GR_SET_CLIP_RECT, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    byte nullWin[] = {GR_SET_WIN_CLIP_RECT, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    byte win[] = {GR_SET_WIN_CLIP_RECT, 1, 0, 24, 1, 20, 0, 84, 1, 100, 0};
    byte circle[] = {GR_DRAW_ELLIPSE, 24, 1, 20, 0, 124, 1, 120, 0};
    byte clipPath[] = {GR_SET_CLIP_PATH, 0, 1, 0};
    byte circlePaint[] = {GR_FILL_RECT, 24, 1, 20, 0, 124, 1, 120, 0};
    byte transformedSquare[] = {GR_DRAW_RECT, 10, 0, 140, 0, 30, 0, 160, 0};
    byte restoredSquare[] = {GR_DRAW_RECT, 120, 0, 140, 0, 140, 0, 160, 0};
    byte savedWidth[] = {GR_SET_LINE_WIDTH, 0, 0, 4, 0};
    byte clipText[43], textClip[] = {GR_SET_WIN_CLIP_PATH, 0, 1, 0};
    byte textPaint[] = {GR_FILL_RECT, 144, 1, 190, 0, 174, 1, 220, 0};
    byte transformRecord[29], identityRecord[29];
    byte firstClip[] = {GR_SET_CLIP_RECT, 1, 0, 10, 0, 20, 0, 60, 0, 80, 0};
    byte nextClip[] = {GR_SET_CLIP_RECT, 3, 0, 50, 0, 20, 0, 100, 0, 80, 0};
    byte paint[] = {GR_FILL_RECT, 0, 0, 0, 0, 120, 0, 120, 0};
    assert(argc==2);
    pathChecks();
    out=fopen(argv[1],"wb");
    assert(out);
    h = begin();
    addDonut();
    add(parent, sizeof(parent));
    add(save, 1);
    add(child, sizeof(child));
    add(bar, sizeof(bar));
    add(restoreState, 1);
    add(bar, sizeof(bar));
    add(nullApp, sizeof(nullApp));
    add(win, sizeof(win));
    add(startPath, 5);
    add(circle, sizeof(circle));
    add(finishPath, 1);
    add(clipPath, sizeof(clipPath));
    add(circlePaint, sizeof(circlePaint));
    add(nullApp, sizeof(nullApp));
    add(nullWin, sizeof(nullWin));
    identity(&identityMatrix);
    identityRecord[0] = GR_SET_TRANSFORM;
    memcpy(identityRecord+1, &identityMatrix, sizeof(identityMatrix));
    identityMatrix.TM_e11.WWF_int = 2;
    identityMatrix.TM_e31.DWF_int = 20;
    transformRecord[0] = GR_SET_TRANSFORM;
    memcpy(transformRecord+1, &identityMatrix, sizeof(identityMatrix));
    add(startPath, 5);
    add(save, 1);
    add(transformRecord, 29);
    add(save, 1);
    add(savedWidth, sizeof(savedWidth));
    add(transformedSquare, sizeof(transformedSquare));
    add(restoreState, 1);
    add(restoreState, 1);
    add(restoredSquare, sizeof(restoredSquare));
    add(finishPath, 1);
    add(fillWinding, 2);
    memset(clipText, 0, sizeof(clipText));
    clipText[0] = GR_DRAW_TEXT_FIELD;
    storeWord(clipText+1, 2);
    clipText[3] = 64; /* Fractional native text origin: 400.25, 200.5. */
    storeWord(clipText+4, 400);
    clipText[6] = 128;
    storeWord(clipText+7, 200);
    storeWord(clipText+10, 12);
    storeWord(clipText+12, 0xffff);
    storeWord(clipText+15, 2);
    clipText[21] = SDM_100;
    clipText[24] = TS_ITALIC;
    clipText[25] = 0xff;
    clipText[26] = TM_DRAW_BASE;
    clipText[27] = 0xff;
    storeWord(clipText+31, 0x1204);
    storeWord(clipText+34, 16);
    clipText[38] = clipText[39] = 100;
    clipText[41] = clipText[42] = 'O';
    add(startPath, 5);
    add(clipText, sizeof(clipText));
    add(finishPath, 1);
    add(textClip, sizeof(textClip));
    add(textPaint, sizeof(textPaint));
    add(nullWin, sizeof(nullWin));
    addUnionClip();
    add(finishString, 1);
    regionFixture = unionRegion;
    regionFixtureWords = sizeof(unionRegion)/2;
    assert(PDFGSTRING(h, 1, 0)==GSRT_COMPLETE);
    assert(regionCalls == 2 && regionSections == 6);
    assert(regionCombines[0] == PCT_REPLACE && regionCombines[1] == PCT_UNION &&
           regionCombines[2] == PCT_INTERSECTION);
    assert(regionRules[0] == 0 && regionRules[1] == 1 && regionRules[2] == 0);
    regionFixture = 0;
    assert(PDFENDPAGE(h)==0);
    assert(PDFSTARTPAGE(h)==0);
    identity(&identityMatrix);
    identityMatrix.TM_e11.WWF_int = identityMatrix.TM_e22.WWF_int = 0;
    identityMatrix.TM_e12.WWF_int = 2;
    identityMatrix.TM_e21.WWF_int = -1;
    identityMatrix.TM_e31.DWF_int = 200;
    assert(PDFSETTRANSFORM(h, &identityMatrix)==0);
    identity(&identityMatrix);
    cursor = elementCount = 0;
    identityMatrix.TM_e31.DWF_int = 20;
    memcpy(transformRecord+1, &identityMatrix, sizeof(identityMatrix));
    add(transformRecord, 29);
    add(firstClip, sizeof(firstClip));
    add(identityRecord, 29);
    add(nextClip, sizeof(nextClip));
    add(paint, sizeof(paint));
    add(finishString, 1);
    assert(PDFGSTRING(h, 1, 0)==GSRT_COMPLETE);
    assert(PDFENDPAGE(h)==0);
    assert(PDFDESTROY(h)==0);
    assert(!live);
    fclose(out);
    puts("path: retained fill/stroke, holes, scope replacement, native clip intersection, transforms and failures passed");
    return 0;
}
