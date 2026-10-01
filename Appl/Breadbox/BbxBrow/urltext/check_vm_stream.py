#!/usr/bin/env python3
"""Compile the actual stream/JPEG storage code against small host API stubs."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
stream = (root / 'Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc').read_text()
jpeg = (root / 'Library/Breadbox/Ijgjpeg/SUPPT/JMEMMGR.c').read_text()
block_asm = (root / 'Appl/Breadbox/BbxBrow/ASMTOOLS/asmtoolsManager.asm').read_text()

# The host stub below checks the atomic predicate/scheduling contract. It does
# not emulate GEOS interrupts or ThreadBlockOnQueue itself.
assert 'bytesAvailP:fptr, preReadOffsetP:fptr, needed:word' in block_asm
assert 'sbb\tdx, ds:[si+2]' in block_asm
assert 'cmp\tax, needed' in block_asm and 'jae\tskipBlock' in block_asm


def between(text, first, last):
    return text.split(first, 1)[1].split(last, 1)[0]


common = r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
typedef uint16_t word;
typedef uint32_t dword;
typedef int Boolean;
#define TRUE 1
#define FALSE 0
'''
stream_code = common + r'''
enum { LPSS_EMPTY, LPSS_FIRST_PACKET, LPSS_MORE_DATA };
struct Progress {
    word LPD_sem, LPD_emptyQueue, LPD_dataFile, LPD_dataStream;
    Boolean LPD_fileDone;
    dword LPD_bytesAvail, LPD_preReadOffset;
    int LPD_streamState;
};
static unsigned char data[200000], original[200000], output[200000];
static dword count;
#define HAL_COUNT(x) (x)
#define ThreadPSem(x) ((void)0)
#define ThreadVSem(x) ((void)0)
static int producerSchedule;
static word producerBytes, blockCalls;
static word maxDelete, deleteCalls;
static void produce(dword *bytesAvailP)
{
    assert(count + producerBytes <= sizeof(data));
    memcpy(data + count, original + count, producerBytes);
    count += producerBytes;
    *bytesAvailP += producerBytes;
    producerSchedule = 0;
}
static void Block(word *queueP, Boolean *flagP, dword *bytesAvailP,
                  dword *preReadOffsetP, word needed)
{
    if (producerSchedule == 1) produce(bytesAvailP);
    if (*flagP || (*bytesAvailP >= *preReadOffsetP &&
        *bytesAvailP - *preReadOffsetP >= needed)) return;
    blockCalls++;
    if (producerSchedule == 2) {
        produce(bytesAvailP);
        if (*bytesAvailP >= *preReadOffsetP &&
            *bytesAvailP - *preReadOffsetP >= needed) return;
    }
    *flagP = TRUE;
}
static word HugeArrayLock(word file, word array, dword pos, void **ptr, word *size)
{
    dword n;
    if (pos >= count) return 0;
    *ptr = data + pos; *size = 1;
    n = 8192 - pos % 8192;
    return n < count - pos ? n : count - pos;
}
static void HugeArrayUnlock(void *ptr) {}
static dword HugeArrayGetCount(word file, word array) { return count; }
static void HugeArrayDelete(word file, word array, word n, dword pos)
{
    assert(n <= 65535);
    if (n > maxDelete) maxDelete = n;
    deleteCalls++;
    assert(pos + n <= count);
    memmove(data + pos, data + pos + n, count - pos - n);
    count -= n;
}
static word read_stream(struct Progress *loadProgressDataP, void *buffer,
                        word bufSize, Boolean peek, Boolean preRead)
'''
stream_code += '{ dword streamCount; word deleteCount;\n' + between(
                            stream, '    case LPCT_READ:\n    {',
                            '        /* return bytes read */') + '\nreturn sizeRead;\n}\n'
stream_code += 'enum { LPCT_FLUSH_FIRST, LPCT_RESET_STREAM_STATE };\n' \
    'static void reset_stream(struct Progress *loadProgressDataP, ' \
    'int callbackType, word bufSize) { switch (callbackType) {\n' \
    'case LPCT_FLUSH_FIRST:' + between(stream, '    case LPCT_FLUSH_FIRST:',
                                      '    case LPCT_CLOSE:') + '} }\n'
delete_loop = between(stream, '        while (streamCount) {',
                      '            streamCount -= deleteCount;')
packet_assignment = 'streamCount = HugeArrayGetCount(loadProgressDataP->LPD_dataFile,' + between(
    stream,
    '                streamCount = HugeArrayGetCount(loadProgressDataP->LPD_dataFile,',
    '                while (streamCount) {')
stream_code += r'''
static void clear_stream(struct Progress *loadProgressDataP)
{
    dword streamCount = HugeArrayGetCount(loadProgressDataP->LPD_dataFile,
                                          loadProgressDataP->LPD_dataStream);
    word deleteCount;
''' + '        while (streamCount) {' + delete_loop + \
    '            streamCount -= deleteCount;\n        }\n}\n'
stream_code += r'''
static void clear_first_packet(struct Progress *loadProgressDataP)
{
    dword streamCount;
    word deleteCount;
''' + packet_assignment + '                while (streamCount) {' + delete_loop + \
    '            streamCount -= deleteCount;\n        }\n}\n'
stream_code += r'''
int main(void)
{
    struct Progress p;
    unsigned i;
    memset(&p, 0, sizeof(p));
    for (i = 0; i < sizeof(data); i++) original[i] = i % 251;
    memcpy(data, original, 40000);
    count = p.LPD_bytesAvail = 40000;
    p.LPD_dataStream = p.LPD_fileDone = 1;
    /* Header pre-read crosses a VM block; retry starts at the same bytes. */
    assert(read_stream(&p, output, 8209, TRUE, TRUE) == 8209);
    assert(!memcmp(output, original, 8209));
    assert(count == 40000 && p.LPD_preReadOffset == 8209);
    p.LPD_preReadOffset = 0;
    assert(read_stream(&p, output, 17, FALSE, FALSE) == 17);
    assert(!memcmp(output, original, 17));
    /* Peek after a retained first packet, then change the read size. */
    assert(read_stream(&p, output, 8199, TRUE, FALSE) == 8199);
    assert(!memcmp(output, original + 17, 8199));
    assert(read_stream(&p, output, 8200, FALSE, FALSE) == 8200);
    assert(!memcmp(output, original + 17, 8200));
    assert(p.LPD_bytesAvail == 40000 - 8217);
    assert(count == p.LPD_bytesAvail);
    /* Later peek crosses a block without repeating it; consume short EOF. */
    assert(read_stream(&p, output, 8197, TRUE, FALSE) == 8197);
    assert(!memcmp(output, original + 8217, 8197));
    i = p.LPD_bytesAvail;
    assert(read_stream(&p, output, 32768, FALSE, FALSE) == i);
    assert(!memcmp(output, original + 8217, i));
    assert(count == 0 && p.LPD_bytesAvail == 0);
    assert(read_stream(&p, output, 512, FALSE, FALSE) == 0);
    /* Simulate producer data and its wake arriving before Block begins. */
    memset(&p, 0, sizeof(p)); count = 5;
    memcpy(data, original, count);
    p.LPD_dataStream = 1; p.LPD_bytesAvail = count;
    p.LPD_preReadOffset = 2; producerBytes = 3; producerSchedule = 1;
    assert(read_stream(&p, output, 4, FALSE, FALSE) == 4);
    assert(!memcmp(output, original + 2, 4) && blockCalls == 0);
    /* Also cover a real wait followed by a producer wake. */
    memset(&p, 0, sizeof(p)); count = 0;
    p.LPD_dataStream = 1; producerBytes = 12; producerSchedule = 2;
    assert(read_stream(&p, output, 8, FALSE, FALSE) == 8);
    assert(!memcmp(output, original, 8) && blockCalls == 1);
    /* EOF with less than requested data must return the available short read. */
    memset(&p, 0, sizeof(p)); count = p.LPD_bytesAvail = 3;
    memcpy(data, original, count); p.LPD_dataStream = p.LPD_fileDone = 1;
    assert(read_stream(&p, output, 8, FALSE, FALSE) == 3);
    assert(!memcmp(output, original, 3) && blockCalls == 1);
    /* A nonzero high word must satisfy the wait without truncating availability. */
    memset(&p, 0, sizeof(p)); count = p.LPD_bytesAvail = 65541;
    memcpy(data, original, count); p.LPD_dataStream = 1;
    assert(read_stream(&p, output, 65535, FALSE, FALSE) == 65535);
    assert(!memcmp(output, original, 65535) && blockCalls == 1);
    /* Native HugeArrayDelete takes WORD counts: clear all chunks above 64K. */
    memset(&p, 0, sizeof(p)); count = p.LPD_bytesAvail = 100000;
    deleteCalls = maxDelete = 0;
    clear_stream(&p);
    assert(count == 0 && deleteCalls == 2 && maxDelete == 65535);
    count = 100000; p.LPD_dataStream = 1;
    p.LPD_bytesAvail = p.LPD_preReadOffset = 0;
    deleteCalls = maxDelete = 0;
    clear_first_packet(&p);
    assert(count == 0 && deleteCalls == 2 && maxDelete == 65535);
    /* Successful FJPEG header pre-read is removed once on the next refill. */
    memset(&p, 0, sizeof(p));
    memcpy(data, original, 40000);
    count = p.LPD_bytesAvail = 40000;
    p.LPD_dataStream = p.LPD_fileDone = 1;
    assert(read_stream(&p, output, 37, TRUE, TRUE) == 37);
    assert(read_stream(&p, output, 512, FALSE, FALSE) == 512);
    assert(!memcmp(output, original + 37, 512));
    assert(read_stream(&p, output, 8200, TRUE, FALSE) == 8200);
    assert(!memcmp(output, original + 549, 8200));
    assert(read_stream(&p, output, 8200, FALSE, FALSE) == 8200);
    assert(!memcmp(output, original + 549, 8200));
    assert(count == p.LPD_bytesAvail && p.LPD_preReadOffset == 0);
    /* A failed GIF probe retains its packet for the JPEG fallback. */
    memset(&p, 0, sizeof(p));
    memcpy(data, original, 40000);
    count = p.LPD_bytesAvail = 40000;
    p.LPD_dataStream = p.LPD_fileDone = 1;
    assert(read_stream(&p, output, 512, FALSE, FALSE) == 512);
    reset_stream(&p, LPCT_RESET_STREAM_STATE, 0);
    assert(count == p.LPD_bytesAvail && count == 40000);
    assert(read_stream(&p, output, 17, FALSE, FALSE) == 17);
    assert(!memcmp(output, original, 17));
    assert(read_stream(&p, output, 8200, FALSE, FALSE) == 8200);
    assert(!memcmp(output, original + 17, 8200));
    i = p.LPD_bytesAvail;
    assert(read_stream(&p, output, 65535, FALSE, FALSE) == i);
    assert(!memcmp(output, original + 8217, i));
    assert(count == 0 && p.LPD_bytesAvail == 0);
    /* GIF frame completion consumes, rather than replays, its first packet. */
    memset(&p, 0, sizeof(p));
    memcpy(data, original, 40000);
    count = p.LPD_bytesAvail = 40000;
    p.LPD_dataStream = p.LPD_fileDone = 1;
    assert(read_stream(&p, output, 512, FALSE, FALSE) == 512);
    reset_stream(&p, LPCT_FLUSH_FIRST, 512);
    assert(count == p.LPD_bytesAvail && count == 39488);
    assert(read_stream(&p, output, 17, FALSE, FALSE) == 17);
    assert(!memcmp(output, original + 512, 17));
    puts("VM stream boundaries, lost-wakeup schedule, WORD-sized clears and EOF passed");
    return 0;
}
'''

jpeg_code = common + r'''
typedef word MemHandle;
typedef word VMBlockHandle;
typedef word VMFileHandle;
typedef word JDIMENSION;
typedef int boolean;
typedef unsigned char JSAMPLE;
typedef JSAMPLE *JSAMPROW;
typedef JSAMPROW *JSAMPARRAY;
typedef short JBLOCK[64];
typedef JBLOCK *JBLOCKROW;
typedef JBLOCKROW *JBLOCKARRAY;
typedef struct jvirt_sarray_control *jvirt_sarray_ptr, *jmemmgr_sarray_ptr;
typedef struct jvirt_barray_control *jvirt_barray_ptr, *jmemmgr_barray_ptr;
typedef int backing_store_info;
#define FAR
#define LOCAL(t) static t
#define METHODDEF(t) static t
#define EC(x) x
#define SIZEOF(x) sizeof(x)
#define NullHandle 0
#define HF_DYNAMIC 1
#define HF_SHARABLE 2
#define HAF_ZERO_INIT 128
#define SP_PRIVATE_DATA 0
#define VMAF_FORCE_READ_WRITE 1
#define VMO_TEMP_FILE 1
#define FILE_NO_ERRORS 1
#define JPOOL_IMAGE 1
#define JERR_BAD_POOL_ID 2
#define JERR_BAD_VIRTUAL_ACCESS 3
#define JERR_TFILE_CREATE 4
static jmp_buf error;
#define ERREXIT(c,e) longjmp(error,e)
#define ERREXIT1(c,e,n) ERREXIT(c,e)
#define ERREXITS(c,e,n) ERREXIT(c,e)
static void out_of_memory(void *c, int n) { longjmp(error, 9); }
'''
jpeg_code += 'struct jvirt_sarray_control {' + between(
    jpeg, 'struct jvirt_sarray_control {', '#ifdef MEM_STATS')
jpeg_code += r'''
typedef struct {
    jmemmgr_sarray_ptr virt_sarray_list;
    jmemmgr_barray_ptr virt_barray_list;
    VMFileHandle tempVMFile;
    char tempName[40];
} my_memory_mgr, *my_mem_ptr;
struct Context { my_mem_ptr mem; };
typedef struct Context *j_common_ptr;
static struct { void *p; word size, locks; } heap[2000];
static struct { word h, size, dirty; void *disk; } vm[2000];
static word vmCount;
static int failAfter = -1, openFail, opened, deleted, depth;
static MemHandle MemAlloc(word n, word flags, word allocFlags)
{
    word h;
    assert(allocFlags == HAF_ZERO_INIT);
    if (failAfter == 0) return 0;
    if (failAfter > 0) failAfter--;
    for (h = 1; heap[h].p; h++) assert(h < 1999);
    heap[h].p = calloc(1, n); heap[h].size = n; heap[h].locks = 0;
    assert(heap[h].p); return h;
}
static void *MemLock(word h) { assert(heap[h].p); heap[h].locks++; return heap[h].p; }
static void MemUnlock(word h) { assert(heap[h].locks); heap[h].locks--; }
static void MemFree(word h) { assert(!heap[h].locks); free(heap[h].p); heap[h].p = NULL; }
static void FilePushDir(void) { depth++; }
static void FilePopDir(void) { depth--; }
static void FileSetStandardPath(int path) {}
static word VMOpen(char *name, int flags, int mode, int compress)
{
    if (openFail) return 0;
    assert(!opened); opened = 1; strcpy(name, "JPEG.TMP"); return 1;
}
static word VMAttach(word file, word block, word h)
{
    assert(file && !block); block = ++vmCount;
    assert(block < 2000);
    vm[block].h = h; vm[block].size = heap[h].size; vm[block].dirty = 1;
    return block;
}
static void *VMLock(word file, word block, word *h)
{
    if (!vm[block].h) {
        vm[block].h = MemAlloc(vm[block].size, 0, HAF_ZERO_INIT);
        assert(vm[block].h);
        memcpy(heap[vm[block].h].p, vm[block].disk, vm[block].size);
    }
    *h = vm[block].h; return MemLock(*h);
}
static void VMDirty(word h)
{
    word i;
    for (i = 1; i <= vmCount; i++) if (vm[i].h == h) { vm[i].dirty = 1; return; }
    assert(0);
}
static void VMUnlock(word h) { MemUnlock(h); }
static unsigned resident(void)
{
    word i; unsigned n = 0;
    for (i = 1; i <= vmCount; i++) if (vm[i].h) n++;
    return n;
}
static void VMEnforceHandleLimits(word file, word low, word high)
{
    word i, h;
    if (resident() <= high) return;
    for (i = 1; i <= vmCount && resident() > low; i++) {
        h = vm[i].h;
        if (!h || heap[h].locks) continue;
        if (vm[i].dirty) {
            if (!vm[i].disk) vm[i].disk = malloc(vm[i].size);
            memcpy(vm[i].disk, heap[h].p, vm[i].size); vm[i].dirty = 0;
        }
        assert(vm[i].disk); MemFree(h); vm[i].h = 0;
    }
}
static void VMClose(word file, int flags)
{
    word i;
    for (i = 1; i <= vmCount; i++) {
        if (vm[i].h) MemFree(vm[i].h);
        free(vm[i].disk); memset(&vm[i], 0, sizeof(vm[i]));
    }
    vmCount = 0; opened = 0;
}
static void FileDelete(char *name) { assert(!opened); deleted++; }
static void *small[100];
static unsigned smallCount;
static void *alloc_small(j_common_ptr c, int pool, size_t n)
{
    assert(smallCount < 100);
    small[smallCount] = calloc(1, n); return small[smallCount++];
}
'''
jpeg_code += 'METHODDEF(jvirt_sarray_ptr)\nrequest_virt_sarray' + between(
    jpeg, 'METHODDEF(jvirt_sarray_ptr)\nrequest_virt_sarray',
    '/*\n * Release all objects belonging to a specified pool.')
cleanup = between(jpeg, '  /* If freeing IMAGE pool, close any virtual arrays first */',
                  '  /* Release large objects */')
jpeg_code += '\nstatic void cleanup(j_common_ptr cinfo) {\n' \
             'my_mem_ptr mem = cinfo->mem; JDIMENSION i; int pool_id = JPOOL_IMAGE;\n' \
             + cleanup + r'''
    while (smallCount) free(small[--smallCount]);
}
static void empty(void)
{
    unsigned h;
    assert(!opened && !depth && !vmCount);
    for (h = 1; h < 2000; h++) assert(!heap[h].p);
}
int main(void)
{
    my_memory_mgr m;
    struct Context c;
    jvirt_barray_ptr b;
    jvirt_sarray_ptr s;
    JBLOCKARRAY rows;
    word i;
    memset(&m, 0, sizeof(m)); c.mem = &m;
    assert(setjmp(error) == 0);
    b = request_virt_barray(&c, JPOOL_IMAGE, TRUE, 8, 300, 2);
    s = request_virt_sarray(&c, JPOOL_IMAGE, TRUE, 100, 300, 1);
    realize_virt_arrays(&c);
    assert(opened == 1);
    for (i = 0; i < 300; i++) {
        rows = access_virt_barray(&c, b, i, 1, TRUE);
        assert(rows[0][0][0] == 0); rows[0][0][0] = i + 1;
        access_virt_sarray(&c, s, i, 1, TRUE)[0][0] = i % 251;
        assert(resident() <= 32);
    }
    for (i = 0; i < 300; i++) {
        assert(access_virt_barray(&c, b, i, 1, FALSE)[0][0][0] == i + 1);
        assert(access_virt_sarray(&c, s, i, 1, FALSE)[0][0] == i % 251);
    }
    cleanup(&c); empty(); assert(deleted == 1);
    /* Reuse a decoder, then fail partway through a two-row lock. */
    b = request_virt_barray(&c, JPOOL_IMAGE, TRUE, 8, 3, 2);
    realize_virt_arrays(&c);
    failAfter = 1;
    if (!setjmp(error)) { access_virt_barray(&c, b, 0, 2, TRUE); assert(0); }
    failAfter = -1;
    assert(b->cur_rows_in_mem == 1);
    cleanup(&c); empty();
    /* Index allocation/open failure and invalid access must unwind safely. */
    b = request_virt_barray(&c, JPOOL_IMAGE, TRUE, 8, 3, 2);
    failAfter = 0;
    if (!setjmp(error)) { realize_virt_arrays(&c); assert(0); }
    failAfter = -1; cleanup(&c); empty();
    b = request_virt_barray(&c, JPOOL_IMAGE, TRUE, 8, 3, 2);
    openFail = 1;
    if (!setjmp(error)) { realize_virt_arrays(&c); assert(0); }
    openFail = 0; cleanup(&c); empty();
    b = request_virt_barray(&c, JPOOL_IMAGE, TRUE, 8, 3, 2);
    realize_virt_arrays(&c);
    if (!setjmp(error)) { access_virt_barray(&c, b, 65535, 2, TRUE); assert(0); }
    cleanup(&c); empty();
    puts("JPEG VM eviction, zeroing, decoder reuse and failure cleanup passed");
    return 0;
}
'''

with tempfile.TemporaryDirectory() as temp:
    for name, code in [('stream', stream_code), ('jpeg', jpeg_code)]:
        source = Path(temp) / (name + '.c')
        binary = Path(temp) / name
        source.write_text(code)
        subprocess.run(['cc', '-std=c89', '-Wno-incompatible-pointer-types',
                        str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
