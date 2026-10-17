#!/usr/bin/env perl
# Run actual publication, cleanup, dispatch and browser callback code with host
# resource shims. This does not run GEOS, scheduling or full raster decoding.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

my $root = "$FindBin::Bin/../../../..";
sub read_source {
    open my $in, '<:raw', $_[0] or die "$!: $_[0]";
    local $/;
    my $s = <$in>;
    $s =~ s/\r\n/\n/g;
    return $s;
}
sub part {
    my ($s, $first, $last) = @_;
    my $a = index($s, $first);
    my $b = index($s, $last, $a + length($first));
    die "Missing source section: $first\n" if $a < 0 || $b < 0;
    return substr($s, $a, $b-$a);
}
sub function {
    my ($s, $signature) = @_;
    return part($s, $signature, "\n}") . "\n}\n";
}
my $browser = read_source("$FindBin::Bin/../mime/GraphicImport.goc");
my $progress = read_source("$FindBin::Bin/../urltext/URLTextImageProgress.goc");
my $public = read_source("$root/CInclude/htmldrv.h");
my $private = read_source("$root/Library/Breadbox/ImpGraph/IMPBMP/ibcommon.h");
my $engine = read_source("$root/Library/Breadbox/ImpGraph/MAIN/impgraph.goc");
my $jpeg = read_source("$root/Library/Breadbox/ImpGraph/IMPBMP/impjpeg.goc");
my $fjpeg = read_source("$root/Library/Breadbox/ImpGraph/IMPBMP/impfjpeg.goc");
my $gif = read_source("$root/Library/Breadbox/ImpGraph/IMPBMP/impgifc.goc");
my $input = read_source("$root/CInclude/impinput.h");
$input =~ s/^#include <geos.h>\n//m;
my $api = part($public, 'typedef enum { IIS_FILE', '#define MIME_LIMIT_NONE');
my $state = part($private, '#define IMPORT_PUBLICATIONS_PER_BLOCK', "typedef enum\n{");
my $params = part($private, "typedef struct\n{\n  FileHandle", "typedef struct\n{\n  byte");
my $request = part($browser, "typedef struct {\n    optr textObj", '} T_importGraphicRequest;') . '} T_importGraphicRequest;';
my $notification = read_source("$FindBin::Bin/../importg.goh");
$notification = part($notification, "typedef struct {\n    optr textObj", '} ImportGraphicProgress;') . '} ImportGraphicProgress;';
my $callback = function($browser, 'void _pascal _export ImportGraphicProgressCallback(');
$callback =~ s/\@send, forceQueue requestP->textObj::\s*MSG_URL_TEXT_IMPORT_GRAPHIC_PROGRESS\(importProgressData\)/QueueProgress(requestP->textObj, importProgressData)/s
    or die "Missing queued notification\n";
my $receiver = function($progress, '@extern method URLTextClass, MSG_URL_TEXT_IMPORT_GRAPHIC_PROGRESS');
$receiver =~ s/^\@extern method[^\n]+/static void Receive(MemHandle importProgressData)/;
$receiver =~ s/\@call self::MSG_URL_TEXT_INTERNAL_REPLACE_LIKE_GRAPHICS/ReplaceGraphic/;
my $adapter = function($progress, 'word _pascal _export ImportGraphicInputCallback(');
my $helpers = part($engine, 'static Boolean _pascal ImportWasPublished', '/*' . "\n *  Import file whose name");
$helpers =~ s/ProcCallFixedOrMovable_pascal/CallProgress/g;
my $retention = part($browser, '#define IMPORT_TOKENS_PER_BLOCK', '/*' . "\n * import progress callback");
my $error = part($jpeg, '      /* Free the existing data if we have any */', '      /* More clean up */');
my $flag_error = part($jpeg, '  if(flag == FALSE)', '  /* We know that the temporarily');
my $abort = part($jpeg, '    /* Stop here if we are aborting', "\n    }\n") . "\n    }\n";
$abort =~ s/\s*break\s*;//g;
my $tmp = tempdir(CLEANUP => 1);
open my $out, '>', "$tmp/check.c" or die $!;
print {$out} <<'C';
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define _pascal
#define _export
#define LOCAL
#define TRUE 1
#define FALSE 0
#define NullHandle 0
#define OCT_NULL 0
#define OCT_GSTRING 1
#define HF_DYNAMIC 1
#define HAF_ZERO_INIT 2
#define HAF_NO_ERR 4
#define FILE_ACCESS_R 0
#define FILE_DENY_W 0
#define FILE_DENY_NONE 0
#define SLICE_HEIGHT 10
#define MIME_MAXBUF 32
#define MIME_STATUS_ABORT 0x8000
#define IMPORT_PROGRESS_DATA_QUEUE_SIZE 20
#define VMCHAIN_GET_VM_BLOCK(c) (c)
#define VMCHAIN_MAKE_FROM_VM_BLOCK(b) (b)
#define MIME_GREX_NO_ANIMATIONS 1
#define MIME_GREX_NO_SCANLINE_COMPRESS 2
#define MIME_RES_DISPLAY_DEFAULT 0
#define IAD_TYPE_BITMAP 2
#define IAD_TYPE_ANIMATION 1
#define _TEXT(s) (s)
typedef unsigned short word, NameToken, VMFileHandle, VMBlockHandle, MemHandle;
typedef unsigned long dword, VMChain;
typedef int Boolean, optr, ObjCacheToken;
typedef char TCHAR, PathName[128], MimeRes;
typedef word FileHandle, BMType, AllocWatcherHandle;
typedef struct { word XYS_width, XYS_height; } XYSize;
typedef struct { int P_x, P_y; } Point;
typedef struct { word IAD_type; XYSize IAD_size; Point IAD_origin;
    Boolean IAD_completeGraphic; } ImageAdditionalData;
