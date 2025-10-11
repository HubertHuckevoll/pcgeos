/*
 * mp3_internal.h — streaming helpers for MP3 playback glue
 */
#ifndef MP3_INTERNAL_H
#define MP3_INTERNAL_H

#include <geos.h>
#include <mem.h>
#include <file.h>
#include <sound.h>

#include "minimp3_port.h"
#include "../fmem_compat.h"

#define MP3_INBUF_SIZE              6144
#define MP3_FRAME_SAMPLES_MAX       (MINIMP3_MAX_SAMPLES_PER_FRAME)
#define MP3_PCM_FRAME_BYTES         (MP3_FRAME_SAMPLES_MAX * 2)

typedef struct _MP3Handle {
    MemHandle              selfHandle;
    FileHandle             fh;

    byte                   inBuf[MP3_INBUF_SIZE];
    word                   inPos;
    word                   inFill;
    Boolean                eofSeen;

    sword                  frameBuf[MP3_PCM_FRAME_BYTES / 2];
    word                   frameBytes;
    word                   frameOff;

    word                   outRate;
    word                   outCh;

    WWFixed                volume;
    Boolean                forceMono;

    mp3dec_t               dec;
    mp3dec_frame_info_t    fi;

    Boolean                primed;
} MP3Handle;

MP3Handle * _pascal MP3_OpenStream(FileHandle fh,
                                   WWFixed volume,
                                   Boolean forceMono);
void        _pascal MP3_CloseStream(MP3Handle *handleP);
Boolean     _pascal MP3_RewindStream(MP3Handle *handleP);
word        _pascal MP3_StreamChannels(const MP3Handle *handleP);
word        _pascal MP3_StreamSampleRate(const MP3Handle *handleP);
word        _pascal MP3_StreamBlockAlign(const MP3Handle *handleP);
dword       _pascal MP3_ReadS16(MP3Handle *handleP,
                                dword framesToRead,
                                sword *dst);

#endif /* MP3_INTERNAL_H */
