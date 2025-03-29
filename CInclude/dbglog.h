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

//--------------------------------------------------------------------------
// Convenience macros for common string segment modes

#define dbgLogStrHead(str, len)   dbgLogStrSegment(str, DBG_STR_HEAD, len, 0)
#define dbgLogStrTail(str, len)   dbgLogStrSegment(str, DBG_STR_TAIL, len, 0)
#define dbgLogStrRange(str,f,t)   dbgLogStrSegment(str, DBG_STR_RANGE, f, t)
#define dbgLogStrAll(str)         dbgLogStrSegment(str, DBG_STR_ALL, 0, 0)

#endif // __DBGLOG_H__
