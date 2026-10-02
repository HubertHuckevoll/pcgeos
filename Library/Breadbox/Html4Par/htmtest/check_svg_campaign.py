#!/usr/bin/env python3
"""Runnable check for inline SVG batch admission and pending ownership."""


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
    start = source.index("void LOCAL IMarkAllImagesUnresolved(")
    end = source.index("\n#ifdef __WATCOMC__", start)
    header = (repo / "CInclude/html4par.goh").read_text()
    defines = "\n".join(line for line in header.splitlines()
                        if line.lstrip().startswith("#define HTML_IDF_") or
                        line.lstrip().startswith("#define HTS_LAYOUT_"))
    harness = r'''
#include <assert.h>
#include <string.h>
#define LOCAL
#define TRUE 1
#define FALSE 0
#define NAME_POOL_NONE 0
#define ATTR_VIS_TEXT_GRAPHIC_RUNS 0
#define OptrToHandle(o) (o)
/* GEOS word and int have equal widths, as this reverse loop requires. */
typedef unsigned int word;
typedef unsigned long dword;
typedef word optr, VMFileHandle, VMBlockHandle, MemHandle;
typedef int Boolean;
typedef struct { word XYS_width, XYS_height; } XYSize;
typedef struct {
    word flags;
    XYSize HID_size;
    dword svgSourceLength, HID_cacheToken;
    word HID_resolvedURL, HID_vmf, HID_vmb;
} HTMLimageData;
typedef struct { XYSize VTG_size; } VisTextGraphic;
typedef struct { VMFileHandle VTI_vmFile; word HTI_layoutState; } HTMLTextInstance;
static HTMLTextInstance text;
static HTMLimageData images[3];
static VisTextGraphic graphics[3];
static word runs = 7, dirty, unlocked, arrayLocks;
static HTMLTextInstance *ObjDerefVis(optr o) { (void)o; return &text; }
static VMBlockHandle *ObjVarFindData(optr o, word v)
{ (void)o; (void)v; return &runs; }
static void MemLock(word h) { (void)h; arrayLocks++; }
static void MemUnlock(word h) { (void)h; arrayLocks--; }
static word ChunkArrayGetCount(optr o) { (void)o; return 3; }
static HTMLimageData *ChunkArrayElementToPtr(optr o, word i, void *size)
{ (void)o; (void)size; return &images[i]; }
static VisTextGraphic *IFindGraphicForImage(VMFileHandle f, VMBlockHandle r,
                                           word i, MemHandle *h)
{ (void)f; (void)r; *h = i + 1; return &graphics[i]; }
static void VMDirty(MemHandle h) { dirty |= 1 << h; }
static void VMUnlockChainifiedLMemBlock(MemHandle h) { unlocked |= 1 << h; }
''' + defines + "\n" + source[start:end] + r'''
int main(void)
{
    word i;
    for (i = 0; i < 3; i++) {
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
    assert(dirty == ((1 << 2) | (1 << 3)) && unlocked == dirty);
    assert(text.HTI_layoutState & HTS_LAYOUT_DIRTY);
    dirty = unlocked = 0;
    IMarkAllImagesUnresolved(1, 1);
    assert(!dirty && unlocked == ((1 << 2) | (1 << 3)) && !arrayLocks);
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
