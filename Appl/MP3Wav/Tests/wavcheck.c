/* Compiles the real WAV writer against host file-operation shims. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../wavwriter.h"

static FILE *outputP;
static int failWrite;
static int failSeek;

word FileWrite(FileHandle fileH, const void *dataP, word size, word flags)
{
    (void)fileH;
    (void)flags;
    if (failWrite == 1) return 0xffff;
    if (failWrite == 2) return size - 1;
    return (word)fwrite(dataP, 1, size, outputP);
}
dword FilePos(FileHandle fileH, dword offset, word mode)
{
    (void)fileH;
    (void)mode;
    if (failSeek || fseek(outputP, offset, SEEK_SET)) return 0xffffffffUL;
    return (dword)ftell(outputP);
}

int main(int argc, char **argvP)
{
    static const dword rates[] = {8000,11025,12000,16000,22050,24000,
                                   32000,44100,48000};
    static const sword pcm[] = {-32768, -1, 0, 1, 32767, 42};
    WavWriter writer;
    BSNPcmFormat format, changed;
    byte header[44], samples[12];
    unsigned i, channels;
    unsigned long bytes;

    assert(argc == 2);
    for (channels = 1; channels <= 2; channels++) {
        for (i = 0; i < sizeof(rates)/sizeof(rates[0]); i++) {
            outputP = fopen(argvP[1], "w+b");
            assert(outputP);
            format.channels = channels;
            format.sampleRate = rates[i];
            format.bitsPerSample = 16;
            format.blockAlign = channels * 2;
            format.avgBytesPerSecond = rates[i] * format.blockAlign;
            assert(!WavWriterBegin(&writer, 1, &format));
            assert(!WavWriterAppend(&writer, pcm, 6/channels, &format));
            assert(!WavWriterFinish(&writer));
            assert(!fseek(outputP, 0, SEEK_SET));
            assert(fread(header, 1, 44, outputP) == 44);
            assert(!memcmp(header, "RIFF", 4) && !memcmp(header+8, "WAVEfmt ", 8));
            assert(header[4] == 48 && header[5] == 0);
            assert(header[20] == 1 && header[22] == channels && header[34] == 16);
            assert(header[32] == channels*2 && header[40] == 12);
            bytes = header[28] | ((unsigned long)header[29] << 8) |
                    ((unsigned long)header[30] << 16) | ((unsigned long)header[31] << 24);
            assert(bytes == rates[i]*channels*2);
            assert(fread(samples, 1, 12, outputP) == 12);
            assert(!memcmp(samples, pcm, 12));
            changed = format;
            changed.sampleRate++;
            assert(WavWriterAppend(&writer, pcm, 1, &changed));
            writer.bytes = 0xffffffffUL - 36;
            assert(WavWriterAppend(&writer, pcm, 1, &format));
            failWrite = 1;
            writer.bytes = 0;
            assert(WavWriterAppend(&writer, pcm, 1, &format));
            assert(WavWriterFinish(&writer));
            failWrite = 2;
            assert(WavWriterAppend(&writer, pcm, 1, &format));
            failWrite = 0;
            failSeek = 1;
            assert(WavWriterFinish(&writer));
            failSeek = 0;
            assert(!fclose(outputP));
        }
    }
    puts("WAV PCM, headers, rates, format/size limits, I/O failure: PASS");
    return 0;
}
