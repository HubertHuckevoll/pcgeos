/* BSNWAV/MP3/minimp3_conf.h
 * Project-wide minimp3 include (no implementation here).
 * Integer PCM output. No stdio. No SIMD.
 */
#ifndef MINIMP3_CONF_H
#define MINIMP3_CONF_H

#define MINIMP3_NO_SIMD
#define MINIMP3_NO_STDIO

/* minimp3.h is vendored right next to this file */
#include "minimp3.h"

#endif /* MINIMP3_CONF_H */
