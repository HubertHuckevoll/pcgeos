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

void LogInit(void);     // Clear log and start fresh
void LogStart(void);    // Add timestamped session header
void LogEnd(void);      // Add session footer
void Log(const char *fmt, ...);  // Formatted log entry

void LogStrSegment(const char *str, DbgStrMode mode, word startOrLen, word end);
void LogStrHead(const char *str, word len);
void LogStrTail(const char *str, word len);
void LogStrRange(const char *str, word from, word to);
void LogStrAll(const char *str);

void LogByte(const char *label, byte val);
void LogSByte(const char *label, sbyte val);
void LogWord(const char *label, word val);
void LogSWord(const char *label, sword val);
void LogDWord(const char *label, dword val);
void LogSDWord(const char *label, sdword val);
void LogBoolean(const char *label, Boolean val);
void LogPtr(const char *label, void *ptr);
void LogChunkHandle(const char *label, ChunkHandle ch);
void LogMemHandle(const char *label, MemHandle mh);
void LogFileHandle(const char *label, FileHandle fh);
void LogOptr(const char *label, optr o);

#endif // __DBGLOG_H__