typedef struct { word MS_mimeFlags; } MimeStatus;
typedef struct { word child; } LoadProgressData;
C
print {$out} "$input\n$api\n$state\n$params\n$request\n$notification\n";
print {$out} <<'C';
typedef enum { LPCT_READ, LPCT_PEEK, LPCT_PRE_READ, LPCT_FLUSH_FIRST,
    LPCT_RESET_STREAM_STATE } LoadProgressCallbackType;
#define LIMIT 512
static int mapped, failAlloc, failLock, queueCount, fileOpens, fileReads;
static int semDepth, nameRefs, delivered;
static MemHandle G_importProgressDataQueue[20], queued[LIMIT];
static word G_importProgressDataQueueSem = 1;
static struct { int live, locked; unsigned char data[1024]; } blocks[LIMIT];
typedef struct { int refs; word bitmap, file, lockCount, OCD_flags;
    union { ImageAdditionalData graph; } auxdata; } objCacheData;
static objCacheData cache[LIMIT];
static int imageLive[LIMIT][4], imageFrees[LIMIT][4];
static struct { int HTI_imageArray; } text = {1}, *pself = &text;
static void ThreadPSem(word sem) { assert(sem == 1 && !semDepth); semDepth++; }
static void ThreadVSem(word sem) { assert(sem == 1 && semDepth == 1); semDepth--; }
static MemHandle MemAlloc(word size, word flags, word allocFlags)
{
    word h;
    assert(size <= 1024 && flags == HF_DYNAMIC);
    assert(allocFlags & HAF_ZERO_INIT);
    if (failAlloc && !(allocFlags & HAF_NO_ERR)) return 0;
    for (h = 1; h < LIMIT && blocks[h].live; h++);
    assert(h < LIMIT); blocks[h].live = 1;
    memset(blocks[h].data, 0, sizeof(blocks[h].data)); return h;
}
static void *MemLock(MemHandle h)
{
    assert(h && blocks[h].live && !blocks[h].locked);
    if (failLock) { failLock = 0; return (void*)0; }
    blocks[h].locked = 1; return blocks[h].data;
}
static void MemUnlock(MemHandle h) { assert(blocks[h].locked); blocks[h].locked = 0; }
static void MemFree(MemHandle h)
{ assert(blocks[h].live && !blocks[h].locked); blocks[h].live = 0; }
static void NewImage(word f, word b)
{ assert(f && f < 4 && b && b < LIMIT && !imageLive[b][f]); imageLive[b][f] = 1; }
static void VMFreeVMChain(word f, word b)
{
    assert(f && f < 4 && b && b < LIMIT && imageLive[b][f]);
    imageLive[b][f] = 0; imageFrees[b][f]++;
}
static void ObjCacheLockItem(ObjCacheToken t, VMFileHandle *f, VMChain *b, void *a, word n)
{
    (void)a; (void)n; assert(t && cache[t].refs); cache[t].refs++;
    if (f) *f = cache[t].file;
    if (b) *b = cache[t].bitmap;
}
static void ObjCacheUnlockItem(ObjCacheToken t)
{
    assert(t && cache[t].refs);
    if (!--cache[t].refs) VMFreeVMChain(cache[t].file, cache[t].bitmap);
}
static ObjCacheToken ObjCacheAddURL(VMFileHandle f, VMChain b, int type,
    ImageAdditionalData *iad, word size, NameToken name, Boolean lock, Boolean temporary)
{
    int t;
    (void)iad; assert(type == OCT_GSTRING && size == sizeof(*iad) && name == 7);
    assert(lock && temporary && imageLive[b][f]);
    for (t = 1; t < LIMIT && cache[t].refs; t++);
    assert(t < LIMIT); cache[t].refs = 1; cache[t].bitmap = (word)b; cache[t].file = f; cache[t].auxdata.graph = *iad;
    return t;
}
static void QueueProgress(optr obj, MemHandle h)
{ assert(obj == 5 && queueCount < LIMIT); queued[queueCount++] = h; }
static void NamePoolUseToken(optr pool, NameToken name)
{ assert(pool == 1 && name == 7); nameRefs++; }
static optr namePool = 1;
static void ReplaceGraphic(ObjCacheToken t, NameToken n, word first, word last)
{
    assert(n == 7 && first <= last && last < 30 && nameRefs);
    assert(imageLive[cache[t].bitmap][cache[t].file]); nameRefs--; delivered++;
    ObjCacheUnlockItem(t);
}
static word LoadGraphicProgressCallback(void *contextP, LoadProgressCallbackType op,
    void *bufferP, word size)
{ assert(contextP == &text && bufferP == &text && size == 9); mapped = op; return 9; }
static void CallProgress(void *clientDataP, const ImageImportUpdate *updateP, void *pf)
{ ((proc_ImageImportUpdate *)pf)(clientDataP, updateP); }
C
print {$out} "$helpers\n$retention\n$callback\n";
print {$out} function($browser, 'void ImportRemoveProgressDataFromQueue(');
print {$out} "$receiver\n$adapter\n";
print {$out} <<'C';
static word CallInput(void *dataP, ImageInputOperation op, void *bufferP, word size, void *pf)
{ return ((proc_ImageInputCallback *)pf)(dataP, op, bufferP, size); }
static word FileOpen(const char *file, int flags)
{ (void)flags; assert(!strcmp(file, "image")); fileOpens++; return 1; }
static void FileClose(word file, int errors) { (void)errors; assert(file == 1); }
static word FileRead(word file, void *bufferP, word size, int errors)
{ (void)bufferP; (void)errors; assert(file == 1); fileReads++; return size; }
static int isJpeg(word file) { assert(file == 1); return TRUE; }
typedef struct { word soi; unsigned char marker; } T_jpegHeader;
typedef struct { word pos; int operations[5]; } Source;
static word Input(void *dataP, ImageInputOperation op, void *bufferP, word size)
{
    static const unsigned char bytes[] = {0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4};
    Source *sourceP = dataP;
    word count;
    sourceP->operations[op]++;
    if (op == IIO_RESET) { sourceP->pos = 0; return 0; }
    if (op == IIO_FLUSH_FIRST) return 0;
    count = (word)(sizeof(bytes)-sourceP->pos);
    if (size < count) count = size;
    memcpy(bufferP, bytes+sourceP->pos, count);
    if (op == IIO_READ || op == IIO_PRE_READ) sourceP->pos += count;
    return count;
}
C
print {$out} <<'C';
#define INPUT_BUF_SIZE 4
#define JPEG_EOI 0xd9
#define JERR_FILE_READ 1
#define JERR_INPUT_EMPTY 2
#define DSTATE_INHEADER 1
#define METHODDEF(t) static t
#define EC(code) code
#define ERREXIT(c, code) return -1
#define TRACEMS(c, level, code) ((void)0)
#define WARNMS(c, code) ((void)0)
#define JFREAD(f, b, n) FileRead(1, b, n, FALSE)
typedef unsigned char JOCTET;
typedef struct {
    struct { Boolean eoi; JOCTET *next_input_byte; size_t bytes_in_buffer; } pub;
    JOCTET buffer[16], *next_input_byte;
    size_t bytes_in_buffer;
    FILE *infile;
    Boolean start_of_file;
    ImageInput *inputP;
} FakeSource;
typedef struct { ImageInput *inputP; } FakeInputCtl;
typedef struct { FakeSource *src; FakeInputCtl *inputctl; } FakeJPEG;
#define boolean Boolean
#define j_decompress_ptr FakeJPEG *
#define my_src_ptr FakeSource *
C
my $read = read_source("$root/Library/Breadbox/Ijgjpeg/DECOMP/JDATASRC.c");
$read = function($read, 'METHODDEF(boolean)');
$read =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
print {$out} $read;
print {$out} <<'C';
#undef j_decompress_ptr
typedef struct { FakeSource src; int global_state, error; } FakeFJPEG;
#define j_decompress_ptr FakeFJPEG *
#define fread(b, s, n, f) ((void)(f), FileRead(1, b, (word)((s)*(n)), FALSE))
static void set_error(FakeFJPEG *c, int code) { c->error = code; }
C
for my $entry (['init.c', 'Boolean fill_input_buffer_i'], ['decode.c', 'Boolean fill_input_buffer_a']) {
    my $code = function(read_source("$root/Library/Breadbox/Fjpeg/code/$entry->[0]"), $entry->[1]);
    $code =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
    print {$out} $code;
}
print {$out} <<'C';
#undef fread
static void CheckReaders(void)
{
    FakeSource src;
    FakeInputCtl ctl;
    FakeJPEG jpeg;
    FakeFJPEG fast;
    Source source;
    ImageInput input;
    memset(&src, 0, sizeof(src)); memset(&fast, 0, sizeof(fast));
    memset(&source, 0, sizeof(source)); input.callback = Input; input.clientDataP = &source;
    ctl.inputP = &input; jpeg.src = &src; jpeg.inputctl = &ctl;
    assert(fill_input_buffer(&jpeg) && fill_input_buffer(&jpeg));
    assert(!fill_input_buffer(&jpeg) && src.pub.eoi && src.pub.bytes_in_buffer == 2);
    assert(src.buffer[0] == 0xff && src.buffer[1] == JPEG_EOI);
    Input(&source, IIO_RESET, (void*)0, 0);
    fast.src.inputP = &input; fast.global_state = DSTATE_INHEADER;
    assert(fill_input_buffer_i(&fast) && source.operations[IIO_PRE_READ] == 1);
    fast.global_state = 0;
    assert(fill_input_buffer_a(&fast) && fill_input_buffer_a(&fast));
    assert(fast.src.bytes_in_buffer == 2 && fast.src.buffer[1] == JPEG_EOI);
    input.callback = (void*)0; fileReads = 0;
    assert(fill_input_buffer(&jpeg) == -1 && !fill_input_buffer_i(&fast));
    assert(!fill_input_buffer_a(&fast) && fast.error == JERR_FILE_READ && !fileReads);
    ctl.inputP = (void*)0; fast.src.inputP = (void*)0;
    assert(fill_input_buffer(&jpeg) && fill_input_buffer_i(&fast) && fill_input_buffer_a(&fast));
    assert(fileReads == 3);
}
C
for my $decoder (['Select', $jpeg], ['SelectFast', $fjpeg]) {
    my $select = part($decoder->[1], '  /* Streaming input and decoded-output',
        $decoder->[0] eq 'Select' ? '  /* Make sure it is a jpeg' : '  /* only pure RGB');
    $select .= part($fjpeg, '  *usedMem = 0 ;', '  /* Make sure it is a jpeg') if $decoder->[0] eq 'SelectFast';
    print {$out} "static int $decoder->[0](ImportState *importProgressDataP)\n{\nconst ImageInput *inputP; void *cinfo = 0; word filehan;\ndword used = 0, *usedMem = &used; char *file = \"image\";\n$select\n(void)filehan; return 1;\n}\n";
}
my $probe = part($jpeg, '  /* Make sure it is a jpeg', '  importProgressDataP->recognized = TRUE;');
$probe =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
print {$out} "static int Probe(const ImageInput *inputP)\n{\nvoid *cinfo = 0; word filehan = 1; Boolean status = FALSE;\n$probe\nreturn status;\n}\n";
print {$out} "static word ErrorCleanup(ImportState *importProgressDataP, word bmblock, word vmf)\n{\nword dataVMBlock;\n$error\nreturn dataVMBlock;\n}\n";
print {$out} "static word FlagCleanup(ImportState *importProgressDataP, word bmblock, word vmf, Boolean flag)\n{\nword dataVMBlock;\n$flag_error\nreturn dataVMBlock;\n}\n";
print {$out} "static int Abort(ImportState *importProgressDataP)\n{\nMimeStatus status, *mimeStatus = &status; Boolean flag = FALSE;\nstatus.MS_mimeFlags = MIME_STATUS_ABORT;\n$abort\nreturn !flag;\n}\n";
for my $decoder (['PublishJPEG', $jpeg], ['PublishFast', $fjpeg]) {
    my $publish = part($decoder->[1], "\t/* send out progress", "\t/* mark the graphic");
    $publish = part($decoder->[1], "\t/* send out progress", "\t/* this stop one line") if $decoder->[0] eq 'PublishJPEG';
    print {$out} "static void $decoder->[0](ImportState *importProgressDataP, word line, word height)\n{\nstruct { word output_scanline, output_height, output_width, image_height, image_width; } info, *cinfo = &info;\nword bmblock = importProgressDataP->IPD_bitmap;\ninfo.output_scanline = line; info.output_height = info.image_height = height; info.output_width = info.image_width = 20;\n$publish\n}\n";
}
# Use the real GIF start, reads and retained-prefix flush, independently of updates.
my $gif_start = function($gif, 'Boolean IGIFAnimStart(');
my $gif_read = part($gif, '            case IG_STATUS_OK:', '                if (sizeRead <');
$gif_read =~ s/^            case IG_STATUS_OK:\n//;
$gif_read =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
my $gif_flush = part($gif, '            case IG_STATUS_GIF_DONE:', '                /* Get information about this frame');
$gif_flush =~ s/^            case IG_STATUS_GIF_DONE:\n//;
$gif_flush =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
print {$out} <<'C';
#define INPUT_P p_work->importProgressDataP->IPD_inputP
#define IG_STATUS_NEED_DATA 1
#define IG_STATUS_OK 0
#define IG_STATUS_GIF_DONE 2
#define IG_STATUS_ERROR_NOT_GIF 3
#define IG_STATUS_END_DATA 4
#define IG_STATUS_FOUND_END_OF_GIF 5
#define IG_STATUS_ABORTED 6
#define IG_STATUS_ERROR 7
static word ImpGIFCreate(word f, int watcher, Boolean palette, MimeStatus *status)
{ (void)f; (void)watcher; (void)palette; (void)status; return 1; }
typedef struct {
    ImportState *importProgressDataP;
    struct { word IGI_bitmap; dword IGI_memoryUsed; } info;
    struct { word IGPI_bitmap, IGPI_fieldWidth, IGPI_fieldHeight, IGPI_yPos; } progressInfo;
    word frameNum;
    word numFrames, picFile, GIFState, vmFile;
    int watcher, status;
    Boolean useSysPal, lastBlock, keepGoing;
    MimeStatus *mimeStatus;
    char picFilename[6], buffer[4];
} GIFAnimWorkStruct;
C
print {$out} <<'C';
static int gifStatus;
static word gifBitmap, gifLine;
static int ImpGIFProcess(word state, void *data, word size, int last)
{ (void)state; (void)data; (void)size; (void)last; return gifStatus; }
#define ImpGIFGetInfo(h,p) ((void)(h), (p)->IGI_bitmap = gifBitmap, (p)->IGI_memoryUsed = 600)
#define ImpGIFGetProgressInfo(h,p) ((void)(h), (p)->IGPI_bitmap = gifBitmap, \
    (p)->IGPI_fieldWidth = 20, (p)->IGPI_fieldHeight = 30, (p)->IGPI_yPos = gifLine)
