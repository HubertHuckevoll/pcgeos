#include "wavwriter.h"
#include <Ansi/string.h>

static void _pascal
WavPut32(byte *destP, dword value)
{
    destP[0] = (byte)value;
    destP[1] = (byte)(value >> 8);
    destP[2] = (byte)(value >> 16);
    destP[3] = (byte)(value >> 24);
}

static word _pascal
WavHeader(WavWriter *writerP)
{
    byte header[44];
    word align;

    align = writerP->format.channels * 2;
    memset(header, 0, sizeof(header));
    memcpy(header, "RIFF", 4);
    WavPut32(header + 4, writerP->bytes + 36);
    memcpy(header + 8, "WAVEfmt ", 8);
    WavPut32(header + 16, 16);
    header[20] = 1;
    header[22] = (byte)writerP->format.channels;
    WavPut32(header + 24, writerP->format.sampleRate);
    WavPut32(header + 28, writerP->format.sampleRate * align);
    header[32] = (byte)align;
    header[34] = 16;
    memcpy(header + 36, "data", 4);
    WavPut32(header + 40, writerP->bytes);
    return FileWrite(writerP->fileH, header, sizeof(header), FALSE) != sizeof(header);
}

word _pascal
WavWriterBegin(WavWriter *writerP, FileHandle fileH,
                const BSNPcmFormat *formatP)
{
    if (formatP->channels < 1 || formatP->channels > 2 ||
        !formatP->sampleRate || formatP->sampleRate > 48000UL ||
        formatP->bitsPerSample != 16 ||
        formatP->blockAlign != formatP->channels * 2 ||
        formatP->avgBytesPerSecond != formatP->sampleRate * formatP->blockAlign)
        return 1;
    writerP->fileH = fileH;
    writerP->format = *formatP;
    writerP->bytes = 0;
    return WavHeader(writerP);
}

word _pascal
WavWriterAppend(WavWriter *writerP, const sword *pcmP,
                 word frames, const BSNPcmFormat *formatP)
{
    word bytes;
    word align;

    align = writerP->format.channels * 2;
    if (writerP->format.channels != formatP->channels ||
        writerP->format.sampleRate != formatP->sampleRate ||
        frames > 65535U / align) return 1;
    bytes = frames * align;
    if (writerP->bytes > 0xffffffffUL - 36 - bytes) return 1;
    /* GEOS and the public PCM buffers are little endian, signed 16-bit. */
    if (FileWrite(writerP->fileH, pcmP, bytes, FALSE) != bytes) return 1;
    writerP->bytes += bytes;
    return 0;
}

word _pascal
WavWriterFinish(WavWriter *writerP)
{
    if (FilePos(writerP->fileH, 0, FILE_POS_START) != 0) return 1;
    return WavHeader(writerP);
}
