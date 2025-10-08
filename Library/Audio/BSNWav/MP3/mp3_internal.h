/*
 * mp3_internal.h — shared context + helpers for MP3 playback glue
 */
#ifndef MP3_INTERNAL_H
#define MP3_INTERNAL_H

#include <geos.h>
#include <file.h>
#include <sound.h>
#include "minimp3_conf.h"

typedef struct {
    FileHandle              fh;
    Handle                  inBufH;
    byte                   *inBufP;
    word                    inFill;
    word                    inPos;
    Boolean                 eofSeen;

    Handle                  frameH;
    sword                  *frameP;
    word                    frameBytes;
    word                    frameOff;

    word                    outRate;
    word                    outCh;

    WWFixed                 volume;
    Boolean                 forceMono;

    mp3dec_t                dec;
    mp3dec_frame_info_t     fi;
} MP3Ctx;

Boolean _pascal MP3_InitContextAndPrime(MP3Ctx *ctxP,
                                        const char *pathP,
                                        WWFixed volume,
                                        Boolean forceMono);
void    _pascal MP3_CleanupContext(MP3Ctx *ctxP);
void    _pascal MP3_SetActiveCtxInternal(MP3Ctx *ctxP);
Boolean _pascal MP3_BSNWavFill(void *dstBuf, word wantBytes);

#endif /* MP3_INTERNAL_H */
