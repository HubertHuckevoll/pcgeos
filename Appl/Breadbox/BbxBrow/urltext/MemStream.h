/* Private MemStream interface; used by URLTextImageProgress only. */
#ifndef _MEMSTREAM_H_
#define _MEMSTREAM_H_

#include <geos.h>

/* Keep the existing stream-selection switch shared with the implementation. */
#define USE_MEM_STREAM

/* Retain the existing C calling convention and handle ownership. */
MemHandle MemStreamInit(MemHandle stream);
void MemStreamDelete(MemHandle stream, word bufSize, Boolean emptyLast);
word MemStreamRead(MemHandle stream, void *buffer, word bufSize, word offset);
void MemStreamWrite(MemHandle stream, void *buffer, word bufSize);

#endif
