#ifndef __DBGLOG_H
#define __DBGLOG_H
/*
 * Debug logging header.
 * Macros compile to real logging code only when DEBUG_LOG is defined;
 * otherwise they expand to no-ops without evaluating their arguments.
 */

#ifdef DEBUG_LOG

#include <geos.h>
#include <file.h>
#include <timedate.h>
#include <Ansi/stdio.h>
#include <Ansi/string.h>
#include <localize.h>

#define LOG_FILENAME "dbglog.txt"

/* --- unique-name helpers for static buffers (no stack usage) --- */
#define _DBG_JOIN(a,b) a##b
#define _DBG_UNIQUE(base) _DBG_JOIN(base,__LINE__)

/*
 * Open (or create) the log file in SP_DOCUMENT and optionally truncate it.
 * Returns the FileHandle via 'fh'; leaves current dir unchanged.
 */
#define _DBG_OPEN_LOG_FILE(truncate, fh) \
    do { \
        FileHandle _dbg_fh; \
        FilePushDir(); \
        FileSetStandardPath(SP_DOCUMENT); \
        if (truncate) { FileDelete(LOG_FILENAME); } \
        _dbg_fh = FileOpen(LOG_FILENAME, FILE_ACCESS_RW | FILE_DENY_W); \
        if (_dbg_fh == NullHandle) { \
            _dbg_fh = FileCreate(LOG_FILENAME, FILE_CREATE_TRUNCATE | FCF_NATIVE | FILE_ACCESS_RW | FILE_DENY_W, 0); \
        } \
        (fh) = _dbg_fh; \
        FilePopDir(); \
    } while (0)

/*
 * Append a single line to the log file and add CRLF.
 * Creates the file if needed; closes it after the write.
 */
#define _WRITE_TO_FILE(str) \
    do { \
        FileHandle _dbg_fh2; \
        _DBG_OPEN_LOG_FILE(FALSE, _dbg_fh2); \
        if (_dbg_fh2 != NullHandle) { \
            FilePos(_dbg_fh2, 0L, FILE_POS_END); \
            FileWrite(_dbg_fh2, (void *)(str), strlen(str), FALSE); \
            FileWrite(_dbg_fh2, (void *)"\r\n", 2, FALSE); \
            FileClose(_dbg_fh2, FALSE); \
        } \
    } while (0)

/*
 * Initialize a fresh log by truncating/creating the file.
 * Does not write any content.
 */
#define LOG_INIT() \
    do { \
        FileHandle _dbg_fh3; \
        _DBG_OPEN_LOG_FILE(TRUE, _dbg_fh3); \
        if (_dbg_fh3 != NullHandle) { FileClose(_dbg_fh3, FALSE); } \
    } while (0)

/*
 * Write a timestamped "LOG START" line using current time.
 */
