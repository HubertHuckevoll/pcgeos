/* Host-only heap shim and public streaming API checks. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "host.h"

typedef struct {
    byte *dataP;
    word size;
    unsigned locks;
} Block;
static Block blocks[16];
static unsigned failAllocation;
static unsigned allocation;

MemHandle MemAlloc(word size, word flags, word action)
{
    word h;
    (void)flags;
    (void)action;
    if (++allocation == failAllocation) return 0;
    for (h = 1; h < 16; h++) {
        if (!blocks[h].dataP) {
            blocks[h].dataP = (byte *)calloc(1, size);
            assert(blocks[h].dataP);
            blocks[h].size = size;
            return h;
        }
    }
    assert(0);
    return 0;
}
void *MemLock(MemHandle h)
{
    assert(h && h < 16 && blocks[h].dataP);
    blocks[h].locks++;
    return blocks[h].dataP;
}
void MemUnlock(MemHandle h)
{
    byte *newP;
    assert(blocks[h].locks);
    if (--blocks[h].locks) return;
    newP = (byte *)malloc(blocks[h].size);
    assert(newP);
    memcpy(newP, blocks[h].dataP, blocks[h].size);
    memset(blocks[h].dataP, 0xa5, blocks[h].size);
    free(blocks[h].dataP);
    blocks[h].dataP = newP;
}
void MemFree(MemHandle h)
{
    assert(h && h < 16 && blocks[h].dataP && !blocks[h].locks);
    free(blocks[h].dataP);
    memset(&blocks[h], 0, sizeof(Block));
}

#ifndef MP3_HEAP_ONLY
/* One caller's source and sink. No decoder internals are visible here. */
typedef struct {
    Mp3DecHandle decoderH;
    byte *sourceP;
    unsigned long length;
    unsigned long position;
    unsigned long pcmBytes;
    unsigned long calls;
    dword hash;
    word terminal;
    word chunk;
    word capacity;
    word sentEnd;
    word done;
    FILE *outputP;
} Stream;

static void Step(Stream *streamP)
{
    sword pcm[2304];
    Mp3DecFormat format;
    Mp3DecResult result;
    word frames, accepted, size, flags, i;
    unsigned long remaining;

    if (streamP->done) return;
    assert(++streamP->calls < streamP->length * 8 + 10000);
    result = Mp3DecReadPCM(streamP->decoderH, pcm, streamP->capacity,
                           &frames, &format);
    if (result == MP3DEC_OUTPUT_SMALL) {
        assert(!frames);
        streamP->capacity = 4;
        return;
    }
    if (frames) {
        assert(result == MP3DEC_PCM || result == MP3DEC_RECOVERABLE);
        assert(format.channels == 1 || format.channels == 2);
        assert(frames * format.channels * 2 <= streamP->capacity);
        assert(fwrite(pcm, 2 * format.channels, frames, streamP->outputP) == frames);
        for (i = 0; i < frames * format.channels * 2; i++)
            streamP->hash = (streamP->hash ^ ((byte *)pcm)[i]) * 16777619UL;
        streamP->pcmBytes += frames * format.channels * 2;
        return;
    }
    if (result == MP3DEC_FORMAT_CHANGED || result == MP3DEC_RECOVERABLE) return;
    if (result == MP3DEC_END) {
        streamP->done = 1;
        return;
    }
    if (result == MP3DEC_TRUNCATED || result == MP3DEC_FATAL) {
        streamP->terminal = result;
        streamP->done = 1;
        return;
    }
    assert(result == MP3DEC_NEED_INPUT);
    assert(!streamP->sentEnd);
    remaining = streamP->length - streamP->position;
    size = remaining > streamP->chunk ? streamP->chunk : (word)remaining;
    flags = remaining == size ? MP3DEC_FEED_END : 0;
    result = Mp3DecFeed(streamP->decoderH, streamP->sourceP + streamP->position,
                        size, flags, &accepted);
    assert(result == MP3DEC_PCM || result == MP3DEC_INPUT_FULL);
    assert(accepted <= size);
    streamP->position += accepted;
    if (flags && size == accepted) streamP->sentEnd = 1;
}

