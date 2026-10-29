#ifndef WAVWRITER_H
#define WAVWRITER_H
#include <geos.h>
#include <file.h>
#include <mp3dec.h>

typedef struct {
    FileHandle fileH;
    Mp3DecFormat format;
    dword bytes;
} WavWriter;
/* Caller opens a new, empty file, and closes/deletes it on any error.
 * Return zero on success. PCM has the same representation as MP3Dec output.
 */
word _pascal WavWriterBegin(WavWriter *writerP, FileHandle fileH,
                            const Mp3DecFormat *formatP);
word _pascal WavWriterAppend(WavWriter *writerP, const sword *pcmP,
                             word frames, const Mp3DecFormat *formatP);
word _pascal WavWriterFinish(WavWriter *writerP);
#endif
