/* Test-only GEOS heap model. Unlock relocates blocks to expose stale pointers. */
#ifndef MP3_HOST_H
#define MP3_HOST_H
#include <stdint.h>
#include <string.h>
typedef uint8_t byte;
typedef uint16_t word;
typedef int16_t sword;
typedef uint32_t dword;
typedef word MemHandle;
typedef int Boolean;
typedef dword optr;
#define _pascal
#define _export
#define NullHandle 0
#define HF_SWAPABLE 0
#define HAF_ZERO_INIT 0
MemHandle MemAlloc(word size, word flags, word action);
void *MemLock(MemHandle h);
void MemUnlock(MemHandle h);
void MemFree(MemHandle h);
/* Reuse the real public header after providing the test platform types. */
#define __GEOS_H
#include <mp3dec.h>
#endif