static void OpenStream(Stream *streamP, const char *sourceP,
                       const char *outputP, word chunk, word capacity)
{
    FILE *fileP;
    memset(streamP, 0, sizeof(*streamP));
    fileP = fopen(sourceP, "rb");
    assert(fileP && !fseek(fileP, 0, SEEK_END));
    streamP->length = ftell(fileP);
    assert(!fseek(fileP, 0, SEEK_SET));
    streamP->sourceP = (byte *)malloc(streamP->length + 1);
    assert(streamP->sourceP);
    assert(fread(streamP->sourceP, 1, streamP->length, fileP) == streamP->length);
    assert(!fclose(fileP));
    streamP->outputP = fopen(outputP, "wb");
    assert(streamP->outputP);
    streamP->hash = 2166136261UL;
    streamP->chunk = chunk;
    streamP->capacity = capacity;
    assert(Mp3DecCreate(&streamP->decoderH) == MP3DEC_PCM);
}

int main(int argc, char **argvP)
{
    Stream first, second;
    Mp3DecHandle decoderH;
    Mp3DecFormat format;
    unsigned h, fail;
    dword hash;
    unsigned long pcmBytes;
    word accepted, frames;
    byte junk[2049];

    assert(argc == 7);
    for (fail = 1; fail <= 3; fail++) {
        allocation = 0;
        failAllocation = fail;
        assert(Mp3DecCreate(&decoderH) == MP3DEC_NO_MEMORY && !decoderH);
        for (h = 1; h < 16; h++) assert(!blocks[h].dataP);
    }
    failAllocation = 0;
    assert(Mp3DecCreate(&decoderH) == MP3DEC_PCM);
    assert(Mp3DecGetFormat(decoderH, &format) == MP3DEC_NEED_INPUT);
    memset(junk, 0, sizeof(junk));
    assert(Mp3DecFeed(decoderH, junk, sizeof(junk), MP3DEC_FEED_END,
                      &accepted) == MP3DEC_INPUT_FULL && accepted == 2048);
    assert(Mp3DecFeed(decoderH, (void *)0, 0, 0, &accepted) == MP3DEC_PCM);
    assert(Mp3DecReset(decoderH) == MP3DEC_PCM);
    assert(Mp3DecFeed(decoderH, junk, 1, MP3DEC_FEED_END, &accepted) == MP3DEC_PCM);
    assert(Mp3DecReadPCM(decoderH, (void *)0, 0, &frames, &format) == MP3DEC_TRUNCATED);
    assert(Mp3DecReset(decoderH) == MP3DEC_PCM);
    assert(Mp3DecFeed(decoderH, (void *)0, 0, MP3DEC_FEED_END, &accepted) == MP3DEC_PCM);
    assert(Mp3DecReadPCM(decoderH, (void *)0, 0, &frames, &format) == MP3DEC_END);
    Mp3DecDestroy(decoderH);
    Mp3DecDestroy(0);
    OpenStream(&first, argvP[1], argvP[2], (word)atoi(argvP[5]), (word)atoi(argvP[6]));
    OpenStream(&second, argvP[3], argvP[4], 127, 4608);
    while (!first.done || !second.done) {
        Step(&first);
        Step(&second);
    }
    assert(first.pcmBytes && second.pcmBytes);
    /* Reset and decode again on the same handles, comparing the entire PCM. */
    hash = first.hash;
    pcmBytes = first.pcmBytes;
    assert(Mp3DecReset(first.decoderH) == MP3DEC_PCM);
    first.position = first.sentEnd = first.done = 0;
    first.calls = first.pcmBytes = 0;
    first.hash = 2166136261UL;
    first.outputP = freopen(argvP[2], "wb", first.outputP);
    assert(first.outputP);
    while (!first.done) Step(&first);
    assert(first.hash == hash && first.pcmBytes == pcmBytes);
    assert(!fclose(first.outputP) && !fclose(second.outputP));
    Mp3DecDestroy(first.decoderH);
    Mp3DecDestroy(second.decoderH);
    free(first.sourceP);
    free(second.sourceP);
    for (h = 1; h < 16; h++) assert(!blocks[h].dataP);
    puts("streaming, relocation, allocation failure, reset, two instances: PASS");
    return 0;
}

#endif
