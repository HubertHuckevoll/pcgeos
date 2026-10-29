/* Pull-based PCM sources for PC/GEOS Ensemble (bsnwav.lib). */
#ifndef __BSNAUDIO_H
#define __BSNAUDIO_H

#include <geos.h>

#define BSN_PCM_LENGTH_UNKNOWN 0xFFFFFFFFUL
#define BSN_PCM_READ_ERROR     0xFFFF

typedef struct {
    dword sampleRate;
    word channels;
    word bitsPerSample;
    word blockAlign;
    dword avgBytesPerSecond;
} BSNPcmFormat;

/* Far Pascal callback, invoked through ProcCallFixedOrMovable_pascal.
 * Return complete interleaved PCM frames: unsigned 8-bit or signed 16-bit.
 * A positive count must not exceed maxBytes; short reads are normal.
 * Zero means EOF; BSN_PCM_READ_ERROR means failure. Format is constant.
 * File I/O and decoding run synchronously on the calling playback thread.
 */
typedef word _pascal _export BSNPcmReadProc(void *contextP, void *destP,
                                          word maxBytes);

typedef struct {
    BSNPcmFormat format;
    dword pcmBytes;              /* Expected length, or LENGTH_UNKNOWN. */
    BSNPcmReadProc *readP;       /* GEOS virtual far code pointer. */
    void *contextP;
} BSNPcmSource;

/* Blocking; flags, parent and results use the legacy BSNWavePlayPCM rules.
 * The descriptor and context are borrowed and must remain valid/locked
 * throughout playback. Store handles in decoder contexts; never retain a
 * pointer into an unlocked movable block. No file handle is transferred.
 * Independent readers may be used without playback or sound hardware.
 */
extern int _pascal _export BSNPcmPlay(BSNPcmSource *sourceP,
                                     word flags, optr parent);
#endif
