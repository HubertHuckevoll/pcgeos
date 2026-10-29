/* Host regression for actual cache, conversion and playback-loop code. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <bsnaudio.h>
#define BSNW_PCM_READ_ERROR BSN_PCM_READ_ERROR
#define BSNW_STATUS_PLAY_MEM 2
#define NullOptr 0
#define BSNW_TICKS_PER_SECOND 60
#define BSNW_MIN_TICKS_PER_HALF_BUFFER 2
#define HF_SWAPABLE 0
#define HAF_ZERO_INIT 0
#define BSCPT_REST_TIME 1
static word playCacheLen, cacheFree, cacheFull, cacheOffset, cacheKOffset;
static word secondKOffset, secondFree, secBufLen, secBufL2, playLen2, secondOffset;
static word peakLevel, peakLevel2, secondHandle, playCacheHandle;
static word pcmBlockAlign, statusGlyphOptr2, simFlags, playStatus;
static byte konvChanRed, konvBitsRed, konvRateRed, playBits;
static Boolean pcmUnknownLength, playStopFlag;
static dword bytesToPlay, fullLen, playedBytes, timeOutCounter;
static byte cache[32], dma[8], played[2048];
static byte *playCachePtr = cache, *secondPtr = dma;
static char playStatusText[80];
static BSNPcmSource *playSourceP;
static dword ticks, playedCount;
static word started, stopped;
static FILE *playOutputP;
#ifdef BSN_INTEGRATION_TEST
static MemHandle dmaH;
static word failCache, failDMA;
static word secBufLenSoll = 512, playSampleRate;
static byte playChannels, stereoToggle, stereoToggleIni;
static optr statusBox, statusGlyphOptr1, statusRightBoxOptr;
extern MemHandle MemAlloc(word size, word flags, word action);
extern void *MemLock(MemHandle h);
extern void MemUnlock(MemHandle h);
extern void MemFree(MemHandle h);
static int BSNWPreCheck(word flags) { (void)flags; return BSNW_STATUS_OK; }
static void *BSNWAllocPlayCache(word size)
{
    if (failCache) { playCacheHandle = 0; return (void *)0; }
    playCacheHandle = MemAlloc(size, 0, 0);
    return playCacheHandle ? MemLock(playCacheHandle) : (void *)0;
}
static word BSNWAllocSecBuffer(byte **ptrP, word size)
{
    if (failDMA) { *ptrP = (void *)0; return 0; }
    dmaH = MemAlloc(size, 0, 0);
    *ptrP = dmaH ? MemLock(dmaH) : (void *)0;
    return dmaH ? size : 0;
}
static int BSNWPrepKS(word rate, byte channels, byte bits)
{
    playSampleRate = rate; playChannels = channels; playBits = bits;
    konvRateRed = konvBitsRed = konvChanRed = 1;
    return BSNW_STATUS_OK;
}
static optr BSCNCreateStatusBox(optr parent) { (void)parent; return 0; }
void BSNWInsertSample(void *destP, byte bits);
#endif

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
    assert(ticks < 1000000);
    half = (ticks & 1) ? secBufL2 : 0;
    if (playOutputP) {
        assert(fwrite(secondPtr + half, 1, secBufL2, playOutputP) == secBufL2);
    } else {
        assert(playedCount + secBufL2 <= sizeof(played));
        memcpy(played + playedCount, dma + half, secBufL2);
    }
    playedCount += secBufL2;
    ticks++;
    return (word)((ticks & 255) | ((ticks & 1) ? 0x100 : 0));
}
static void TimerSleep(word ticksToSleep) { (void)ticksToSleep; }
static void BSNWaveStopRecOrPlay(void *bufferP)
{
    (void)bufferP; stopped++;
#ifdef BSN_INTEGRATION_TEST
    if (dmaH) { MemUnlock(dmaH); MemFree(dmaH); dmaH = 0; }
#endif
}
#ifndef BSN_INTEGRATION_TEST
static void MemUnlock(word h) { (void)h; }
static void MemFree(word h) { (void)h; }
#endif
static dword BSNWaveCalcPlaytimeText(char *textP, dword current, dword full,
                                    dword rate, word mode)
{
    (void)textP; (void)current; (void)full; (void)rate; (void)mode;
    return 0;
}
#include "pcm.inc"

#ifndef BSN_INTEGRATION_TEST
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
    secondKOffset = secondOffset = 0;
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
                assert(playedBytes == length && stopped == 1);
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
    input.offset = 0; input.failAt = 0xffff;
    Reset(&source);
    fullLen = 0xfffffffeUL;
    assert(BSNWLoadCache(cache) == BSNW_SOURCE_ERROR);
    assert(fullLen == 0xfffffffeUL);
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

#else
static FILE *inputP;
dword FileSize(FileHandle file)
{
    long pos, end;
    (void)file;
    pos = ftell(inputP); assert(!fseek(inputP, 0, SEEK_END));
    end = ftell(inputP); assert(!fseek(inputP, pos, SEEK_SET));
    return (dword)end;
}
dword FilePos(FileHandle file, dword offset, word mode)
{
    (void)file; (void)mode;
    return fseek(inputP, (long)offset, SEEK_SET) ? 0xffffffffUL : offset;
}
word FileRead(FileHandle file, void *destP, word count, word flags)
{
    (void)file; (void)flags;
    return (word)fread(destP, 1, count, inputP);
}
int main(int argc, char **argv)
{
    BSNMP3Dec mp3;
    BSNWav wav;
    BSNPcmSource *sourceP;
    int result;

    assert(argc == 4);
    inputP = fopen(argv[2], "rb"); assert(inputP);
    playOutputP = fopen(argv[3], "wb"); assert(playOutputP);
    if (argv[1][0] == 'm') {
        assert(BSNMP3DecOpen(&mp3, 1) == BSNW_STATUS_OK);
        sourceP = &mp3.source;
    } else {
        assert(BSNWavOpen(&wav, 1) == BSNW_STATUS_OK);
        sourceP = &wav.source;
    }
    playCacheLen = 8192;
    if (sourceP->format.sampleRate < 44200) {
        /* Failed preparation must not insert a stereo-toggle sample at NULL. */
        stereoToggle = 1;
        failCache = 1;
        assert(BSNPcmPlay(sourceP, 0, 0) == BSNW_MEMORY_ERROR);
        failCache = 0; failDMA = 1;
        assert(BSNPcmPlay(sourceP, 0, 0) == BSNW_MEMORY_ERROR);
        failDMA = 0; stereoToggle = strchr(argv[1], '-') != (void *)0;
        assert(!started);
    }
    result = BSNPcmPlay(sourceP, 0, 0);
    if (sourceP->format.sampleRate >= 44200) {
        assert(result == BSNW_UNKNOWN_WAVE_FORMAT && !started);
    } else {
        assert(result == BSNW_STATUS_OK && started && stopped);
        assert(playedBytes >= fullLen && playedBytes-fullLen < playLen2);
        assert(playCacheLen == 8192);
    }
    if (argv[1][0] == 'm') BSNMP3DecClose(&mp3);
    else BSNWavClose(&wav);
    assert(!fseek(inputP, 0, SEEK_SET));
    assert(!fclose(inputP) && !fclose(playOutputP));
    puts("Public decoder -> BSNPcmPlay -> common DMA buffer path: PASS");
    return 0;
}
#endif
