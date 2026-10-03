#!/usr/bin/env python3
"""Runnable check for image completion, placeholders and pending ownership."""


from pathlib import Path
import re


browser = (Path(__file__).resolve().parents[4] /
           "Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc").read_text()
MAX_IMPORTS, BATCH_SIZE, PAUSE_TICKS = (
    int(re.search(r"^#define " + name + r" (\d+)$", browser, re.M).group(1))
    for name in ("MAX_INLINE_SVG_IMPORTS", "INLINE_SVG_BATCH_SIZE",
                 "INLINE_SVG_PAUSE_TICKS")
)
assert (MAX_IMPORTS, BATCH_SIZE, PAUSE_TICKS) == (2, 8, 30)


class Campaign:
    def __init__(self, items):
        self.items = list(items)
        self.next_item = 0
        self.admitted = 0
        self.completed = 0
        self.outstanding = 0
        self.pending = 1                 # campaign hold
        self.paused = 0
        self.max_outstanding = 0
        self.temp_files = 0
        self.batches = []

    def admit(self):
        while (self.next_item < len(self.items) and self.outstanding < MAX_IMPORTS and
               self.admitted < BATCH_SIZE):
            item = self.items[self.next_item]
            self.next_item += 1
            self.admitted += 1
            if item is True or item == "failure":
                self.completed += 1
            if item is False:
                self.outstanding += 1
                self.pending += 1
                self.temp_files += 1
                self.max_outstanding = max(self.max_outstanding,
                                           self.outstanding)
        self.finish_batch_if_ready()

    def result(self):
        assert self.outstanding
        self.outstanding -= 1
        self.pending -= 1                 # individual import reference
        self.completed += 1
        self.finish_batch_if_ready()
        if not self.paused:
            self.admit()

    def finish_batch_if_ready(self):
        if self.admitted == BATCH_SIZE and self.completed == BATCH_SIZE and not self.outstanding:
            self.batches.append(BATCH_SIZE)
            if self.next_item < len(self.items):
                self.paused = PAUSE_TICKS
            else:
                self.pending -= 1         # campaign hold
        elif (self.next_item == len(self.items) and not self.outstanding and
              self.admitted < BATCH_SIZE and self.completed == self.admitted):
            self.batches.append(self.completed)
            self.pending -= 1

    def tick(self, ticks):
        assert self.paused
        self.paused -= ticks
        if not self.paused:
            self.admitted = self.completed = 0
            self.admit()

    def stop(self):
        self.paused = 0
        self.pending -= 1                 # campaign hold

    def cancel_result(self):
        assert self.outstanding
        self.outstanding -= 1
        self.pending -= 1                 # import callback owns this reference


