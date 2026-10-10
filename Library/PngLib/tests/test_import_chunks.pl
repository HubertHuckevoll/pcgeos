#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;

# Run: perl Library/PngLib/tests/test_import_chunks.pl
# Exercise the real chunk scanner with host file and GEOS memory stubs.
# This checks chunk layout and cleanup, not CRCs or pixel decompression.
my $source;
{
    local $/;
    open my $in, '<:raw', "$FindBin::Bin/../pngimp.c" or die $!;
    $source = <$in>;
}
my ($scanner) = $source =~ /(int _pascal _export pngImportCheckHeader\(.*?)(?=\/\* init the IDAT processing structure \*\/)/s;
my ($row_size) = $source =~ /(unsigned long _pascal _export pngCalcBytesPerRow\(.*?)(?=\/\* Bytes per Pixel\.)/s;
die "cannot extract PNG routines\n" unless defined $scanner && defined $row_size;
my $dir = tempdir(CLEANUP => 1);
open my $out, '>', "$dir/check.c" or die $!;
print {$out} <<'C';
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define _pascal
#define _export
#define FALSE 0
#define NullHandle 0
#define FILE_POS_START SEEK_SET
#define FILE_POS_RELATIVE SEEK_CUR
#define HF_SWAPABLE 0
#define HF_SHARABLE 0
#define HAF_ZERO_INIT 0
#define PNG_CHUNK_IHDR 0x49484452UL
#define PNG_CHUNK_IDAT 0x49444154UL
#define PNG_CHUNK_IEND 0x49454e44UL
#define PNG_CHUNK_PLTE 0x504c5445UL
#define PNG_MAX_IDAT_CHUNKS 256
#define PNG_MAX_SCANLINE_SIZE 6144
#define PNG_COLOR_TYPE_GREY 0
#define PNG_COLOR_TYPE_RGB 2
#define PNG_COLOR_TYPE_PALETTE 3
#define PNG_COLOR_TYPE_GREY_ALPHA 4
#define PNG_COLOR_TYPE_RGBA 6
static const unsigned char PNG_SIGNATURE[8] = {137,80,78,71,13,10,26,10};
typedef int FileHandle;
typedef int MemHandle;
#pragma pack(push, 1)
typedef struct {
    uint32_t width, height;
    unsigned char bitDepth, colorType, compressionMethod, filterMethod, interlaceMethod;
} pngIHDRData;
typedef struct { uint32_t length, type; } pngChunkHeader;
typedef struct { uint32_t length, chunkPos; } pngIDATChunkEntry;
#pragma pack(pop)
typedef pngIDATChunkEntry pngPLTEChunkEntry;
static FILE *fileP;
static pngIDATChunkEntry entries[PNG_MAX_IDAT_CHUNKS];
static int allocated, allocFail, readCount, failRead;

unsigned long _pascal swapEndian(unsigned long value)
{
    return ((value & 0xffUL) << 24) | ((value & 0xff00UL) << 8) |
        ((value & 0xff0000UL) >> 8) | ((value & 0xff000000UL) >> 24);
}
unsigned int _pascal FileRead(FileHandle file, void *dataP, unsigned int size, int flags)
{
    (void)file; (void)flags;
    if (++readCount == failRead) return 0xffff;
    return (unsigned int)fread(dataP, 1, size, fileP);
}
unsigned long _pascal FilePos(FileHandle file, unsigned long offset, int mode)
{
    (void)file;
    assert(fseek(fileP, (long)offset, mode) == 0);
    return (unsigned long)ftell(fileP);
}
unsigned long _pascal FileSize(FileHandle file)
{
    long position, size;
    (void)file;
    position = ftell(fileP);
    assert(fseek(fileP, 0, SEEK_END) == 0);
    size = ftell(fileP);
    assert(fseek(fileP, position, SEEK_SET) == 0);
    return (unsigned long)size;
}
MemHandle _pascal MemAlloc(unsigned int size, int flags, int allocFlags)
{
    (void)flags; (void)allocFlags;
    assert(!allocated && size == sizeof(entries));
    if (allocFail) return NullHandle;
    allocated = 1;
    memset(entries, 0, sizeof(entries));
    return 1;
}
void *_pascal MemLock(MemHandle handle)
{
    assert(handle == 1 && allocated);
    return entries;
}
void _pascal MemUnlock(MemHandle handle) { assert(handle == 1 && allocated); }
void _pascal MemFree(MemHandle handle) { assert(handle == 1 && allocated); allocated = 0; }
unsigned long _pascal pngCalcBytesPerRow(unsigned long width, unsigned char colorType, unsigned char bitDepth);
C
print {$out} $scanner, $row_size;
print {$out} <<'C';
int main(int argc, char **argv)
{
    pngIHDRData header = {0};
    pngPLTEChunkEntry palette = {0};
    MemHandle idatH = NullHandle;
    int count = 0, expected;
    assert(sizeof(header) == 13 && sizeof(pngChunkHeader) == 8);
    assert(argc == 5);
    expected = argv[2][0] - '0';
    allocFail = argv[3][0] - '0';
    failRead = argv[4][0] - '0';
    fileP = fopen(argv[1], "rb");
    assert(fileP != (void *)0);
    /* The scanner must work even after an earlier signature probe. */
    assert(fseek(fileP, 8, SEEK_SET) == 0);
    assert(pngImportProcessChunks(1, &header, &idatH, &count, &palette) == expected);
    if (expected) {
        assert(idatH == 1 && count > 0 && allocated);
        MemFree(idatH);
    } else {
        assert(idatH == NullHandle && count == 0 && !allocated);
        assert(palette.length == 0 && palette.chunkPos == 0);
    }
    assert(fclose(fileP) == 0);
    return 0;
}
C
close $out or die $!;
system('cc', '-std=c89', '-Wall', '-Wextra', '-Werror', "$dir/check.c", '-o', "$dir/check") == 0
    or die "compilation failed\n";
my $signature = "\x89PNG\r\n\x1a\n";
# CRC values are irrelevant to this chunk-layout check.
my $ihdr = pack('NNCCCCC', 1, 1, 8, 0, 0, 0, 0);
my $header = pack('Na4', 13, 'IHDR') . $ihdr . "\0" x 4;
my $idat = pack('Na4', 1, 'IDAT') . 'x' . "\0" x 4;
my $iend = pack('Na4N', 0, 'IEND', 0);
my $valid = $signature . $header . $idat . $iend;
my @cases = (
    ['valid layout', $valid, 1],
    ['split IDAT', $signature . $header . $idat . $idat . $iend, 1],
    ['empty file', '', 0],
    ['bad signature', 'invalid!' . $header . $idat . $iend, 0],
    ['IDAT first', $signature . $idat . $iend, 0],
    ['IEND first', $signature . $iend, 0],
    ['ancillary first', $signature . pack('Na4N', 0, 'tEXt', 0) . $header . $idat . $iend, 0],
    ['duplicate IHDR', $signature . $header . $header . $idat . $iend, 0],
    ['short IHDR', $signature . pack('Na4', 12, 'IHDR') . substr($ihdr, 0, 12) . "\0" x 4, 0],
    ['long IHDR', $signature . pack('Na4', 14, 'IHDR') . $ihdr . 'x' . "\0" x 4, 0],
    ['no IDAT', $signature . $header . $iend, 0],
    ['missing IEND', $signature . $header . $idat, 0],
    ['bad IEND length', $signature . $header . $idat . pack('Na4', 1, 'IEND') . 'x' . "\0" x 4, 0],
    ['overflowing chunk', $signature . $header . pack('Na4N', 0xffffffff, 'IDAT', 0), 0],
    ['too many IDATs', $signature . $header . ($idat x 257) . $iend, 0],
    ['allocation failure', $valid, 0, 1],
);
for my $read (1 .. 5) {
    push @cases, ["read error $read", $valid, 0, 0, $read];
}
for my $length (0 .. length($valid) - 1) {
    push @cases, ["truncated $length", substr($valid, 0, $length), 0];
}
for my $case (@cases) {
    my ($name, $data, $expected, $alloc_fail, $read_fail) = @$case;
    my $path = "$dir/$name.png";
    open my $file, '>:raw', $path or die $!;
    print {$file} $data or die $!;
    close $file or die $!;
    system("$dir/check", $path, $expected, $alloc_fail || 0, $read_fail || 0) == 0
        or die "$name failed\n";
}
for my $path (glob("$FindBin::Bin/*.png")) {
    system("$dir/check", $path, 1, 0, 0) == 0 or die "$path failed\n";
}
print "PNG chunk scanner regression checks passed\n";
