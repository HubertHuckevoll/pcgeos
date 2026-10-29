/* MP3Dec public API for PC/GEOS Ensemble. */
#ifndef __MP3DEC_H
#define __MP3DEC_H

#include <geos.h>

typedef MemHandle Mp3DecHandle;
typedef word Mp3DecResult;
#define MP3DEC_PCM             0
#define MP3DEC_NEED_INPUT      1
#define MP3DEC_OUTPUT_SMALL    2
#define MP3DEC_FORMAT_CHANGED  3
#define MP3DEC_END             4
#define MP3DEC_RECOVERABLE     5
#define MP3DEC_FATAL           6
#define MP3DEC_BAD_ARGUMENT    7
#define MP3DEC_NO_MEMORY       8
#define MP3DEC_INPUT_FULL      9
#define MP3DEC_TRUNCATED      10
#define MP3DEC_FEED_END         1
#define MP3DEC_MAX_PCM_BYTES 4608

typedef struct {
    dword sampleRate;
    word channels;
} Mp3DecFormat;

/* One instance per stream. Calls on one instance must be serialized.
 * Each instance owns three movable blocks; destroy releases them all.
 * No caller pointer is retained. All caller buffers must remain locked for
 * the duration of a call and fit entirely within one 64 KB segment.
 */
extern Mp3DecResult _pascal _export Mp3DecCreate(Mp3DecHandle *decoderHP);

/* acceptedP always reports exactly how many bytes were copied. INPUT_FULL
 * requires draining PCM and retrying the unaccepted suffix. END is latched
 * only when all supplied bytes have been accepted. After END, use Reset
 * before feeding another stream. dataP may be null only when size is zero.
 * MP3DEC_PCM here means successful input acceptance, not available audio.
 */
extern Mp3DecResult _pascal _export
Mp3DecFeed(Mp3DecHandle decoderH, const byte *dataP, word size,
           word flags, word *acceptedP);

/* Decode at most one MPEG frame per call, or drain pending PCM. byteCapacity
 * may be smaller than a whole MPEG frame; complete PCM frames are returned.
 * A PCM frame is one signed 16-bit sample per channel, interleaved L,R.
 * framesP counts PCM frames, never samples or bytes. formatP describes them.
 * FORMAT_CHANGED returns no PCM; the next call drains retained new-format
 * PCM. RECOVERABLE can return PCM (upstream concealment); inspect framesP.
 * OUTPUT_SMALL retains all PCM and needs at least channels*2 bytes.
 * NEED_INPUT and FORMAT_CHANGED may consume compressed bytes; no PCM is lost.
 * TRUNCATED is terminal until Reset. Free-format and Layers I/II are rejected
 * as recoverable sync errors. No gapless delay/padding trimming is performed.
 */
extern Mp3DecResult _pascal _export
Mp3DecReadPCM(Mp3DecHandle decoderH, sword *pcmP, word byteCapacity,
              word *framesP, Mp3DecFormat *formatP);
extern Mp3DecResult _pascal _export
Mp3DecGetFormat(Mp3DecHandle decoderH, Mp3DecFormat *formatP);
extern Mp3DecResult _pascal _export Mp3DecReset(Mp3DecHandle decoderH);
/* Destroy accepts NullHandle. Other calls require a live handle from Create. */
extern void _pascal _export Mp3DecDestroy(Mp3DecHandle decoderH);
#endif