def check_cached_placeholders():
    """Run the actual attach-time reset with host stubs for GEOS storage."""
    import subprocess
    import tempfile

    repo = Path(__file__).resolve().parents[4]
    source = (repo / "Library/Breadbox/Html4Par/htmlclas/htmlclas.goc").read_text()
    start = source.index("typedef struct {", source.index("VisTextGraphic *IFindGraphicForImage("))
    end = source.index("\n#ifdef __WATCOMC__", start)
    find_start = source.index("typedef struct {", source.index(" * Routine: IFindGraphicForImage"))
    find_end = source.index("\n/**************************************************************************", find_start)
    collapse_start = source.index("@method HTMLTextClass, MSG_HTML_TEXT_COLLAPSE_BROKEN_IMAGES")
    collapse_end = source.index("\n@method", collapse_start + 1)
    collapse = source[collapse_start:collapse_end].replace(
        "@method HTMLTextClass, MSG_HTML_TEXT_COLLAPSE_BROKEN_IMAGES",
        "static void CollapseBrokenImages(optr oself, HTMLTextInstance *pself)")
    completion = browser[browser.index("@method URLTextClass, MSG_URL_TEXT_DEC_PENDING"):
                         browser.index("void URLTextInitializeImage(")]
    assert completion.index("MSG_HTML_TEXT_COLLAPSE_BROKEN_IMAGES") < completion.index(
        "MSG_HTML_TEXT_CALCULATE_LAYOUT")
    header = (repo / "CInclude/html4par.goh").read_text()
    defines = "\n".join(line for line in header.splitlines()
                        if line.lstrip().startswith(("#define HTML_IDF_",
                            "#define HTS_LAYOUT_", "#define HTML_IMAGE_POS_")))
    harness = r'''
#include <assert.h>
#include <string.h>
#define LOCAL
#define _pascal
#define _export
#define VTGT_VARIABLE 1
#define HTML_VARGRAPH_MFGID 2
#define HTML_VARGRAPH_TYPE_IMAGE 3
#define TRUE 1
#define FALSE 0
#define NAME_POOL_NONE 0
#define TEXT_ADDRESS_PAST_END 0xffffffffUL
#define ATTR_VIS_TEXT_GRAPHIC_RUNS 0
#define OptrToHandle(o) (o)
/* GEOS word and int have equal widths, as this reverse loop requires. */
typedef unsigned int word;
typedef unsigned long dword;
typedef word optr, VMFileHandle, VMBlockHandle, MemHandle;
typedef int Boolean;
typedef struct { word XYS_width, XYS_height; } XYSize;
typedef struct {
    word flags, hspace, vspace;
    XYSize size, HID_size;
    dword pos;
    dword svgSourceLength, HID_cacheToken;
    word HID_resolvedURL, HID_vmf, HID_vmb;
} HTMLimageData;
typedef struct { word HIGV_imageIndex; } HTMLimageGraphicVariable;
typedef struct {
    XYSize VTG_size;
    struct { struct { word WAAH_high; } REH_refCount; } VTG_meta;
    word VTG_type;
    struct { struct {
        word VTGV_manufacturerID, VTGV_type;
        word VTGV_privateData[1];
    } VTGD_variable; } VTG_data;
} VisTextGraphic;
typedef struct { VMBlockHandle TLRAH_elementVMBlock; } TextLargeRunArrayHeader;
typedef struct { word LMBH_offset; } LMemBlockHeader;
typedef struct {
    VMFileHandle VTI_vmFile;
    word HTI_layoutState;
    optr HTI_imageArray;
} HTMLTextInstance;
static HTMLTextInstance text;
static HTMLimageData images[260];
static VisTextGraphic graphics[266];
static word runs = 7, arrayLocks, imageCount = 3;
static word dirtyCalls, unlockCalls, graphicVisits, vmLocks, graphicLocks;
static word graphicEnums;
static word graphicCount = 3;
static TextLargeRunArrayHeader runHeader = {8};
static LMemBlockHeader graphicHeader = {9};
static HTMLTextInstance *ObjDerefVis(optr o) { (void)o; return &text; }
static VMBlockHandle *ObjVarFindData(optr o, word v)
{ (void)o; (void)v; return runs ? &runs : (void *)0; }
static void MemLock(word h) { (void)h; arrayLocks++; }
static void MemUnlock(word h) { (void)h; arrayLocks--; }
static word ChunkArrayGetCount(optr o) { (void)o; return imageCount; }
static HTMLimageData *ChunkArrayElementToPtr(optr o, word i, void *size)
{ (void)o; (void)size; return &images[i]; }
static TextLargeRunArrayHeader *VMLock(VMFileHandle f, VMBlockHandle b, MemHandle *h)
{ (void)f; assert(b == runs); *h = 10; vmLocks++; return &runHeader; }
static void VMUnlock(MemHandle h) { assert(h == 10 && vmLocks); vmLocks--; }
static LMemBlockHeader *VMLockChainifiedLMemBlock(VMFileHandle f, VMBlockHandle b,
                                               MemHandle *h)
{ (void)f; assert(b == 8); *h = 11; graphicLocks++; return &graphicHeader; }
static Boolean ChunkArrayEnumHandles(MemHandle h, word a, void *dataP,
    Boolean (*callback)(void *, void *))
{
    word i;
    assert(h == 11 && a == 9 && graphicLocks);
    graphicEnums++;
    for(i = 0; i < graphicCount; i++) {
        graphicVisits++;
        if(callback(&graphics[i], dataP))
            return TRUE;
    }
    return FALSE;
}
static void VMDirty(MemHandle h) { assert(h == 11); dirtyCalls++; }
static void VMUnlockChainifiedLMemBlock(MemHandle h)
{ assert(h == 11 && graphicLocks); graphicLocks--; unlockCalls++; }
static void initGraphic(word i, word imageIndex)
{
    memset(&graphics[i], 0, sizeof(graphics[i]));
    graphics[i].VTG_type = VTGT_VARIABLE;
    graphics[i].VTG_data.VTGD_variable.VTGV_manufacturerID = HTML_VARGRAPH_MFGID;
    graphics[i].VTG_data.VTGD_variable.VTGV_type = HTML_VARGRAPH_TYPE_IMAGE;
    graphics[i].VTG_data.VTGD_variable.VTGV_privateData[0] = imageIndex;
}
''' + defines + "\n" + source[start:end] + "\n" + source[find_start:find_end] + "\n" + collapse + r'''
int main(void)
{
    word i;
    MemHandle graphicH;
    VisTextGraphic *graphicP;
    for (i = 0; i < 3; i++) {
        initGraphic(i, i);
        images[i].flags = HTML_IDF_RESOLVED;
        images[i].HID_cacheToken = images[i].HID_resolvedURL = 99;
        images[i].HID_vmf = images[i].HID_vmb = 99;
        images[i].HID_size.XYS_width = graphics[i].VTG_size.XYS_width = 120;
        images[i].HID_size.XYS_height = graphics[i].VTG_size.XYS_height = 80;
    }
    images[1].flags |= HTML_IDF_INLINE_SVG;
    images[1].svgSourceLength = 5000;
    images[2].flags |= HTML_IDF_INLINE_SVG | HTML_IDF_SVG_UNSUPPORTED;
    images[2].svgSourceLength = 15;
    IMarkAllImagesUnresolved(1, 1);
    assert(!arrayLocks);
    assert(images[0].HID_size.XYS_width == 120);
    assert(graphics[0].VTG_size.XYS_height == 80);
    for (i = 1; i < 3; i++) {
        assert(!images[i].HID_size.XYS_width && !images[i].HID_size.XYS_height);
        assert(!graphics[i].VTG_size.XYS_width && !graphics[i].VTG_size.XYS_height);
    }
    for (i = 0; i < 3; i++) {
        assert(!(images[i].flags & HTML_IDF_RESOLVED));
        assert(!images[i].HID_cacheToken && !images[i].HID_resolvedURL);
        assert(!images[i].HID_vmf && !images[i].HID_vmb);
    }
    assert(images[1].svgSourceLength == 5000);
    assert(!(images[1].flags & HTML_IDF_BROKEN));
    assert(images[2].flags & HTML_IDF_BROKEN);
    assert(dirtyCalls == 1 && unlockCalls == 1 && graphicVisits == 3);
    assert(graphicEnums == 1);
    assert(text.HTI_layoutState & HTS_LAYOUT_DIRTY);
    dirtyCalls = unlockCalls = graphicVisits = 0;
    IMarkAllImagesUnresolved(1, 1);
    assert(!dirtyCalls && unlockCalls == 1 && graphicVisits == 3 && !arrayLocks);

    /* More failures than the waiting list holds, with authored spacing. */
    imageCount = 260;
    graphicCount = 266;
    text.HTI_imageArray = 1;
    text.HTI_layoutState = dirtyCalls = unlockCalls = graphicVisits = 0;
    for(i = 0; i < imageCount; i++) {
        /* Graphic order need not match image order. */
        initGraphic(i, imageCount - i - 1);
        images[i].flags = HTML_IDF_BROKEN | HTML_IDF_RESOLVED;
        images[i].pos = i;
        images[i].size.XYS_width = images[i].HID_size.XYS_width = 120;
        images[i].size.XYS_height = images[i].HID_size.XYS_height = 80;
        images[i].hspace = 7;
        images[i].vspace = 9;
        graphics[i].VTG_size.XYS_width = 134;
        graphics[i].VTG_size.XYS_height = 97;
    }
    images[0].flags = HTML_IDF_RESOLVED;
    images[1].flags = HTML_IDF_RESOLVING;
    images[2].pos = HTML_IMAGE_POS_DOCUMENT_BACKGROUND;
    images[3].flags |= HTML_IDF_SUBMIT;
    images[4].pos = HTML_IMAGE_POS_TABLE_OR_CELL_BACKGROUND;
    images[5].HID_size.XYS_width = images[5].HID_size.XYS_height = 0;
    graphics[253].VTG_size.XYS_width = graphics[253].VTG_size.XYS_height = 0;
    for(i = imageCount; i < graphicCount; i++) {
        initGraphic(i, 7);
        graphics[i].VTG_size.XYS_width = 134;
    }
    graphics[260].VTG_meta.REH_refCount.WAAH_high = 255; /* free element */
    graphics[261].VTG_type = 0;
    graphics[262].VTG_data.VTGD_variable.VTGV_manufacturerID = 0;
    graphics[263].VTG_data.VTGD_variable.VTGV_type = 0;
    graphics[264].VTG_data.VTGD_variable.VTGV_privateData[0] = imageCount;
    graphics[265].VTG_data.VTGD_variable.VTGV_privateData[0] = 65535;
    CollapseBrokenImages(1, &text);
    assert(dirtyCalls == 1 && unlockCalls == 1 && graphicVisits == graphicCount);
    assert(!arrayLocks && !vmLocks && !graphicLocks);
    assert(text.HTI_layoutState == (HTS_LAYOUT_DIRTY |
        HTS_LAYOUT_NEED_TO_BLAST_HARD_MIN_WIDTHS |
        HTS_LAYOUT_NEED_COMPLETE_PROGRESSIVE_REDRAW));
    for(i = 0; i < imageCount; i++) {
        assert(images[i].size.XYS_width == 120 && images[i].size.XYS_height == 80);
        assert(images[i].hspace == 7 && images[i].vspace == 9);
        if(i < 5) {
            assert(images[i].HID_size.XYS_width == 120);
            assert(graphics[imageCount - i - 1].VTG_size.XYS_width == 134);
            assert(!(images[i].flags & HTML_IDF_SIZE_DIRTY));
        } else {
            assert(!images[i].HID_size.XYS_width && !images[i].HID_size.XYS_height);
            assert(!graphics[imageCount - i - 1].VTG_size.XYS_width &&
                !graphics[imageCount - i - 1].VTG_size.XYS_height);
            assert(images[i].flags == (HTML_IDF_BROKEN | HTML_IDF_RESOLVED |
                HTML_IDF_SIZE_DIRTY));
        }
    }
    text.HTI_layoutState = dirtyCalls = unlockCalls = graphicVisits = 0;
    CollapseBrokenImages(1, &text);
    assert(!dirtyCalls && !text.HTI_layoutState && !arrayLocks);
    assert(unlockCalls == 1 && graphicVisits == graphicCount);
    for(i = imageCount; i < graphicCount; i++)
        assert(graphics[i].VTG_size.XYS_width == 134);
    text.HTI_imageArray = 0;
    CollapseBrokenImages(1, &text);
    text.HTI_imageArray = 1;
    runs = 0;
    CollapseBrokenImages(1, &text);
    assert(!dirtyCalls && unlockCalls == 1 && !arrayLocks);
    assert(graphicVisits == graphicCount && !vmLocks && !graphicLocks);
    runs = 7;
    runHeader.TLRAH_elementVMBlock = 0;
    CollapseBrokenImages(1, &text);
    assert(unlockCalls == 1 && !vmLocks && !graphicLocks);
    runHeader.TLRAH_elementVMBlock = 8;

    /* Search is linear even in EC; successful lookup keeps its VM lock. */
    graphicVisits = graphicEnums = unlockCalls = 0;
    graphicP = IFindGraphicForImage(1, runs, 7, &graphicH);
    assert(graphicP == &graphics[252]);
    assert(graphicVisits == 253 && graphicEnums == 1 && !vmLocks);
    assert(graphicLocks == 1 && !unlockCalls);
    VMUnlockChainifiedLMemBlock(graphicH);
    /* All invalid graphic types must be skipped even with matching indices. */
    for(i = imageCount; i < graphicCount; i++)
        graphics[i].VTG_data.VTGD_variable.VTGV_privateData[0] = imageCount;
    graphicVisits = graphicEnums = unlockCalls = 0;
    graphics[264].VTG_type = 0;
    graphics[265].VTG_type = 0;
    assert(!IFindGraphicForImage(1, runs, 260, &graphicH));
    assert(graphicVisits == graphicCount && graphicEnums == 1);
    assert(unlockCalls == 1 && !vmLocks && !graphicLocks);
    graphicVisits = graphicEnums = unlockCalls = 0;
    assert(IFindGraphicForImage(1, runs, 259, &graphicH) == &graphics[0]);
    assert(graphicVisits == 1 && graphicEnums == 1 && graphicLocks == 1);
    VMUnlockChainifiedLMemBlock(graphicH);

    /* Fresh SVG placeholders still use one scan before drawing is enabled. */
    graphicCount = imageCount;
    text.HTI_layoutState = dirtyCalls = unlockCalls = graphicVisits = 0;
    for(i = 0; i < imageCount; i++) {
        initGraphic(i, imageCount - i - 1);
        images[i].flags = HTML_IDF_INLINE_SVG | HTML_IDF_RESOLVED;
        images[i].svgSourceLength = 50;
        images[i].HID_size.XYS_width = images[i].HID_size.XYS_height = 0;
    }
    IMarkAllImagesUnresolved(1, 1);
    assert(graphicVisits == graphicCount && unlockCalls == 1 && !dirtyCalls);
    assert(!text.HTI_layoutState && !arrayLocks && !vmLocks && !graphicLocks);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as directory:
        c_file = Path(directory) / "check_svg_cache.c"
        binary = Path(directory) / "check_svg_cache"
        c_file.write_text(harness)
        subprocess.run(["cc", "-std=c89", "-Wall", "-Wextra", "-Werror",
                        str(c_file), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


def main():
    check_cached_placeholders()
    empty = Campaign([])
    empty.admit()
    assert empty.pending == 0 and not empty.outstanding

    # Cache hits count toward each batch without allocating temp files.
    c = Campaign([True, False, True, False, "failure", True, False, True,
                  False, True, False, True, False, False, True, False, True])
    c.admit()
    assert c.max_outstanding == 2
    while c.outstanding:
        c.result()
    assert c.paused == 30 and c.batches == [8]
    c.tick(29)
    assert c.paused == 1 and c.batches == [8]
    c.tick(1)
    assert c.max_outstanding == 2
    while c.outstanding:
        c.result()
    assert c.paused == 30 and c.batches == [8, 8]
    c.tick(30)
    while c.outstanding:
        c.result()
    assert c.batches == [8, 8, 1]
    assert c.pending == 0 and c.temp_files == 8

    stopped = Campaign([False] * 17)
    stopped.admit()
    stopped.result()
    while stopped.outstanding:
        stopped.result()
    assert stopped.paused == 30 and stopped.pending == 1
    stopped.stop()
    assert stopped.paused == 0 and stopped.pending == 0

    active = Campaign([False] * 3)
    active.admit()
    assert active.outstanding == 2 and active.pending == 3
    active.stop()
    assert active.pending == 2
    active.cancel_result()
    active.cancel_result()
    assert active.pending == 0


if __name__ == "__main__":
    main()
