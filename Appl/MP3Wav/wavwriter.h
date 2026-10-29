#ifndef WAVWRITER_H
#define WAVWRITER_H
#include <geos.h>
#include <file.h>
#include <bsnaudio.h>

typedef struct {
    FileHandle fileH;
    BSNPcmFormat format;
    dword bytes;
} WavWriter;
/* Caller opens a new, empty file, and closes/deletes it on any error.
 * Return zero on success. PCM has the same representation as MP3Dec output.
 */
word _pascal WavWriterBegin(WavWriter *writerP, FileHandle fileH,
                            const BSNPcmFormat *formatP);
word _pascal WavWriterAppend(WavWriter *writerP, const sword *pcmP,
                             word frames, const BSNPcmFormat *formatP);
word _pascal WavWriterFinish(WavWriter *writerP);
#endif
