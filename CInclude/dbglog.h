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

void _pascal _export LogInit(void);     // Clear log and start fresh
void _pascal _export LogStart(void);    // Add timestamped session header
void _pascal _export Log(const char *fmt, ...);  // Formatted log entry
void _pascal _export LogEnd(void);      // Add session footer
void _pascal _export LogStrHead(const char *label, const char *str, word len);
void _pascal _export LogStrTail(const char *label, const char *str, word len);
void _pascal _export LogStrRange(const char *label, const char *str, word from, word to);
void _pascal _export LogStrAll(const char *label, const char *str);
void _pascal _export LogByte(const char *label, byte val);
void _pascal _export LogSByte(const char *label, sbyte val);
void _pascal _export LogWord(const char *label, word val);
void _pascal _export LogSWord(const char *label, sword val);
void _pascal _export LogDWord(const char *label, dword val);
void _pascal _export LogSDWord(const char *label, sdword val);
void _pascal _export LogBoolean(const char *label, Boolean val);
void _pascal _export LogPtr(const char *label, void *ptr);
void _pascal _export LogChunkHandle(const char *label, ChunkHandle ch);
void _pascal _export LogMemHandle(const char *label, MemHandle mh);
void _pascal _export LogFileHandle(const char *label, FileHandle fh);
void _pascal _export LogOptr(const char *label, optr o);

#endif // __DBGLOG_H__
