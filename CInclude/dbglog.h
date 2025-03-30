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

void _export LogInit(void);     // Clear log and start fresh
void _export LogStart(void);    // Add timestamped session header
void _export LogEnd(void);      // Add session footer
void _export Log(const char *fmt, ...);  // Formatted log entry

void _export LogStrHead(const char *str, word len);
void _export LogStrTail(const char *str, word len);
void _export LogStrRange(const char *str, word from, word to);
void _export LogStrAll(const char *str);

void _export LogByte(const char *label, byte val);
void _export LogSByte(const char *label, sbyte val);
void _export LogWord(const char *label, word val);
void _export LogSWord(const char *label, sword val);
void _export LogDWord(const char *label, dword val);
void _export LogSDWord(const char *label, sdword val);
void _export LogBoolean(const char *label, Boolean val);
void _export LogPtr(const char *label, void *ptr);
void _export LogChunkHandle(const char *label, ChunkHandle ch);
void _export LogMemHandle(const char *label, MemHandle mh);
void _export LogFileHandle(const char *label, FileHandle fh);
void _export LogOptr(const char *label, optr o);

#endif // __DBGLOG_H__
