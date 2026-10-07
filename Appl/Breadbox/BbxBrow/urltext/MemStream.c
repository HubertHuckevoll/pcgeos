/*
 * Private byte-buffer implementation for URLText image loading progress.
 *
 * The caller retains stream handles and synchronization. Preserve the
 * existing block layout, allocation behavior and absolute tail ceiling.
 */

#include <product.h>
#include "MemStream.h"
#include <heap.h>
#include <ec.h>
#include <Ansi/string.h>

/* Keep the implementation in the original browser code resource. */
#ifdef __BORLANDC__
#pragma codeseg URLTEXT_TEXT
#pragma option -dc-
#endif
#ifdef __WATCOMC__
#pragma code_seg("URLTEXT_TEXT")
#endif

#if PROGRESS_DISPLAY && defined(USE_MEM_STREAM)

#define MEM_STREAM_BLOCK_SIZE 8192
#define MEM_STREAM_INIT_BLKS 200  /* supports up to 1.6M files w/o growth */

typedef struct {
    dword head;
    dword tail;
    word maxBlk;
    /* followed by block pointers */
} MemStreamHeader;

/* Initialize or clear the existing per-fetch-child memory stream. */
MemHandle MemStreamInit(MemHandle stream)
{
    MemStreamHeader *streamP;
    MemHandle *blkP;
    MemHandle ret = stream;
    int i;

    if (stream) {
        streamP = MemPLock(stream);
        (byte *)blkP = (byte *)streamP + sizeof(MemStreamHeader);
        for (i = 0; i < streamP->maxBlk; i++) {
            if (!blkP[i]) break;
            MemFree(blkP[i]);
            blkP[i] = 0;
        }
        streamP->head = streamP->tail = 0;
        MemUnlockV(stream);
    } else {
        ret = MemAlloc(sizeof(MemStreamHeader)+(MEM_STREAM_INIT_BLKS*sizeof(MemHandle)),
            HF_DYNAMIC, HAF_STANDARD|HAF_ZERO_INIT);
        if (ret) {
            streamP = MemLock(ret);
            streamP->maxBlk = MEM_STREAM_INIT_BLKS;
            MemUnlock(ret);
        }
    }
    return ret;
}

/* Advance the stream head and release blocks already consumed. */
void MemStreamDelete(MemHandle stream, word bufSize, Boolean emptyLast)
{
    MemStreamHeader *streamP;
    MemHandle *blkP;
    int i, last;

    streamP = MemPLock(stream);
    /* advance head offset */
    streamP->head += bufSize;
    EC_ERROR_IF((streamP->head > streamP->tail), -1);
    /* compute last one */
    last = streamP->head/MEM_STREAM_BLOCK_SIZE;
    if (emptyLast && (streamP->head == streamP->tail)) last++;
    /* free blocks before head */
    (byte *)blkP = (byte *)streamP + sizeof(MemStreamHeader);
    for (i = 0; i < last; i++) {
        if (blkP[i]) {
            MemFree(blkP[i]);
            blkP[i] = 0;
        }
    }
    MemUnlockV(stream);
}

/* Copy available stream bytes without changing stream ownership. */
word MemStreamRead(MemHandle stream, void *buffer, word bufSize, word offset)
{
    MemStreamHeader *streamP;
    MemHandle *blkP;
    byte *dataP;
    word blockOffset, dataOffset;
    word bytesInFirstBlock, bytesInNextBlock;
    word ret = 0;

    streamP = MemPLock(stream);
    if (bufSize > (streamP->tail - streamP->head)) {
        bufSize = streamP->tail - streamP->head;
    }
    if (bufSize) {  /* handles no more data because of write overflow */
        (byte *)blkP = (byte *)streamP + sizeof(MemStreamHeader);
        /* copy from start block */
        blockOffset = streamP->head/MEM_STREAM_BLOCK_SIZE;
        if (blkP[blockOffset]) {
            dataP = MemLock(blkP[blockOffset]);
            dataOffset = streamP->head % MEM_STREAM_BLOCK_SIZE;
            dataP += dataOffset;
            bytesInFirstBlock = MEM_STREAM_BLOCK_SIZE-dataOffset;
            if (bufSize > bytesInFirstBlock) {
                bytesInNextBlock = bufSize - bytesInFirstBlock;
            } else {
                bytesInFirstBlock = bufSize;
                bytesInNextBlock = 0;
            }
            memcpy(buffer, dataP + offset, bytesInFirstBlock);
            ret += bytesInFirstBlock;
            MemUnlock(blkP[blockOffset]);
            /* copy from next block, if needed */
            if (bytesInNextBlock && blkP[blockOffset+1]) {
                dataP = MemLock(blkP[blockOffset+1]);
                memcpy((byte *)buffer+bytesInFirstBlock, dataP, bytesInNextBlock);
                ret += bytesInNextBlock;
                MemUnlock(blkP[blockOffset+1]);
            }
        }
    }
    MemUnlockV(stream);
    return ret;
}

/* Append within the existing fixed stream block limit. */
void MemStreamWrite(MemHandle stream, void *buffer, word bufSize)
{
    MemStreamHeader *streamP;
    MemHandle *blkP;
    byte *dataP;
    word blockOffset, dataOffset;
    word bytesInFirstBlock, bytesInNextBlock;

    streamP = MemPLock(stream);
    if ((streamP->tail + (dword)bufSize) < (dword)MEM_STREAM_BLOCK_SIZE*(dword)MEM_STREAM_INIT_BLKS) {
        (byte *)blkP = (byte *)streamP + sizeof(MemStreamHeader);
        /* copy to start block */
        blockOffset = streamP->tail/MEM_STREAM_BLOCK_SIZE;
        if (!blkP[blockOffset]) {
            blkP[blockOffset] = MemAlloc(MEM_STREAM_BLOCK_SIZE, HF_DYNAMIC, HAF_STANDARD);
        }
        if (blkP[blockOffset]) {
            dataP = MemLock(blkP[blockOffset]);
            dataOffset = streamP->tail % MEM_STREAM_BLOCK_SIZE;
            dataP += dataOffset;
            bytesInFirstBlock = MEM_STREAM_BLOCK_SIZE-dataOffset;
            if (bufSize > bytesInFirstBlock) {
                bytesInNextBlock = bufSize - bytesInFirstBlock;
            } else {
                bytesInFirstBlock = bufSize;
                bytesInNextBlock = 0;
            }
            memcpy(dataP, buffer, bytesInFirstBlock);
            MemUnlock(blkP[blockOffset]);
            /* copy to next block, if needed */
            if (bytesInNextBlock) {
                if (!blkP[blockOffset+1]) {
                    blkP[blockOffset+1] = MemAlloc(MEM_STREAM_BLOCK_SIZE, HF_DYNAMIC, HAF_STANDARD);
                }
                if (blkP[blockOffset+1]) {
                    dataP = MemLock(blkP[blockOffset+1]);
                    memcpy(dataP, (byte *)buffer+bytesInFirstBlock, bytesInNextBlock);
                    MemUnlock(blkP[blockOffset+1]);
                }
            }
        }
        streamP->tail += bufSize;
    }
    MemUnlockV(stream);
}


#endif
