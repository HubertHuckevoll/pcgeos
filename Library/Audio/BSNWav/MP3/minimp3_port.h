/* BSNWAV/MP3/minimp3_port.h
 * Project-wide minimp3 include (no implementation here).
 * Float PCM decode path (converted to s16 downstream). No stdio. No SIMD.
 */
#ifndef MINIMP3_PORT_H
#define MINIMP3_PORT_H

#define MINIMP3_GEOS_PORT

#define MINIMP3_NO_SIMD
#define MINIMP3_NO_STDIO
#define MINIMP3_ONLY_MP3
#define MINIMP3_FLOAT_OUTPUT

#include "minimp3.h"

#endif /* MINIMP3_CONF_H */
