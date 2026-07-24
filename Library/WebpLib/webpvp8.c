/*
 * VP8 decoder core derived from SimpleWebP commit
 * d1a728a1f8ec7348ca2a5039b6dd813b83986fbb.
 * See LICENSE.md and PATENTS.md.
 */

#ifdef WEBP_HOST_TEST
#include "tests/webptest.h"
#else
#include "webpint.h"
#endif

typedef byte simplewebp_u8;
typedef sbyte simplewebp_i8;
typedef word simplewebp_u16;
typedef sword simplewebp_i16;
typedef dword simplewebp_u32;
typedef sdword simplewebp_i32;
typedef Boolean simplewebp_bool;

typedef enum {
    SIMPLEWEBP_NO_ERROR = 0,
    SIMPLEWEBP_ALLOC_ERROR,
    SIMPLEWEBP_IO_ERROR,
    SIMPLEWEBP_NOT_WEBP_ERROR,
    SIMPLEWEBP_CORRUPT_ERROR,
    SIMPLEWEBP_UNSUPPORTED_ERROR
} simplewebp_error;

static simplewebp_i32
swebp__clip(simplewebp_i32 value, simplewebp_i32 maximum)
{
    if (value < 0) {
        return 0;
    }
    return value > maximum ? maximum : value;
}

#include "webpcore.inc"

typedef struct {
    struct swebp__vp8 vp8;
    struct swebp__mblockdata block;
} WebPCore;

typedef char WebPCoreSizeCheck[
    (sizeof(WebPCore) <= sizeof(((WebPDecoder *)0)->core)) ? 1 : -1
];

static WebPResult
WebPMapCoreError(simplewebp_error error)
{
    switch (error) {
    case SIMPLEWEBP_NO_ERROR:
        return WEBP_RESULT_OK;
    case SIMPLEWEBP_ALLOC_ERROR:
        return WEBP_ERROR_OUT_OF_MEMORY;
    case SIMPLEWEBP_IO_ERROR:
        return WEBP_ERROR_READ;
    case SIMPLEWEBP_UNSUPPORTED_ERROR:
        return WEBP_ERROR_UNSUPPORTED;
    default:
        return WEBP_ERROR_CORRUPT;
    }
}

static void
WebPRebindCore(WebPDecoder *decoderP, WebPCore *coreP,
               byte *contextP, byte *lumaP, byte *chromaP)
{
    word type;
    word band;

    coreP->vp8.br.decoderP = decoderP;
    for (type = 0; type < 4; type++) {
        for (band = 0; band < 17; band++) {
            coreP->vp8.proba.bands_ptr[type][band] =
                &coreP->vp8.proba.bands[type][swebp__bands[band]];
        }
    }
    for (band = 0; band <= coreP->vp8.nparts_minus_1; band++) {
        coreP->vp8.parts[band].decoderP = decoderP;
    }
    coreP->vp8.mb_data = &coreP->block;
    swebp__vp8_bind_buffers(&coreP->vp8, decoderP,
                            contextP, lumaP, chromaP);
}

