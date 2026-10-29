/* Host integration: real public decoder API plus the real WAV writer. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../wavwriter.h"

static FILE *outputP;
word FileWrite(FileHandle fileH, const void *dataP, word size, word flags)
{
    (void)fileH;
    (void)flags;
    return (word)fwrite(dataP, 1, size, outputP);
}
dword FilePos(FileHandle fileH, dword offset, word mode)
{
    (void)fileH;
    (void)mode;
    return fseek(outputP, offset, SEEK_SET) ? 0xffffffffUL : (dword)ftell(outputP);
}
int main(int argc, char **argvP)
{
    static sword pcm[2304];
    byte input[512];
    FILE *sourceP;
    Mp3DecHandle decoderH;
    Mp3DecFormat format;
    Mp3DecResult result;
    WavWriter writer;
    word count, accepted, frames, ended;

    assert(argc == 3);
    sourceP = fopen(argvP[1], "rb");
    outputP = fopen(argvP[2], "wb");
    assert(sourceP && outputP);
    memset(&writer, 0, sizeof(writer));
    ended = 0;
    assert(Mp3DecCreate(&decoderH) == MP3DEC_PCM);
    for (;;) {
        result = Mp3DecReadPCM(decoderH, pcm, sizeof(pcm), &frames, &format);
        if (result == MP3DEC_NEED_INPUT && !ended) {
            count = (word)fread(input, 1, sizeof(input), sourceP);
            assert(!ferror(sourceP));
            ended = count < sizeof(input);
            assert(Mp3DecFeed(decoderH, input, count,
                              ended ? MP3DEC_FEED_END : 0, &accepted) == MP3DEC_PCM);
            assert(accepted == count);
        } else if (result == MP3DEC_PCM && frames) {
            if (!writer.fileH) assert(!WavWriterBegin(&writer, 1, &format));
            assert(!WavWriterAppend(&writer, pcm, frames, &format));
        } else if (result == MP3DEC_END) {
            assert(writer.bytes && !WavWriterFinish(&writer));
            break;
        } else {
            fprintf(stderr, "decoder status %u\n", result);
            fclose(outputP);
            remove(argvP[2]);
            return 1;
        }
    }
    Mp3DecDestroy(decoderH);
    assert(!fclose(sourceP) && !fclose(outputP));
    return 0;
}
