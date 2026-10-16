/*
 * Private buffer API for progressive image download/import.
 *
 * URLTextImageProgress.goc owns one stream handle per fetch child and controls
 * producer/consumer synchronization. MemStream.c allocates the header and data
 * blocks; Init creates or resets a stream, Write appends, Read copies without
 * consuming, and Delete advances the head and frees consumed blocks.
 */
#ifndef _MEMSTREAM_H_
#define _MEMSTREAM_H_

#include <geos.h>

/* Select memory buffering instead of the VM HugeArray stream. */
#define USE_MEM_STREAM

MemHandle MemStreamInit(MemHandle stream);
void MemStreamDelete(MemHandle stream, word bufSize, Boolean emptyLast);
word MemStreamRead(MemHandle stream, void *buffer, word bufSize, word offset);
void MemStreamWrite(MemHandle stream, void *buffer, word bufSize);

#endif
