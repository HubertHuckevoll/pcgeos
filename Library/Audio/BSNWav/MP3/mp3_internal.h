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

#define MP3_DUMP_PCM

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
#ifdef MINIMP3_FLOAT_OUTPUT
    float                  frameFloatBuf[MP3_FRAME_SAMPLES_MAX];
#endif

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

#ifdef MINIMP3_GEOS_PORT
void        MP3_TraceWrite(const char *text);
void        MP3_TraceWriteHex(const char *label,
                              const byte _far *data,
                              word count);
void        MP3_TraceWriteFloatHex(const char *label,
                                   const float _far *data,
                                   word count);
void        MP3_TraceWriteSamples(const char *label,
                                  const sword _far *data,
                                  word count);
extern word    s_mp3DumpFrames;
extern word    s_mp3ClampLogs;
extern word    s_mp3ScaleLogs;
extern word    s_mp3SynthLogs;
#endif

#endif /* MP3_INTERNAL_H */
