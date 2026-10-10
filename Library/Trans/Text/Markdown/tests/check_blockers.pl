#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

# Compile the actual GOC routines with host stubs; no PC/GEOS runtime needed.
my $source;
{
    local $/;
    open my $in, '<:raw', "$FindBin::Bin/../Import/markdownImport.goc" or die $!;
    $source = <$in>;
}
my ($reader) = $source =~ /(int MDReadChar\(.*?)(?=TransError MDReadLine\()/s;
{
    local $/;
    open my $in, '<:raw', "$FindBin::Bin/../Export/exportMarkdown.goc" or die $!;
    $source = <$in>;
}
my ($writer) = $source =~ /(TransError MDWriteGraphicPNG\(.*?)(?=Boolean MDGetGraphic\()/s;
die "cannot extract routines\n" unless defined $reader && defined $writer;
my $dir = tempdir(CLEANUP => 1);
open my $out, '>', "$dir/check.c" or die $!;
print {$out} <<'C';
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define _pascal
#define FALSE 0
#define TRUE 1
#define NullHandle 0
#define MD_EXPORT_OUTPUT 6656
#define MD_EXPORT_LINE 2048
#define VMCHAIN_MAKE_FROM_VM_BLOCK(b) (b)
#define FCF_NATIVE 0x8000
#define FILE_CREATE_ONLY (2 << 8)
#define FILE_ACCESS_RW 2
#define FILE_DENY_RW 0x10
#define FILE_ATTR_NORMAL 0
#define ERROR_INSUFFICIENT_MEMORY 1
#define PE_NO_ERROR 0
#define PE_WRITE_PROBLEM 1
#define TE_NO_ERROR 0
#define TE_OUT_OF_MEMORY 1
#define TE_FILE_OPEN 2
#define TE_FILE_WRITE 3

typedef unsigned char byte;
typedef unsigned short word;
typedef int Boolean;
typedef int TransError;
typedef int PngError;
typedef int FileHandle;
typedef int VMBlockHandle;
typedef struct { int unused; } VisTextGraphic;
typedef struct { int EF_outputPathDisk; const char *EF_outputPathName; } ExportFrame;
typedef struct {
    Boolean pendingValid;
    byte pending, pushed[3];
    word pushCount;
    const byte *inputP;
    int end;
} MDState;
typedef struct {
    int buffersH, vmFile;
    char *renderedP, *lineP;
    byte *kindsP;
    ExportFrame *frameP;
} MDExportState;

static char buffers[MD_EXPORT_OUTPUT + 2 * MD_EXPORT_LINE];
static int locked = 1, depth, pngError, closeError;

int _pascal MDRawRead(MDState *stateP)
{
    if (stateP->pushCount) return stateP->pushed[--stateP->pushCount];
    return *stateP->inputP ? *stateP->inputP++ : stateP->end;
}
void _pascal MDRawPush(MDState *stateP, byte value)
{
    assert(stateP->pushCount < 3);
    stateP->pushed[stateP->pushCount++] = value;
}
int _pascal HTMLTranslateCharNum(unsigned int value)
{
    /* Source-verified HTML special entities and supported SBCS mappings. */
    switch (value) {
    case 0x00de: return 10010;
    case 0x00bd: return 10006;
    case 0x00b2: return 10003;
    case 0x00e4: return 0x8a;
    case 0x20ac: return 0xdb;
    }
    return 0;
}
void _pascal MemUnlock(int handle)
{
    (void)handle;
    assert(locked);
    locked = 0;
}
void *_pascal MemLock(int handle)
{
    (void)handle;
    assert(!locked);
    locked = 1;
    return buffers;
}
TransError _pascal MDRasterizeGraphic(MDExportState *stateP,
    VisTextGraphic *graphicP, VMBlockHandle *bitmapP)
{
    (void)stateP; (void)graphicP;
    *bitmapP = 1;
    return TE_NO_ERROR;
}
void _pascal FilePushDir(void) { ++depth; }
void _pascal FilePopDir(void) { --depth; }
int _pascal FileSetCurrentPath(int disk, const char *pathP)
{
    (void)disk; (void)pathP;
    return TRUE;
}
FileHandle _pascal FileCreate(const char *nameP, int flags, int attrs)
{
    int fileH;
    (void)attrs;
    fileH = open(nameP, O_CREAT | O_RDWR |
        ((flags & (3 << 8)) == FILE_CREATE_ONLY ? O_EXCL : O_TRUNC), 0600);
    return fileH < 0 ? NullHandle : fileH;
}
int _pascal ThreadGetError(void) { return 0; }
PngError _pascal pngExportBitmapFHandle(int file, int bitmap, FileHandle fileH)
{
    (void)file; (void)bitmap;
    assert(write(fileH, "new PNG", 7) == 7);
    return pngError;
}
TransError _pascal MDPngError(PngError error) { (void)error; return TE_FILE_WRITE; }
int _pascal FileClose(FileHandle fileH, Boolean noError)
{
    (void)noError;
    assert(close(fileH) == 0);
    return closeError;
}
void _pascal VMFreeVMChain(int file, int block) { (void)file; (void)block; }
void _pascal FileDelete(const char *nameP) { assert(unlink(nameP) == 0); }
C
print {$out} $reader, $writer;
print {$out} <<'C';
void _pascal CheckDecode(const char *inputP, const char *expectedP, int end)
{
    MDState state;
    memset(&state, 0, sizeof(state));
    state.inputP = (const byte *)inputP;
    state.end = end;
    while (*expectedP) assert(MDReadChar(&state) == (byte)*expectedP++);
    assert(MDReadChar(&state) == end);
}
int main(void)
{
    MDExportState state;
    ExportFrame frame;
    VisTextGraphic graphic;
    int fileH;
    char contents[7];

    CheckDecode("\xf0(ABC", "?(ABC", -1);
    CheckDecode("\xf0\x90(ABC", "?(ABC", -1);
    CheckDecode("\xf0\x90\x80(ABC", "?(ABC", -1);
    CheckDecode("\xf0\nABC", "?\nABC", -1);
    CheckDecode("\xf0\x90\r\nABC", "?\r\nABC", -1);
    CheckDecode("\xf0\x90\x80\nABC", "?\nABC", -1);
    CheckDecode("\xf0", "?", -1);
    CheckDecode("\xf0\x90", "?", -1);
    CheckDecode("\xf0\x90\x80", "?", -1);
    CheckDecode("\xf0\x90\x80\x80!", "?!", -1);
    CheckDecode("\xf4\x8f\xbf\xbf!", "?!", -1);
    CheckDecode("\xf0\x80\x80\x80!", "???" "!", -1);
    CheckDecode("\xf4\x90\x80\x80!", "???" "!", -1);
    CheckDecode("\xf0", "", -2);
    CheckDecode("\xf0\x90", "", -2);
    CheckDecode("\xf0\x90\x80", "", -2);
    CheckDecode("\xf0(ABC", "?(ABC", -2);
    CheckDecode("\xc3\x9e\xc2\xbd\xc2\xb2", "???", -1);
    CheckDecode("\xc3\xa4\xe2\x82\xac", "\x8a\xdb", -1);
    CheckDecode("\xe2\x98\x83", "?", -1);
    CheckDecode("\xc3(", "?(", -1);

    memset(&state, 0, sizeof(state));
    memset(&frame, 0, sizeof(frame));
    memset(&graphic, 0, sizeof(graphic));
    state.frameP = &frame;
    fileH = open("image.png", O_CREAT | O_WRONLY | O_EXCL, 0600);
    assert(fileH >= 0 && write(fileH, "old PNG", 7) == 7);
    assert(close(fileH) == 0);
    assert(MDWriteGraphicPNG(&state, &graphic, "image.png") == TE_FILE_OPEN);
    fileH = open("image.png", O_RDONLY);
    assert(fileH >= 0 && read(fileH, contents, 7) == 7);
    assert(memcmp(contents, "old PNG", 7) == 0);
    assert(close(fileH) == 0);
    assert(locked && depth == 0);

    pngError = PE_WRITE_PROBLEM;
    assert(MDWriteGraphicPNG(&state, &graphic, "failed.png") == TE_FILE_WRITE);
    assert(access("failed.png", F_OK) != 0 && locked && depth == 0);
    pngError = PE_NO_ERROR;
    closeError = 1;
    assert(MDWriteGraphicPNG(&state, &graphic, "failed.png") == TE_FILE_WRITE);
    assert(access("failed.png", F_OK) != 0 && locked && depth == 0);
    closeError = 0;
    assert(MDWriteGraphicPNG(&state, &graphic, "failed.png") == TE_NO_ERROR);
    assert(access("failed.png", F_OK) == 0 && locked && depth == 0);
    assert(state.renderedP == buffers);
    assert(state.lineP == buffers + MD_EXPORT_OUTPUT);
    puts("Markdown blocker regression checks passed");
    return 0;
}
C
close $out or die $!;
system('cc', '-std=c89', '-Wall', '-Wextra', '-Werror', "$dir/check.c", '-o', "$dir/check") == 0
    or die "compilation failed\n";
chdir $dir or die $!;
system('./check') == 0 or die "regression check failed\n";
