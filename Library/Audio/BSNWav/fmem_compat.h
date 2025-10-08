#ifndef BSNWAV_FMEM_COMPAT_H
#define BSNWAV_FMEM_COMPAT_H

#include <geos.h>

#include <Ansi/string.h>

#ifndef _fmemset
#define _fmemset memset
#endif
#ifndef _fmemcpy
#define _fmemcpy memcpy
#endif
#ifndef _fmemmove
#define _fmemmove memmove
#endif

#endif /* BSNWAV_FMEM_COMPAT_H */