static void AllocWatcherFree(word h, dword amount) { (void)h; (void)amount; }
C
my $grab = function($gif, 'Boolean IGIFAnimGrabFrame(');
$grab =~ s/ProcCallFixedOrMovable_pascal/CallInput/g;
print {$out} $grab;
print {$out} "$gif_start\n";
print {$out} "static word ReadGIF(GIFAnimWorkStruct *p_work)\n{\nword sizeRead;\n$gif_read\nreturn sizeRead;\n}\n";
print {$out} "static void FlushGIF(GIFAnimWorkStruct *p_work, word sizeRead)\n{\n$gif_flush\n}\n";
# Compile the real five-argument entry/validation/fallback/compaction/result code;
# only format decoding and GEOS graphics primitives are stubbed here.
print {$out} <<'C';
static Boolean allowAnimations = TRUE, doCompress = TRUE;
static int backend, backendCalls, makePartial, makeCancel, decodeFailure;
static int publishDuringDecode, distinctFinal, compactFinal;
static void InitGlobals(void) {}
static word AllocWatcherCreate(dword amount) { (void)amount; return 1; }
static void AllocWatcherDestroy(word h) { assert(h == 1); }
static word GrCompactBitmap(word f, word b, word dest)
{ assert(f == dest && imageLive[b][f]); if (!compactFinal) return 0; NewImage(f, b+1); return b+1; }
static ImpBmpStatus Decode(int kind, VMFileHandle vmf, ImageAdditionalData *iad,
    dword *usedMem, VMBlockHandle *bmVMBlock, ImportState *stateP,
    MimeStatus *cancelP)
{
    backendCalls++;
    if (kind != backend) return IBS_UNKNOWN_FORMAT;
    iad->IAD_type = IAD_TYPE_BITMAP;
    iad->IAD_size.XYS_width = 20; iad->IAD_size.XYS_height = 30;
    iad->IAD_completeGraphic = !makePartial;
    NewImage(vmf, 11); stateP->IPD_bitmap = 11;
    if (publishDuringDecode) PublishJPEG(stateP, 10, 30);
    if (makeCancel) cancelP->MS_mimeFlags |= MIME_STATUS_ABORT;
    if (decodeFailure) {
        assert(!ErrorCleanup(stateP, 11, vmf));
        return IBS_WRONG_FILE;
    }
    *usedMem = 600;
    *bmVMBlock = 11;
    if (distinctFinal) { NewImage(vmf, 12); *bmVMBlock = 12; }
    return IBS_NO_ERROR;
}
C
for my $name (qw(ImpGIF ImpJPG ImpPNG ImpSVG)) {
    my $signature = part($engine, "ImpBmpStatus " . ($name eq 'ImpSVG' ? '_pascal ' : '') . "$name(", "\n{");
    $signature =~ s/\b$name\(/Stub$name(/;
    print {$out} "$signature\n{\n(void)file; (void)resolution; (void)watcher; (void)params; (void)isCompacted;\n";
    print {$out} "(void)destFile; (void)locAllowAnimations; (void)isAnimation;\n" if $name eq 'ImpGIF';
    print {$out} "(void)doCompress;\n" if $name ne 'ImpGIF';
    # Exercise actual rejection before file-only decoder opens a filename.
    if ($name eq 'ImpPNG' || $name eq 'ImpSVG') {
        print {$out} "if (importProgressDataP->IPD_inputP) return IBS_UNKNOWN_FORMAT;\n";
    }
    print {$out} 'return Decode(' . ($name eq 'ImpGIF' ? 1 : $name eq 'ImpJPG' ? 2 : $name eq 'ImpPNG' ? 3 : 5) . ', vmf, iad, usedMem, bmVMBlock, importProgressDataP, ' . ($name eq 'ImpGIF' ? 'params->IBP_mimeStatus' : 'mimeStatus') . ");\n}\n";
    print {$out} "#define $name Stub$name\n";
}
print {$out} <<'C';
static ImpBmpStatus StubWebP(TCHAR *file, VMFileHandle vmf, ImageAdditionalData *iad,
    word watcher, dword *usedMem, ImpBmpParams *params, Boolean *compacted,
    word *bitmap, ImportState *stateP, MimeStatus *cancelP)
{
    (void)file; (void)watcher; (void)params; (void)compacted;
    if (stateP->IPD_inputP) return IBS_UNKNOWN_FORMAT;
    return Decode(4, vmf, iad, usedMem, bitmap, stateP, cancelP);
}
#define ImpWebP StubWebP
C
print {$out} function($engine, 'ImageImportStatus _pascal _export MimeDrvGraphicEx(');
print {$out} function($engine, 'ImageImportStatus _pascal _export MimeDrvGraphic(');
print {$out} <<'C';
#define PNG_AT_BLEND 1
#define BMFormat word
#define PNG_TYPE_COLOR 1
typedef struct { word width, height, colorType, bitDepth; } pngIHDRData;
typedef struct { word unused; } pngPLTEChunkEntry;
typedef struct { word lineNo; void *currentRow; } pngIDATState;
typedef struct { int method, alphaThreshold;
    struct { int RGB_red, RGB_green, RGB_blue; } blendColor; } pngAlphaTransformData;
static word pngRows, pngHeight, pngErrorAt, pngCancelAt;
static MimeStatus *pngCancelP;
#define pngImportProcessChunks(f,h,c,n,p) \
    ((void)(f), (void)(c), (void)(n), (void)(p), \
     (h)->width = 20, (h)->height = pngHeight, TRUE)
#define pngCalcLineAllocSize(w,c,d) ((void)(c), (void)(d), (w))
#define AllocWatcherAllocate(w,n) ((void)(w), (void)(n), TRUE)
#define pngImportWhatOutputFormat(c,d,a) ((void)(c), (void)(d), (void)(a), 1)
static word pngImportInitiateOutputBitmap(word vmf, pngIHDRData h, word fmt)
{ (void)h; (void)fmt; NewImage(vmf, 45); return 45; }
#define pngImportHandlePalette(f,p,v,b,c,d) \
    ((void)(f), (void)(p), (void)(v), (void)(b), (void)(c), (void)(d))
#define pngImportInitIDATProcessingState(s,f,c,n,h) \
    ((void)(s), (void)(f), (void)(c), (void)(n), (void)(h))
#define pngImportIDATProcessingUnlockHandles(s) ((void)(s))
#define pngImportIDATProcessingLockHandles(s) ((void)(s))
#define pngImportApplyGEOSFormatTransformations(s,a) ((void)(s), (void)(a))
#define pngImportCleanupIDATProcessingState(s) ((void)(s))
static int pngImportGetNextIDATScanline(pngIDATState *s)
{
    if (pngErrorAt && s->lineNo == pngErrorAt) return -1;
    if (s->lineNo == pngRows) return 0;
    s->lineNo++; return 1;
}
static void pngImportWriteScanlineToBitmap(word f, word b, word row, void *p)
{
    (void)p; assert(f == 2 && b == 45 && row < pngHeight);
    if (pngCancelAt && row+1 == pngCancelAt) pngCancelP->MS_mimeFlags |= MIME_STATUS_ABORT;
}
C
my $png = read_source("$root/Library/Breadbox/ImpGraph/IMPBMP/imppng.goc");
$png = function($png, 'VMBlockHandle PngImport(');
$png =~ s{//[^\n]*}{}g;
print {$out} $png;
print {$out} <<'C';
#define CA_NULL_ELEMENT 0
#define OCDF_NOCACHE 0x80
#define EC_ERROR_IF(c,code) assert(!(c))
static int cacheLocked;
#define ObjCacheGrab() assert(!cacheLocked++)
#define ObjCacheRelease() assert(cacheLocked-- == 1)
#define CacheArrayLock() assert(cacheLocked)
#define CacheArrayUnlock() assert(cacheLocked)
static word ObjCacheFindEntryByToken(ObjCacheToken t, objCacheData **objP)
{ assert(cache[t].refs); *objP = &cache[t]; cache[t].lockCount = (word)cache[t].refs; return (word)t; }
C
my $finish = function(read_source("$FindBin::Bin/../cache/ObjectCache.goc"), 'void ObjCacheFinishImage(');
$finish =~ s/MemLock\(OptrToHandle\(objCacheArray\)\)/CacheArrayLock()/;
$finish =~ s/MemUnlock\(OptrToHandle\(objCacheArray\)\)/CacheArrayUnlock()/;
print {$out} $finish;
print {$out} <<'C';
static void InitRequest(T_importGraphicRequest *requestP, ImageImportUpdates *updatesP,
    ImportState *stateP)
{
    memset(requestP, 0, sizeof(*requestP)); memset(stateP, 0, sizeof(*stateP));
    requestP->name = 7; requestP->textObj = 5;
    updatesP->callback = ImportGraphicProgressCallback; updatesP->clientDataP = requestP;
    stateP->updatesP = updatesP; stateP->IPD_bitmap = 11; stateP->IPD_vmFile = 2;
    stateP->IPD_iad.IAD_size.XYS_width = 20; stateP->IPD_iad.IAD_size.XYS_height = 30;
    stateP->IPD_iad.IAD_type = IAD_TYPE_BITMAP;
}
static void Drain(void)
{
    int i;
    for (i = 0; i < queueCount; i++) Receive(queued[i]);
    queueCount = 0;
}
static void CheckOwnership(void)
{
    T_importGraphicRequest request;
    ImageImportUpdates updates;
    ImageImportUpdate final;
    ImportState state;
    int i, t, transfers;
    InitRequest(&request, &updates, &state);
    /* An unpublished decode failure must release its bitmap. */
    NewImage(2, 11); assert(!ErrorCleanup(&state, 11, 2));
    assert(!imageLive[11][2] && !request.publicationsH);
    /* Actual JPEG scanline publication followed by its actual error cleanup. */
    NewImage(2, 11); PublishJPEG(&state, 10, 30); PublishJPEG(&state, 20, 30);
    assert(queueCount == 1 && state.publicationsH && request.publicationsH);
    t = ((ImportTokens *)blocks[request.publicationsH].data)->tokens[0];
    assert(cache[t].refs == 2);
    assert(!ErrorCleanup(&state, 11, 2) && imageLive[11][2]);
    /* A distinct replacement does not release the old request reference. */
    NewImage(2, 12); state.IPD_bitmap = 12; PublishFast(&state, 10, 30);
    assert(queueCount == 2 && cache[t].refs == 2);
    assert(!FlagCleanup(&state, 12, 2, TRUE) && imageLive[12][2]);
    state.keepPartial = FALSE; assert(!Abort(&state));
    state.keepPartial = TRUE; assert(Abort(&state));
    /* Both same-image and distinct final adoption use the retention code. */
    final.vmFile = 2; final.bitmap = 12; final.info = state.IPD_iad;
    t = ImportLockCacheToken(&request, &final);
    final.info.IAD_completeGraphic = TRUE;
    ObjCacheFinishImage(t, &final.info, TRUE);
    assert(cache[t].auxdata.graph.IAD_completeGraphic);
    ObjCacheUnlockItem(t);
    assert(((ImportTokens *)blocks[request.publicationsH].data)->count == 2);
    NewImage(2, 13); final.bitmap = 13;
    t = ImportLockCacheToken(&request, &final); ObjCacheUnlockItem(t);
    ImportForgetPublications(&state); ImportReleasePublications(&request);
    assert(imageLive[11][2] && imageLive[12][2] && !imageLive[13][2]);
    memset(&request, 0xa5, sizeof(request)); /* borrowed request has expired */
    Drain(); assert(!imageLive[11][2] && !imageLive[12][2]);
    /* Identity includes VM file; growth is not capped at one block. */
    InitRequest(&request, &updates, &state);
    for (i = 0; i < 70; i++) {
        NewImage(2, (word)(100+i)); state.IPD_bitmap = (word)(100+i);
        PublishJPEG(&state, 10, 30);
    }
    NewImage(3, 100); state.IPD_vmFile = 3; state.IPD_bitmap = 100;
    PublishJPEG(&state, 10, 30);
    transfers = 0;
    for (i = 1; i < LIMIT; i++) if (cache[i].refs) transfers++;
    assert(transfers == 71 && queueCount == 71);
    Drain(); /* UI consumes all notifications while decoder is still active */
    for (i = 0; i < 70; i++) assert(imageLive[100+i][2]);
    ImportForgetPublications(&state); ImportReleasePublications(&request);
    assert(!imageLive[100][3]);
    for (i = 0; i < 70; i++) assert(imageFrees[100+i][2] == 1);
    /* Notification OOM does not undo ownership transfer. */
    InitRequest(&request, &updates, &state); NewImage(2, 20);
    state.IPD_bitmap = 20; state.IPD_firstLine = 0; state.IPD_lastLine = 9;
    /* Preallocate decoder record, then fail the notification allocation. */
    state.publicationsH = MemAlloc(sizeof(ImportPublications), HF_DYNAMIC, HAF_ZERO_INIT);
    failAlloc = 1; ImportPublish(&state); failAlloc = 0;
    assert(request.publicationsH && !queueCount && imageLive[20][2]);
    assert(!ErrorCleanup(&state, 20, 2) && imageLive[20][2]);
    ImportForgetPublications(&state); ImportReleasePublications(&request);
    assert(imageFrees[20][2] == 1);
    /* Decoder record OOM suppresses publication, leaving private ownership. */
    InitRequest(&request, &updates, &state); NewImage(2, 21);
    state.IPD_bitmap = 21; state.IPD_firstLine = 0; state.IPD_lastLine = 9;
    failAlloc = 1; ImportPublish(&state); failAlloc = 0;
    assert(!state.publicationsH && !request.publicationsH && !queueCount);
    assert(!ErrorCleanup(&state, 21, 2) && imageFrees[21][2] == 1);
    /* Invalid ranges never publish or transfer ownership. */
    InitRequest(&request, &updates, &state); NewImage(2, 23);
    state.IPD_bitmap = 23; state.IPD_firstLine = 0; state.IPD_lastLine = 30;
    ImportPublish(&state); assert(!state.publicationsH && !queueCount);
    state.IPD_firstLine = 10; state.IPD_lastLine = 9;
    ImportPublish(&state); assert(!state.publicationsH && !queueCount);
    assert(!ErrorCleanup(&state, 23, 2) && imageFrees[23][2] == 1);
    /* A short final slice cannot underflow its inclusive row range. */
    InitRequest(&request, &updates, &state); NewImage(2, 22); state.IPD_bitmap = 22;
    PublishJPEG(&state, 1, 1); assert(queueCount == 1);
    assert(((ImportGraphicProgress *)blocks[queued[0]].data)->firstLine == 0);
    assert(((ImportGraphicProgress *)blocks[queued[0]].data)->lastLine == 0);
    ImportForgetPublications(&state); ImportReleasePublications(&request);
    text.HTI_imageArray = 0; Drain(); text.HTI_imageArray = 1;
    assert(imageFrees[22][2] == 1 && !nameRefs);
}
static void CheckGIF(void)
{
    T_importGraphicRequest request;
    ImageImportUpdates updates;
    ImportState state;
    GIFAnimWorkStruct gif;
    int display, keep, ending, grabbed;
    for (display = 0; display < 2; display++) for (keep = 0; keep < 2; keep++) {
        for (ending = 0; ending < 3; ending++) {
            InitRequest(&request, &updates, &state);
            state.keepPartial = keep; state.updatesP = display ? &updates : (void*)0;
            memset(&gif, 0, sizeof(gif)); gif.importProgressDataP = &state;
            gif.vmFile = 2; gif.keepGoing = TRUE;
            gifBitmap = 46; NewImage(2, 46); gifLine = 11;
            gifStatus = ending == 0 ? IG_STATUS_ABORTED : ending == 1 ? IG_STATUS_END_DATA : IG_STATUS_ERROR;
            grabbed = IGIFAnimGrabFrame(&gif);
            assert(grabbed == (keep && ending != 2));
            if (grabbed) FreeViaProgress(&state, 2, gif.info.IGI_bitmap);
            /* Terminal state must never re-read/free the previous native frame. */
            assert(!IGIFAnimGrabFrame(&gif));
            if (display) assert(imageLive[46][2] && queueCount == 1);
            else assert(!imageLive[46][2]);
            ImportForgetPublications(&state); ImportReleasePublications(&request); Drain();
            assert(!imageLive[46][2]);
        }
    }
    /* Progressive first frame is not a child of the copied animation frame. */
    InitRequest(&request, &updates, &state); memset(&gif, 0, sizeof(gif));
    gif.importProgressDataP = &state; gif.keepGoing = TRUE; gif.vmFile = 2;
    gifBitmap = 46; NewImage(2, 46); gifLine = 30; gifStatus = IG_STATUS_GIF_DONE;
    assert(IGIFAnimGrabFrame(&gif));
    assert(((ImportGraphicProgress *)blocks[queued[0]].data)->lastLine == 29);
    FreeViaProgress(&state, 2, 46); /* composite/copy cleanup preserves preview */
    gifBitmap = 0; gifStatus = IG_STATUS_FOUND_END_OF_GIF;
    assert(!IGIFAnimGrabFrame(&gif));
    ImportForgetPublications(&state); ImportReleasePublications(&request); Drain();
    assert(!imageLive[46][2]);
}
static void CheckPNG(void)
{
    T_importGraphicRequest request;
    ImageImportUpdates updates;
    ImportState state;
    MimeStatus cancel;
    word bitmap;
    XYSize size;
    Boolean complete;
    dword used;
    int display, keep, mode;
    for (display = 0; display < 2; display++) for (keep = 0; keep < 2; keep++) {
        for (mode = 0; mode < 6; mode++) {
            InitRequest(&request, &updates, &state);
            state.keepPartial = keep; state.updatesP = display ? &updates : (void*)0;
            cancel.MS_mimeFlags = 0; pngCancelP = &cancel;
            pngHeight = mode == 0 ? 1 : 30;
            pngRows = mode == 5 ? 0 : mode == 4 ? 31 : pngHeight;
            pngErrorAt = mode == 1 ? 10 : 0; pngCancelAt = mode == 2 ? 10 : 0;
            bitmap = PngImport("image", 2, &size, 0, 1, &used, &complete, &state, &cancel);
            if (mode == 1 || mode == 4 || mode == 5 || (mode == 2 && !keep)) assert(!bitmap);
            else assert(bitmap == 45);
            if (mode == 0 || mode == 3) assert(complete);
            if (mode == 1 || mode == 4) assert(!complete);
            if (bitmap) FreeViaProgress(&state, 2, bitmap);
            if (display && mode != 5) assert(imageLive[45][2]);
            else assert(!imageLive[45][2]);
            ImportForgetPublications(&state); ImportReleasePublications(&request); Drain();
            assert(!imageLive[45][2]);
        }
    }
}
static void CheckInput(void)
{
    ImportState state;
    ImageInput input;
    Source source;
    GIFAnimWorkStruct gif;
    char bytes[16];
    int streaming, display;
    for (streaming = 0; streaming < 2; streaming++) for (display = 0; display < 2; display++) {
        memset(&state, 0, sizeof(state)); memset(&source, 0, sizeof(source));
        input.callback = Input; input.clientDataP = &source;
        state.IPD_inputP = streaming ? &input : (void*)0;
        state.updatesP = display ? (const ImageImportUpdates *)&input : (void*)0;
        fileOpens = 0; assert(Select(&state)); assert(fileOpens == !streaming);
        fileOpens = 0; assert(SelectFast(&state)); assert(fileOpens == !streaming);
        assert(Probe(state.IPD_inputP));
        if (streaming) {
            assert(Input(&source, IIO_PRE_READ, bytes, 4) == 4);
            assert(Probe(&input) && source.pos == 0);
            assert(Input(&source, IIO_READ, bytes, sizeof(bytes)) == 8);
            assert(!Input(&source, IIO_READ, bytes, 1));
            Input(&source, IIO_RESET, (void*)0, 0);
        }
        memset(&gif, 0, sizeof(gif)); gif.importProgressDataP = &state;
        strcpy(gif.picFilename, "image"); fileOpens = fileReads = 0;
        assert(IGIFAnimStart(&gif) && fileOpens == !streaming);
        assert(ReadGIF(&gif) == 4 && fileReads == !streaming); FlushGIF(&gif, 4);
        if (streaming) assert(source.operations[IIO_FLUSH_FIRST] == 1);
    }
    input.callback = (void*)0; state.IPD_inputP = &input; fileOpens = 0;
    assert(!Select(&state) && !SelectFast(&state) && !fileOpens);
    gif.importProgressDataP = &state;
    assert(!IGIFAnimStart(&gif) && !fileOpens);
}
static void CheckAPI(void)
{
    ImageImportSource source;
    ImageImportOptions options;
    ImageImportResult result;
    ImageImportUpdates updates;
    T_importGraphicRequest request;
    ImportState state;
    ImageInput input;
    Source encoded;
    ImageImportStatus status;
    MimeStatus cancel;
    int stream, display, mode;
    memset(&options, 0, sizeof(options)); memset(&encoded, 0, sizeof(encoded));
    input.callback = Input; input.clientDataP = &encoded;
    options.mimeTypeP = "image/jpeg"; options.watcherH = 1; options.cancelP = &cancel;
    backend = 2;
    for (stream = 0; stream < 2; stream++) for (display = 0; display < 2; display++) {
        for (mode = 0; mode < 7; mode++) {
            InitRequest(&request, &updates, &state);
            source.type = stream ? IIS_STREAM : IIS_FILE;
            if (stream) source.data.inputP = &input; else source.data.filenameP = "image";
            cancel.MS_mimeFlags = 0; makePartial = mode == 2 || mode == 3;
            makeCancel = mode == 3 || mode == 4; decodeFailure = mode == 5;
            compactFinal = mode == 6; distinctFinal = mode == 1;
            publishDuringDecode = display; options.keepPartial = TRUE;
            memset(&result, 0xa5, sizeof(result)); backendCalls = 0;
            status = MimeDrvGraphic(&source, 2, &options, display ? &updates : (void*)0, &result);
            assert(backendCalls == 1);
            assert(status == (makeCancel ? IMAGE_IMPORT_CANCELED : decodeFailure ? IMAGE_IMPORT_FAILURE :
                makePartial ? IMAGE_IMPORT_PARTIAL : IMAGE_IMPORT_SUCCESS));
            if (decodeFailure) assert(!result.bitmap && !result.usedMem && !result.info.IAD_size.XYS_height);
            else {
                ImageImportUpdate final;
                final.vmFile = 2; final.bitmap = result.bitmap; final.info = result.info;
                ObjCacheUnlockItem(ImportLockCacheToken(&request, &final));
            }
            ImportReleasePublications(&request); Drain();
            /* Distinct fake final copied a private image in the no-update case. */
            if (distinctFinal && !display) VMFreeVMChain(2, 11);
            assert(!imageLive[11][2] && !imageLive[12][2]);
        }
    }
    makePartial = makeCancel = decodeFailure = compactFinal = distinctFinal = publishDuringDecode = 0;
    source.type = IIS_FILE; source.data.filenameP = "image"; cancel.MS_mimeFlags = 0;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, (void*)0) == IMAGE_IMPORT_INVALID);
    assert(MimeDrvGraphic((void*)0, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID && !result.bitmap);
    assert(MimeDrvGraphic(&source, 0, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    assert(MimeDrvGraphic(&source, 2, (void*)0, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    updates.callback = (void*)0;
    assert(MimeDrvGraphic(&source, 2, &options, &updates, &result) == IMAGE_IMPORT_INVALID);
    options.flags = 4;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    options.flags = 0; source.data.filenameP = "";
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    source.type = (ImageImportSourceType)99;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    source.type = IIS_STREAM; source.data.inputP = (void*)0;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    source.data.inputP = &input; input.callback = (void*)0;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_INVALID);
    input.callback = Input;
    options.mimeTypeP = "image/png";
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_UNSUPPORTED);
    options.mimeTypeP = "image/webp";
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_UNSUPPORTED);
    options.mimeTypeP = "image/svg+xml";
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_UNSUPPORTED);
    options.mimeTypeP = "image/gif"; options.flags = MIME_GREX_NO_ANIMATIONS;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_UNSUPPORTED);
    options.flags = 0;
    /* GIF hint can fall back to JPEG without using any filename. */
    status = MimeDrvGraphic(&source, 2, &options, (void*)0, &result);
    assert(status == IMAGE_IMPORT_SUCCESS && result.bitmap == 11); VMFreeVMChain(2, 11);
    options.mimeTypeP = "image/jpeg"; options.keepPartial = FALSE; makePartial = 1;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_FAILURE && !result.bitmap);
    assert(!imageLive[11][2]); makePartial = 0;
    cancel.MS_mimeFlags = MIME_STATUS_ABORT; backendCalls = 0;
    assert(MimeDrvGraphic(&source, 2, &options, (void*)0, &result) == IMAGE_IMPORT_CANCELED && !backendCalls);
}
int main(void)
{
    int i, j;
    CheckReaders(); CheckInput(); CheckOwnership(); CheckGIF(); CheckPNG(); CheckAPI();
    for (i = 0; i < 5; i++) {
        assert(ImportGraphicInputCallback(&text, (ImageInputOperation)i, &text, 9) == 9);
        assert(mapped == i);
    }
    assert(!ImportGraphicInputCallback(&text, (ImageInputOperation)99, &text, 9));
    for (i = 1; i < LIMIT; i++) {
        assert(!blocks[i].live && !cache[i].refs);
        for (j = 1; j < 4; j++) assert(!imageLive[i][j]);
    }
    assert(!queueCount && !nameRefs && !semDepth);
    puts("Import API: validation, independent modes, probing/EOF, publication cleanup, retention and OOM passed.");
    return 0;
}
C
close $out or die $!;
system('cc', '-std=c89', '-Wall', '-Wextra', '-Werror', "$tmp/check.c", '-o', "$tmp/check") == 0
    or die "Host compilation failed\n";
system("$tmp/check") == 0 or die "Import callback check failed\n";
