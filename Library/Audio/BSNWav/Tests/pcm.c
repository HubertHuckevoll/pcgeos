/* Host regression for actual cache, conversion and playback-loop code. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <bsnaudio.h>
#define BSNW_PCM_READ_ERROR BSN_PCM_READ_ERROR
#define BSNW_STATUS_OK 0
#define BSNW_ABORT 1
#define BSNW_SOURCE_ERROR 8
#define BSNW_PLAY_FINISHED 255
#define BSCPT_REST_TIME 1
static word playCacheLen, cacheFree, cacheFull, cacheOffset, cacheKOffset;
static word secondKOffset, secondFree, secBufLen, secBufL2, playLen2;
static word peakLevel, peakLevel2, secondHandle, playCacheHandle;
static word pcmBlockAlign, statusGlyphOptr2, simFlags, playStatus;
static byte konvChanRed, konvBitsRed, konvRateRed, playBits;
static Boolean pcmUnknownLength, playStopFlag;
static dword bytesToPlay, fullLen, playedBytes, timeOutCounter;
static byte cache[32], dma[8], played[2048];
static byte *playCachePtr = cache, *secondPtr = dma;
static char playStatusText[80];
static BSNPcmSource *playSourceP;
static word ticks, started, stopped, playedCount;

static word ProcCallFixedOrMovable_pascal(void *contextP, void *destP,
                                         word capacity, BSNPcmReadProc *readP)
{
    return readP(contextP, destP, capacity);
}
static void BSNWKonvert16To8(void *cacheP, void *secondP)
{
    (void)cacheP; (void)secondP;
    assert(0); /* This check selects the byte-copy conversion path. */
}
static void BSNWAsmStartPlay(void) { started++; }
static word BSNWaveGetAIState(word options)
{
    word half;
    if (options) { ticks = 0; return 0; }
    assert(ticks < 200);
    half = (ticks & 1) ? secBufL2 : 0;
    assert(playedCount + secBufL2 <= sizeof(played));
    memcpy(played + playedCount, dma + half, secBufL2);
    playedCount += secBufL2;
    ticks++;
    return (word)(ticks | ((ticks & 1) ? 0x100 : 0));
}
static void TimerSleep(word ticksToSleep) { (void)ticksToSleep; }
static void BSNWaveStopRecOrPlay(void *bufferP)
{
    (void)bufferP; stopped++;
}
static void MemUnlock(word h) { (void)h; }
static void MemFree(word h) { (void)h; }
static dword BSNWaveCalcPlaytimeText(char *textP, dword current, dword full,
                                    dword rate, word mode)
{
    (void)textP; (void)current; (void)full; (void)rate; (void)mode;
    return 0;
}
#include "pcm.inc"

typedef struct {
    word length, offset, chunk, failAt, invalid;
} Input;
static word ReadPCM(void *contextP, void *destP, word capacity)
{
    Input *inputP = contextP;
    word count, i;
    if (inputP->invalid) return inputP->invalid == 1 ? capacity+1 : 1;
    if (inputP->offset >= inputP->failAt) return BSN_PCM_READ_ERROR;
    count = inputP->length - inputP->offset;
    if (count > capacity) count = capacity;
    if (count > inputP->chunk) count = inputP->chunk;
    for (i=0; i<count; i++) ((byte *)destP)[i] = (byte)(inputP->offset+i);
    inputP->offset += count;
    return count;
}
static void Reset(BSNPcmSource *sourceP)
{
    playSourceP = sourceP;
    bytesToPlay = sourceP->pcmBytes;
    pcmUnknownLength = bytesToPlay == BSN_PCM_LENGTH_UNKNOWN;
    fullLen = pcmUnknownLength ? 0 : bytesToPlay;
    pcmBlockAlign = sourceP->format.blockAlign;
    playCacheLen = 32;
    cacheFree = playCacheLen;
    cacheFull = cacheOffset = cacheKOffset = 0;
    secBufLen = sizeof(dma);
    secBufL2 = secBufLen/2;
    secondFree = secBufLen;
    secondKOffset = 0;
    konvChanRed = konvRateRed = konvBitsRed = 1;
    playLen2 = secBufL2;
    playBits = 8;
    playedBytes = ticks = started = stopped = playedCount = 0;
    playStopFlag = FALSE;
    memset(dma, 0xcc, sizeof(dma));
}
int main(void)
{
    BSNPcmSource source;
    Input input;
    word length, chunk, unknown, i;
    source.format.avgBytesPerSecond = 8000;
    source.format.blockAlign = 1;
    source.readP = ReadPCM;
    source.contextP = &input;
    for (length=0; length<100; length++) {
        for (chunk=1; chunk<=13; chunk++) {
            for (unknown=0; unknown<2; unknown++) {
                input.length = length; input.offset = 0; input.chunk = chunk;
                input.failAt = 0xffff; input.invalid = 0;
                source.pcmBytes = unknown ? BSN_PCM_LENGTH_UNKNOWN : length+7;
                Reset(&source);
                assert(BSNWPlay(&source.format, 0, 0) == BSNW_STATUS_OK);
                assert(input.offset == length && fullLen == length);
                assert(playedBytes >= length && stopped == 1);
                for (i=0; i<length; i++) assert(played[i] == (byte)i);
            }
        }
    }
    /* Decoder chunk sizes must not change integer rate reduction. */
    for (length=1; length<100; length++) {
        for (chunk=1; chunk<=13; chunk++) {
            input.length = length; input.offset = 0; input.chunk = chunk;
            input.failAt = 0xffff; input.invalid = 0;
            source.pcmBytes = BSN_PCM_LENGTH_UNKNOWN;
            Reset(&source);
            playCacheLen = cacheFree = 30;
            konvRateRed = 3; playLen2 = secBufL2 * 3;
            assert(BSNWPlay(&source.format, 0, 0) == BSNW_STATUS_OK);
            for (i=0; i<(length+2)/3; i++) assert(played[i] == (byte)(i*3));
        }
    }
    /* Error after playback starts must not turn into successful EOF. */
    input.length = 100; input.offset = 0; input.chunk = 8;
    input.failAt = 32; input.invalid = 0;
    source.pcmBytes = BSN_PCM_LENGTH_UNKNOWN;
    Reset(&source);
    assert(BSNWPlay(&source.format, 0, 0) == BSNW_SOURCE_ERROR);
    assert(started == 1 && stopped == 1);
    input.offset = 0; input.invalid = 1;
    Reset(&source);
    assert(BSNWLoadCache(cache) == BSNW_SOURCE_ERROR);
    input.invalid = 2;
    source.format.blockAlign = 4;
    Reset(&source);
    assert(BSNWLoadCache(cache) == BSNW_SOURCE_ERROR);
    puts("PCM partial reads, known/unknown length, early EOF, drain, errors: PASS");
    return 0;
}
