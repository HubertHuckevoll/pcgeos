/* Reference multiplier. GEOS uses the fixed ESP helper in mp3dsp.asm. */
#include "core/pvmp3_audio_type_defs.h"
#include "mp3fxp.h"
#ifdef __WATCOMC__
#pragma code_seg("MP3MathCode")
#endif
#ifndef MP3_386_DSP
int32 _pascal
Mp3MulShift(int32 a, int32 b, unsigned shift)
{
    uint32 ua = (uint32)a;
    uint32 ub = (uint32)b;
    uint32 a0 = ua & 0xffffUL;
    uint32 b0 = ub & 0xffffUL;
    uint32 a1 = ua >> 16;
    uint32 b1 = ub >> 16;
    uint32 w0 = a0 * b0;
    uint32 t = a1 * b0 + (w0 >> 16);
    uint32 w1 = (t & 0xffffUL) + a0 * b1;
    uint32 hi = a1 * b1 + (t >> 16) + (w1 >> 16);
    uint32 lo = (w1 << 16) | (w0 & 0xffffUL);
    uint32 bias;

    if (a < 0) {
        hi -= ub;
    }
    if (b < 0) {
        hi -= ua;
    }
    if (shift == 32) {
        return (int32)hi;
    }
    bias = (uint32)1 << (shift - 1);
    lo += bias;
    if (lo < bias) {
        hi++;
    }
    return (int32)((hi << (32 - shift)) | (lo >> shift));
}
#endif
