#ifndef __DBGLOG_H__
#define __DBGLOG_H__

//--------------------------------------------------------------------------
// Type definitions

typedef enum {
    DBG_STR_ALL,
    DBG_STR_HEAD,
    DBG_STR_TAIL,
    DBG_STR_RANGE
} DbgStrMode;

//--------------------------------------------------------------------------
// API function declarations

void dbgLogInit(void);     // Clear log and start fresh
void dbgLogStart(void);    // Add timestamped session header
void dbgLogEnd(void);      // Add session footer
void dbgLog(const char *fmt, ...);  // Formatted log entry

void dbgLogStrSegment(const char *str, DbgStrMode mode, word startOrLen, word end);
void dbgLogStrHead(const char *str, word len);
void dbgLogStrTail(const char *str, word len);
void dbgLogStrRange(const char *str, word from, word to);
void dbgLogStrAll(const char *str);

void dbgLogByte(const char *label, byte val);
void dbgLogSByte(const char *label, sbyte val);
void dbgLogWord(const char *label, word val);
void dbgLogSWord(const char *label, sword val);
void dbgLogDWord(const char *label, dword val);
void dbgLogSDWord(const char *label, sdword val);
void dbgLogBoolean(const char *label, Boolean val);
void dbgLogPtr(const char *label, void *ptr);
void dbgLogChunkHandle(const char *label, ChunkHandle ch);
void dbgLogMemHandle(const char *label, MemHandle mh);
void dbgLogFileHandle(const char *label, FileHandle fh);
void dbgLogOptr(const char *label, optr o);

#endif // __DBGLOG_H__
