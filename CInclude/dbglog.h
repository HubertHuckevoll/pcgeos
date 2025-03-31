#ifndef __DBGLOG_H
#define __DBGLOG_H

#include <geos.h>
#include <file.h>
#include <timedate.h>
#include <Ansi/stdio.h>
#include <Ansi/string.h>
#include <localize.h>

#define LOG_FILENAME "dbglog.txt"

// Log file open/create macro
#define _DBG_OPEN_LOG_FILE(truncate, fh) \
    do { \
        FilePushDir(); \
        FileSetStandardPath(SP_DOCUMENT); \
        if (truncate) { FileDelete(LOG_FILENAME); } \
        (fh) = FileOpen(LOG_FILENAME, FILE_ACCESS_RW | FILE_DENY_W); \
        if ((fh) == NullHandle) { \
            (fh) = FileCreate(LOG_FILENAME, FILE_CREATE_TRUNCATE | FCF_NATIVE | FILE_ACCESS_RW | FILE_DENY_W, 0); \
        } \
        FilePopDir(); \
    } while (0)

// File write macro
#define _WRITE_TO_FILE(str) \
    do { \
        FileHandle __fh; \
        _DBG_OPEN_LOG_FILE(FALSE, __fh); \
        if (__fh != NullHandle) { \
            FilePos(__fh, 0L, FILE_POS_END); \
            FileWrite(__fh, (void *)(str), strlen(str), FALSE); \
            FileWrite(__fh, (void *)"\r\n", 2, FALSE); \
            FileClose(__fh, FALSE); \
        } \
    } while (0)

// Initialization macros
#define LOG_INIT() \
    do { \
        FileHandle __fh; \
        _DBG_OPEN_LOG_FILE(TRUE, __fh); \
        if (__fh != NullHandle) { FileClose(__fh, FALSE); } \
    } while (0)

#define LOG_START() \
    do { \
        char __time[64]; \
        char __line[96]; \
        TimerDateAndTime __now; \
        TimerGetDateAndTime(&__now); \
        LocalFormatDateTime(__time, DTF_HMS_24HOUR, &__now); \
        sprintf(__line, "=== LOG START: %s ===", __time); \
        _WRITE_TO_FILE(__line); \
    } while (0)

#define LOG_END() \
    _WRITE_TO_FILE("=== LOG END ===")

// Core type logging
#define LOG_BYTE(label, val) \
    do { char __buf[64]; sprintf(__buf, "%s: %u", (label), (word)(val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_SBYTE(label, val) \
    do { char __buf[64]; sprintf(__buf, "%s: %d", (label), (sword)(val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_WORD(label, val) \
    do { char __buf[64]; sprintf(__buf, "%s: %u (0x%04x)", (label), (val), (val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_SWORD(label, val) \
    do { char __buf[64]; sprintf(__buf, "%s: %d", (label), (sword)(val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_DWORD(label, val) \
    do { char __buf[80]; sprintf(__buf, "%s: %lu (0x%08lx)", (label), (val), (val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_SDWORD(label, val) \
    do { char __buf[80]; sprintf(__buf, "%s: %ld", (label), (sdword)(val)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_BOOL(label, val) \
    do { char __buf[64]; sprintf(__buf, "%s: %s", (label), (val) ? "TRUE" : "FALSE"); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_PTR(label, ptr) \
    do { char __buf[64]; sprintf(__buf, "%s: %Fp", (label), (ptr)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_CHUNK(label, ch) \
    do { char __buf[64]; sprintf(__buf, "%s: chunk 0x%04x", (label), (ch)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_MEM(label, mh) \
    do { char __buf[64]; sprintf(__buf, "%s: mem handle 0x%04x", (label), (mh)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_FILE(label, fh) \
    do { char __buf[64]; sprintf(__buf, "%s: file handle 0x%04x", (label), (fh)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_OPTR(label, o) \
    do { char __buf[80]; sprintf(__buf, "%s: optr 0x%08lx", (label), (o)); _WRITE_TO_FILE(__buf); } while (0)

#define LOG_STR(label, val) \
    do { char __buf[256]; sprintf(__buf, "%s: \"%s\"", (label), (val)); _WRITE_TO_FILE(__buf); } while (0)

// String segment logging
#define LOG_STR_SEGMENT(label, str, from, to) \
    do { \
        char __segment[256]; \
        char __line[320]; \
        word __len = strlen(str); \
        word __f = (from < __len) ? from : 0; \
        word __t = (to < __len) ? to : __len; \
        if ((__t > __f) && ((__t - __f) < sizeof(__segment))) { \
            memcpy(__segment, (str) + __f, __t - __f); \
            __segment[__t - __f] = '\0'; \
            sprintf(__line, "%s: \"%s\"", (label), __segment); \
        } else { \
            sprintf(__line, "%s: [string empty or out of bounds]", (label)); \
        } \
        _WRITE_TO_FILE(__line); \
    } while (0)

#define LOG_STR_HEAD(label, str, len) \
    LOG_STR_SEGMENT(label, str, 0, len)

#define LOG_STR_TAIL(label, str, len) \
    do { \
        word __len = strlen(str); \
        word __from = (__len > (len)) ? (__len - (len)) : 0; \
        LOG_STR_SEGMENT(label, str, __from, __len); \
    } while (0)

#define LOG_STR_RANGE(label, str, from, to) \
    LOG_STR_SEGMENT(label, str, from, to)

#define LOG_STR_ALL(label, str) \
    LOG_STR_SEGMENT(label, str, 0, strlen(str))

#endif // __DBGLOG_H
