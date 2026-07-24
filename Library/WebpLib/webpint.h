#ifndef __WEBPINT_H
#define __WEBPINT_H

#include <geos.h>
#include <file.h>
#include <graphics.h>
#include <heap.h>
#include <lmem.h>
#include <hugearr.h>
#include <vm.h>
#include <Ansi/string.h>
#include <webplib.h>

#define WEBP_MAX_DIMENSION       2048
#define WEBP_INPUT_WINDOW        2048
#define WEBP_INPUT_BUFFER_SIZE   (WEBP_INPUT_WINDOW * 2)
#define WEBP_MAX_PARTITIONS      8

#define WEBP_FOURCC(a, b, c, d) \
    ((dword)(byte)(a) | ((dword)(byte)(b) << 8) | \
     ((dword)(byte)(c) << 16) | ((dword)(byte)(d) << 24))

typedef struct {
    dword start;
    dword length;
    dword next;
    dword windowStart;
    word windowSize;
    dword value;
    byte range;
    sbyte bits;
    byte eof;
    byte ioError;
    byte token;
} WebPBoolReader;

typedef struct {
    FileHandle source;
    VMFileHandle destination;
    VMBlockHandle bitmap;
    dword riffEnd;
    dword vp8Start;
    dword vp8Length;
    dword firstPartitionLength;
    word width;
    word height;
    word rowBytes;
    word mbWidth;
    word mbHeight;
    word mbY;
    word nextOutputLine;
    byte terminal;
    byte done;
    MemHandle inputH;
    MemHandle contextH;
    MemHandle lumaH;
    MemHandle chromaH;
    MemHandle rgbH;
    word core[2048];
} WebPDecoder;

WebPResult _pascal WebPParseContainer(FileHandle source, WebPDecoder *decoderP);
WebPResult _pascal WebPDecodeInit(WebPDecoder *decoderP);
WebPResult _pascal WebPDecodeRow(WebPDecoder *decoderP,
                                word *firstLine, word *lineCount);
void _pascal WebPDecodeCleanup(WebPDecoder *decoderP);

void _pascal WebPBoolInit(WebPDecoder *decoderP, WebPBoolReader *readerP,
                          dword start, dword length, Boolean token);
word _pascal WebPBoolGet(WebPDecoder *decoderP, WebPBoolReader *readerP,
                         word probability);
word _pascal WebPBoolGetValue(WebPDecoder *decoderP,
                              WebPBoolReader *readerP, word bitCount);

void _pascal WebPYUVToRGB(byte y, byte u, byte v, byte *rgbP);

#endif
