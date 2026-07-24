/*
 * Static lossy WebP decoder for PC/GEOS Ensemble.
 * Lossy VP8 behavior is derived from SimpleWebP commit
 * d1a728a1f8ec7348ca2a5039b6dd813b83986fbb; see LICENSE.md and PATENTS.md.
 */

#ifdef WEBP_HOST_TEST
#include "tests/webptest.h"
#else
#include "webpint.h"
#endif

static void
WebPFreeDecoderBuffers(WebPDecoder *decoderP)
{
    if (decoderP->rgbH != NullHandle) {
        MemFree(decoderP->rgbH);
    }
    if (decoderP->chromaH != NullHandle) {
        MemFree(decoderP->chromaH);
    }
    if (decoderP->lumaH != NullHandle) {
        MemFree(decoderP->lumaH);
    }
    if (decoderP->contextH != NullHandle) {
        MemFree(decoderP->contextH);
    }
    if (decoderP->inputH != NullHandle) {
        MemFree(decoderP->inputH);
    }
}

WebPResult _pascal _export
WebPImportBegin(FileHandle source, VMFileHandle destination,
                WebPImportHandle *decoder, VMBlockHandle *bitmap,
                WebPImageInfo *info)
{
    WebPImportHandle decoderH;
    WebPDecoder *decoderP;
    WebPResult result;

    if (decoder == (void *)0 || bitmap == (void *)0 || info == (void *)0) {
        return WEBP_ERROR_BAD_STATE;
    }
    *decoder = NullHandle;
    *bitmap = NullHandle;
    info->width = info->height = 0;

    /* HF_FIXED blocks are already locked and cannot use this API pattern. */
    decoderH = MemAlloc(sizeof(WebPDecoder), HF_SWAPABLE, HAF_ZERO_INIT);
    if (decoderH == NullHandle) {
        return WEBP_ERROR_OUT_OF_MEMORY;
    }
    decoderP = MemLock(decoderH);
    decoderP->source = source;
    decoderP->destination = destination;

    result = WebPParseContainer(source, decoderP);
    if (result == WEBP_RESULT_OK) {
        result = WebPDecodeInit(decoderP);
    }
    if (result == WEBP_RESULT_OK) {
        decoderP->bitmap = GrCreateBitmapRaw(BMF_24BIT | BMT_COMPLEX,
                                             decoderP->width,
                                             decoderP->height,
                                             destination);
        if (decoderP->bitmap == NullHandle) {
            result = WEBP_ERROR_OUT_OF_MEMORY;
        }
    }
    if (result != WEBP_RESULT_OK) {
        WebPDecodeCleanup(decoderP);
        WebPFreeDecoderBuffers(decoderP);
        MemUnlock(decoderH);
        MemFree(decoderH);
        return result;
    }

    *bitmap = decoderP->bitmap;
    info->width = decoderP->width;
    info->height = decoderP->height;
    MemUnlock(decoderH);
    *decoder = decoderH;
    return WEBP_RESULT_OK;
}

WebPResult _pascal _export
WebPImportNext(WebPImportHandle decoder, word *firstLine, word *lineCount)
{
    WebPDecoder *decoderP;
    WebPResult result;

    if (firstLine == (void *)0 || lineCount == (void *)0) {
        return WEBP_ERROR_BAD_STATE;
    }
    *firstLine = 0;
    *lineCount = 0;
    if (decoder == NullHandle) {
        return WEBP_ERROR_BAD_STATE;
    }

    decoderP = MemLock(decoder);
    if (decoderP->terminal) {
        result = WEBP_ERROR_BAD_STATE;
    } else if (decoderP->done) {
        result = WEBP_RESULT_DONE;
    } else {
        result = WebPDecodeRow(decoderP, firstLine, lineCount);
        if (result != WEBP_RESULT_OK && result != WEBP_RESULT_DONE) {
            decoderP->terminal = TRUE;
        }
    }
    MemUnlock(decoder);
    return result;
}

void _pascal _export
WebPImportDestroy(WebPImportHandle decoder)
{
    WebPDecoder *decoderP;

    if (decoder == NullHandle) {
        return;
    }
    decoderP = MemLock(decoder);
    WebPDecodeCleanup(decoderP);
    WebPFreeDecoderBuffers(decoderP);
    MemUnlock(decoder);
    MemFree(decoder);
}
