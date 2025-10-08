#ifndef __QOA_DEBUG_H__
#define __QOA_DEBUG_H__

#ifndef QOA_DEBUG_LOGGING
#define QOA_DEBUG_LOGGING
#endif

#ifndef QOA_DEBUG_VERBOSE
#define QOA_DEBUG_VERBOSE 0
#endif

#include <geos.h>
#include <stdarg.h>

void    QOADebug_Reset(const char *fileName);
void    QOADebug_Log(const char *fmt, ...);
void    QOADebug_LogV(const char *fmt, va_list ap);
void    QOADebug_LogVerbose(const char *fmt, ...);
void    QOADebug_LogVerboseV(const char *fmt, va_list ap);
void    QOADebug_SetVerbose(Boolean enable);
Boolean QOADebug_IsVerbose(void);
void    QOADebug_Flush(void);
void    QOADebug_EndSession(void);

#endif /* __QOA_DEBUG_H__ */