WebPResult _pascal
WebPDecodeInit(WebPDecoder *decoderP)
{
    WebPCore *coreP;
    struct swebp__vp8 *vp8P;
    byte *contextP;
    byte *lumaP;
    byte *chromaP;
    dword lumaSize;
    dword chromaSize;
    dword contextSize;
    word delay;
    simplewebp_error error;

    coreP = (WebPCore *)decoderP->core;
    vp8P = &coreP->vp8;
    vp8P->picture_header.width = decoderP->width;
    vp8P->picture_header.height = decoderP->height;
    vp8P->frame_header.partition_length =
        decoderP->firstPartitionLength;

    decoderP->inputH = MemAlloc(WEBP_INPUT_BUFFER_SIZE, HF_SWAPABLE,
                                HAF_ZERO_INIT);
    if (decoderP->inputH == NullHandle) {
        return WEBP_ERROR_OUT_OF_MEMORY;
    }

    error = swebp__load_vp8_header(decoderP, vp8P);
    if (error != SIMPLEWEBP_NO_ERROR) {
        return WebPMapCoreError(error);
    }
    swebp__vp8_enter_critical(vp8P);
    delay = swebp__fextrarows[vp8P->filter_type];
    lumaSize = (dword)decoderP->mbWidth * 16 * (16 + delay);
    chromaSize = (dword)decoderP->mbWidth * 16 * (8 + delay / 2);
    contextSize = (dword)decoderP->mbWidth *
                  (4 + sizeof(struct swebp__topsmp) +
                   sizeof(struct swebp__mblock) +
                   (vp8P->filter_type ?
                    sizeof(struct swebp__finfo) : 0)) +
                  sizeof(struct swebp__mblock) + 834;
    if (lumaSize >= 65536UL || chromaSize >= 65536UL ||
        contextSize >= 65536UL) {
        return WEBP_ERROR_IMAGE_TOO_LARGE;
    }

    decoderP->contextH = MemAlloc((word)contextSize, HF_SWAPABLE,
                                  HAF_ZERO_INIT);
    decoderP->lumaH = MemAlloc((word)lumaSize, HF_SWAPABLE,
                               HAF_ZERO_INIT);
    decoderP->chromaH = MemAlloc((word)chromaSize, HF_SWAPABLE,
                                 HAF_ZERO_INIT);
    decoderP->rgbH = MemAlloc(decoderP->rowBytes, HF_SWAPABLE,
                              HAF_ZERO_INIT);
    if (decoderP->contextH == NullHandle ||
        decoderP->lumaH == NullHandle ||
        decoderP->chromaH == NullHandle ||
        decoderP->rgbH == NullHandle) {
        return WEBP_ERROR_OUT_OF_MEMORY;
    }

    contextP = MemLock(decoderP->contextH);
    lumaP = MemLock(decoderP->lumaH);
    chromaP = MemLock(decoderP->chromaH);
    WebPRebindCore(decoderP, coreP, contextP, lumaP, chromaP);
    memset(vp8P->mb_info - 1, 0,
           sizeof(struct swebp__mblock) * (vp8P->mb_w + 1));
    memset(vp8P->intra_t, 0, 4 * vp8P->mb_w);
    swebp__vp8_init_scanline(vp8P);
    MemUnlock(decoderP->chromaH);
    MemUnlock(decoderP->lumaH);
    MemUnlock(decoderP->contextH);
    return WEBP_RESULT_OK;
}

WebPResult _pascal
WebPDecodeRow(WebPDecoder *decoderP, word *firstLine, word *lineCount)
{
    WebPCore *coreP;
    struct swebp__vp8 *vp8P;
    struct swebp__bdec *tokenP;
    struct swebp__yuvdst output;
    byte *contextP;
    byte *lumaP;
    byte *chromaP;
    byte *rgbP;
    simplewebp_error error;

    if (decoderP->mbY >= decoderP->mbHeight) {
        decoderP->done = TRUE;
        return WEBP_RESULT_DONE;
    }

    coreP = (WebPCore *)decoderP->core;
    vp8P = &coreP->vp8;
    contextP = MemLock(decoderP->contextH);
    lumaP = MemLock(decoderP->lumaH);
    chromaP = MemLock(decoderP->chromaH);
    rgbP = MemLock(decoderP->rgbH);
    WebPRebindCore(decoderP, coreP, contextP, lumaP, chromaP);
    vp8P->mb_y = decoderP->mbY;
    tokenP = &vp8P->parts[vp8P->mb_y & vp8P->nparts_minus_1];
    tokenP->reader.windowSize = 0;
    output.decoderP = decoderP;
    output.rgbP = rgbP;
    output.firstLine = output.lineCount = 0;
    error = SIMPLEWEBP_NO_ERROR;

    for (vp8P->mb_x = 0; vp8P->mb_x < vp8P->mb_w; vp8P->mb_x++) {
        swebp__vp8_parse_intra_mode(vp8P, vp8P->mb_x);
        if (vp8P->br.reader.eof) {
            error = vp8P->br.reader.ioError ?
                SIMPLEWEBP_IO_ERROR : SIMPLEWEBP_CORRUPT_ERROR;
            break;
        }
        if (!swebp__vp8_decode_macroblock(vp8P, tokenP)) {
            error = tokenP->reader.ioError ?
                SIMPLEWEBP_IO_ERROR : SIMPLEWEBP_CORRUPT_ERROR;
            break;
        }
        error = swebp__vp8_process_row(vp8P, &output);
        if (error != SIMPLEWEBP_NO_ERROR) {
            break;
        }
    }
    if (error == SIMPLEWEBP_NO_ERROR) {
        swebp__vp8_init_scanline(vp8P);
        decoderP->mbY++;
        *firstLine = output.firstLine;
        *lineCount = output.lineCount;
    }
    MemUnlock(decoderP->rgbH);
    MemUnlock(decoderP->chromaH);
    MemUnlock(decoderP->lumaH);
    MemUnlock(decoderP->contextH);
    return WebPMapCoreError(error);
}

void _pascal
WebPDecodeCleanup(WebPDecoder *decoderP)
{
    (void)decoderP;
}