#define LOG_START() \
    do { \
        static char _DBG_UNIQUE(_dbg_time_)[64]; \
        static char _DBG_UNIQUE(_dbg_line_)[96]; \
        char * _dbg_time = _DBG_UNIQUE(_dbg_time_); \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        TimerDateAndTime _dbg_now; \
        TimerGetDateAndTime(&_dbg_now); \
        LocalFormatDateTime(_dbg_time, DTF_HMS_24HOUR, &_dbg_now); \
        sprintf(_dbg_line, "=== LOG START: %s ===", _dbg_time); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

/*
 * Write a simple "LOG END" terminator line.
 */
#define LOG_END() \
    _WRITE_TO_FILE("=== LOG END ===")

/* ---------- value/pointer logging (static buffers, no stack) ---------- */

#define LOG_BYTE(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %u", (label), (word)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_SBYTE(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %d", (label), (sword)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_WORD(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %u (0x%04x)", (label), (word)(val), (word)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_SWORD(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %d", (label), (sword)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_DWORD(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[80]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %lu (0x%08lx)", (label), (unsigned long)(val), (unsigned long)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_SDWORD(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[80]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %ld", (label), (long)(sdword)(val)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_BOOL(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %s", (label), (val) ? "TRUE" : "FALSE"); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_PTR(label, ptr) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: %Fp", (label), (ptr)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_CHUNK(label, ch) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: chunk 0x%04x", (label), (word)(ch)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_MEM(label, mh) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: mem handle 0x%04x", (label), (word)(mh)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_FILE(label, fh) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[64]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: file handle 0x%04x", (label), (word)(fh)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_OPTR(label, o) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[80]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        sprintf(_dbg_line, "%s: optr 0x%08lx", (label), (unsigned long)(o)); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

/* ---------- string logging (static buffers, unique per call site) ---------- */

#define LOG_STR(label, val) \
    do { \
        static char _DBG_UNIQUE(_dbg_line_)[256]; \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        const char *_dbg_s = (val) ? (val) : ""; \
        sprintf(_dbg_line, "%s: \"%s\"", (label), _dbg_s); \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

/* String segment logging (no stack usage, safe bounds) */
#define LOG_STR_SEGMENT(label, str, from, to) \
    do { \
        static char _DBG_UNIQUE(_dbg_seg_)[256]; \
        static char _DBG_UNIQUE(_dbg_line_)[320]; \
        char * _dbg_seg  = _DBG_UNIQUE(_dbg_seg_); \
        char * _dbg_line = _DBG_UNIQUE(_dbg_line_); \
        const char *_dbg_s = (str); \
        word _dbg_len = _dbg_s ? (word)strlen(_dbg_s) : 0; \
        word _dbg_f = ((from) < _dbg_len) ? (from) : 0; \
        word _dbg_t = ((to)   < _dbg_len) ? (to)   : _dbg_len; \
        word _dbg_n = (_dbg_t > _dbg_f) ? (_dbg_t - _dbg_f) : 0; \
        if (_dbg_n >= (word)sizeof(_DBG_UNIQUE(_dbg_seg_))) _dbg_n = (word)sizeof(_DBG_UNIQUE(_dbg_seg_)) - 1; \
        if (_dbg_n > 0 && _dbg_s) { \
            memcpy(_dbg_seg, _dbg_s + _dbg_f, _dbg_n); \
            _dbg_seg[_dbg_n] = 0; \
            sprintf(_dbg_line, "%s: \"%s\"", (label), _dbg_seg); \
        } else { \
            sprintf(_dbg_line, "%s: [string empty or out of bounds]", (label)); \
        } \
        _WRITE_TO_FILE(_dbg_line); \
    } while (0)

#define LOG_STR_HEAD(label, str, len) \
    LOG_STR_SEGMENT(label, str, 0, (len))

#define LOG_STR_TAIL(label, str, len) \
    do { \
        const char *_dbg_s = (str); \
        word _dbg_len = _dbg_s ? (word)strlen(_dbg_s) : 0; \
        word _dbg_from = (_dbg_len > (len)) ? (_dbg_len - (len)) : 0; \
        LOG_STR_SEGMENT(label, str, _dbg_from, _dbg_len); \
    } while (0)

#define LOG_STR_RANGE(label, str, from, to) \
    LOG_STR_SEGMENT(label, str, (from), (to))

#define LOG_STR_ALL(label, str) \
    do { \
        const char *_dbg_s = (str); \
        word _dbg_len = _dbg_s ? (word)strlen(_dbg_s) : 0; \
        LOG_STR_SEGMENT(label, str, 0, _dbg_len); \
    } while (0)

#else   /* !DEBUG_LOG */

/* All stubs: no evaluation of args, no code emitted. */
#define _DBG_OPEN_LOG_FILE(truncate, fh)            do { } while (0)
#define _WRITE_TO_FILE(str)                         do { } while (0)
#define LOG_INIT()                                  do { } while (0)
#define LOG_START()                                 do { } while (0)
#define LOG_END()                                   do { } while (0)

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
