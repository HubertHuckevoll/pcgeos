/* BSNWAV/MP3/minimp3_port.c
 * The ONLY translation unit compiling minimp3's implementation.
 * Compile as plain C with Watcom.
 */
#define MINIMP3_IMPLEMENTATION
#include "minimp3_port.h"

static mp3dec_scratch_t *g_minimp3_scratch_ptr = (mp3dec_scratch_t *)0;

int mp3dec_get_scratch_size(void)
{
    return (int)sizeof(mp3dec_scratch_t);
}

void mp3dec_assign_scratch(void *scratchMem)
{
    g_minimp3_scratch_ptr = (mp3dec_scratch_t *)scratchMem;
}

mp3dec_scratch_t *mp3dec_get_scratch_ptr(void)
{
    return g_minimp3_scratch_ptr;
}
