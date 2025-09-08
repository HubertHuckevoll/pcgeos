#ifndef __DBGLOG_H
#define __DBGLOG_H

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

/* Export/calling-convention helpers (safe defaults if not set) */
#ifndef DBG_PASCAL
#define DBG_PASCAL   _pascal
#endif
#ifndef DBG_CDECL
#define DBG_CDECL    _cdecl      /* required for varargs */
#endif
#ifdef DBGLOG_BUILD
#   define DBG_EXP   _export
#else
#   define DBG_EXP
#endif

/* Non-varargs API can remain Pascal if you prefer */
DBG_EXP void DBG_PASCAL DbgLogInit(void);
DBG_EXP void DBG_PASCAL DbgLogStart(void);
DBG_EXP void DBG_PASCAL DbgLogEnd(void);

/* Varargs MUST be cdecl on Watcom */
DBG_EXP void DBG_CDECL  DbgPrintf(const char *fmt, ...);
DBG_EXP void DBG_CDECL  DbgLogPrintf(const char *label, const char *fmt, ...);

/* Typed helpers (kept for compatibility) */
DBG_EXP void DBG_PASCAL DbgLogByte(const char *label, word val);
DBG_EXP void DBG_PASCAL DbgLogSByte(const char *label, sword val);
DBG_EXP void DBG_PASCAL DbgLogWord(const char *label, word val);
DBG_EXP void DBG_PASCAL DbgLogSWord(const char *label, sword val);
DBG_EXP void DBG_PASCAL DbgLogDWord(const char *label, dword val);
DBG_EXP void DBG_PASCAL DbgLogSDWord(const char *label, sdword val);
DBG_EXP void DBG_PASCAL DbgLogBool(const char *label, Boolean val);
DBG_EXP void DBG_PASCAL DbgLogPtr(const char *label, const void *ptrP);
DBG_EXP void DBG_PASCAL DbgLogChunk(const char *label, word ch);
DBG_EXP void DBG_PASCAL DbgLogMem(const char *label, word mh);
DBG_EXP void DBG_PASCAL DbgLogFile(const char *label, word fh);
DBG_EXP void DBG_PASCAL DbgLogOptr(const char *label, dword o);
DBG_EXP void DBG_PASCAL DbgLogStr(const char *label, const char *val);
DBG_EXP void DBG_PASCAL DbgLogStrSegment(const char *label, const char *str, word from, word to);
DBG_EXP void DBG_PASCAL DbgLogStrHead(const char *label, const char *str, word len);
DBG_EXP void DBG_PASCAL DbgLogStrTail(const char *label, const char *str, word len);
DBG_EXP void DBG_PASCAL DbgLogStrRange(const char *label, const char *str, word from, word to);
DBG_EXP void DBG_PASCAL DbgLogStrAll(const char *label, const char *str);

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
#endif /* __DBGLOG_H */
