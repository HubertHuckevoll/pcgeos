// #ifndef __DBGLOG_H
// #define __DBGLOG_H

/* Call-site UX:
 *   LOG_INIT(); LOG_START();
 *   LOGF(("[PATH]", "Emit done: last=(%d,%d) ...", (int)x, (int)y, ...));
 *   LOGF0(("created %u nodes", (unsigned)n));
 * All compile to nothing when DEBUG_LOG is undefined.
 */

#ifdef DEBUG_LOG

#include <geos.h>
#include <file.h>
#include <timedate.h>
#include <Ansi/stdio.h>
#include <Ansi/string.h>
#include <stdarg.h>
#include <localize.h>

/* Non-varargs API can remain Pascal if you prefer */
void _export _pascal DbgLogInit(void);
void _export _pascal DbgLogStart(void);
void _export _pascal DbgLogEnd(void);

/* Varargs MUST be cdecl on Watcom */
void _export _cdecl  DbgPrintf(const char *fmt, ...);
void _export _cdecl  DbgLogPrintf(const char *label, const char *fmt, ...);

/* Typed helpers (kept for compatibility) */
void _export _pascal DbgLogByte(const char *label, word val);
void _export _pascal DbgLogSByte(const char *label, sword val);
void _export _pascal DbgLogWord(const char *label, word val);
void _export _pascal DbgLogSWord(const char *label, sword val);
void _export _pascal DbgLogDWord(const char *label, dword val);
void _export _pascal DbgLogSDWord(const char *label, sdword val);
void _export _pascal DbgLogBool(const char *label, Boolean val);
void _export _pascal DbgLogPtr(const char *label, const void *ptrP);
void _export _pascal DbgLogChunk(const char *label, word ch);
void _export _pascal DbgLogMem(const char *label, word mh);
void _export _pascal DbgLogFile(const char *label, word fh);
void _export _pascal DbgLogOptr(const char *label, dword o);
void _export _pascal DbgLogStr(const char *label, const char *val);
void _export _pascal DbgLogStrSegment(const char *label, const char *str, word from, word to);
void _export _pascal DbgLogStrHead(const char *label, const char *str, word len);
void _export _pascal DbgLogStrTail(const char *label, const char *str, word len);
void _export _pascal DbgLogStrRange(const char *label, const char *str, word from, word to);
void _export _pascal DbgLogStrAll(const char *label, const char *str);

/* Macros: real calls in debug builds; no evaluation when off */
#define LOG_INIT()                                  DbgLogInit()
#define LOG_START()                                 DbgLogStart()
#define LOG_END()                                   DbgLogEnd()

/* printf-style (double-paren C89 idiom) */
#define LOGF0(args)                                 DbgPrintf args
#define LOGF(args)                                  DbgLogPrintf args

/* Typed convenience (compatible with your existing code) */
#define LOG_BYTE(label, val)                        DbgLogByte((const char*)(label),(word)(val))
#define LOG_SBYTE(label, val)                       DbgLogSByte((const char*)(label),(sword)(val))
#define LOG_WORD(label, val)                        DbgLogWord((const char*)(label),(word)(val))
#define LOG_SWORD(label, val)                       DbgLogSWord((const char*)(label),(sword)(val))
#define LOG_DWORD(label, val)                       DbgLogDWord((const char*)(label),(dword)(val))
#define LOG_SDWORD(label, val)                      DbgLogSDWord((const char*)(label),(sdword)(val))
#define LOG_BOOL(label, val)                        DbgLogBool((const char*)(label),(Boolean)(val))
#define LOG_PTR(label, ptr)                         DbgLogPtr((const char*)(label),(const void*)(ptr))
#define LOG_CHUNK(label, ch)                        DbgLogChunk((const char*)(label),(word)(ch))
#define LOG_MEM(label, mh)                          DbgLogMem((const char*)(label),(word)(mh))
#define LOG_FILE(label, fh)                         DbgLogFile((const char*)(label),(word)(fh))
#define LOG_OPTR(label, o)                          DbgLogOptr((const char*)(label),(dword)(o))
#define LOG_STR(label, val)                         DbgLogStr((const char*)(label),(const char*)(val))
#define LOG_STR_SEGMENT(label, str, from, to)       DbgLogStrSegment((const char*)(label),(const char*)(str),(word)(from),(word)(to))
#define LOG_STR_HEAD(label, str, len)               DbgLogStrHead((const char*)(label),(const char*)(str),(word)(len))
#define LOG_STR_TAIL(label, str, len)               DbgLogStrTail((const char*)(label),(const char*)(str),(word)(len))
#define LOG_STR_RANGE(label, str, from, to)         DbgLogStrRange((const char*)(label),(const char*)(str),(word)(from),(word)(to))
#define LOG_STR_ALL(label, str)                     DbgLogStrAll((const char*)(label),(const char*)(str))

#else   /* !DEBUG_LOG */

/* All stubs compile to nothing; args not evaluated */
#define LOG_INIT()                                  do { } while (0)
#define LOG_START()                                 do { } while (0)
#define LOG_END()                                   do { } while (0)
#define LOGF0(args)                                 ((void)0)
#define LOGF(args)                                  ((void)0)

#define LOG_BYTE(label, val)                        do { } while (0)
#define LOG_SBYTE(label, val)                       do { } while (0)
#define LOG_WORD(label, val)                        do { } while (0)
#define LOG_SWORD(label, val)                       do { } while (0)
#define LOG_DWORD(label, val)                       do { } while (0)
#define LOG_SDWORD(label, val)                      do { } while (0)
#define LOG_BOOL(label, val)                        do { } while (0)
#define LOG_PTR(label, ptr)                         do { } while (0)
#define LOG_CHUNK(label, ch)                        do { } while (0)
#define LOG_MEM(label, mh)                          do { } while (0)
#define LOG_FILE(label, fh)                         do { } while (0)
#define LOG_OPTR(label, o)                          do { } while (0)
#define LOG_STR(label, val)                         do { } while (0)
#define LOG_STR_SEGMENT(label, str, from, to)       do { } while (0)
#define LOG_STR_HEAD(label, str, len)               do { } while (0)
#define LOG_STR_TAIL(label, str, len)               do { } while (0)
#define LOG_STR_RANGE(label, str, from, to)         do { } while (0)
#define LOG_STR_ALL(label, str)                     do { } while (0)

#endif /* DEBUG_LOG */
//#endif /* __DBGLOG_H */
