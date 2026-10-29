/* Host oracle for the target's 32-bit-only reference multiplier. */
#include <assert.h>
#include <stdio.h>
#include "../core/pvmp3_audio_type_defs.h"
#include "../mp3fxp.h"

int main(void)
{
    static const int32 edges[] = {0, 1, -1, INT32_MAX, INT32_MIN,
                                  65535, 65536, -65536, 0x40000000};
    uint32 state = 1;
    uint32 i;
    unsigned j, k, shift;
    int32 a, b, expected;
    int64_t product;

    for (i = 0; i < 200000; i++) {
        state = state * 1664525UL + 1013904223UL;
        a = (int32)state;
        state = state * 1664525UL + 1013904223UL;
        b = (int32)state;
        for (shift = 27; shift <= 32; shift++) {
            product = (int64_t)a * b;
            if (shift != 32) {
                product += (int64_t)1 << (shift - 1);
            }
            expected = (int32)(product >> shift);
            assert(Mp3MulShift(a, b, shift) == expected);
        }
    }
    for (j = 0; j < sizeof(edges)/sizeof(edges[0]); j++) {
        for (k = 0; k < sizeof(edges)/sizeof(edges[0]); k++) {
            for (shift = 27; shift <= 32; shift++) {
                product = (int64_t)edges[j] * edges[k];
                if (shift != 32) product += (int64_t)1 << (shift - 1);
                assert(Mp3MulShift(edges[j], edges[k], shift) ==
                       (int32)(product >> shift));
            }
        }
    }
    puts("fixed-point products: PASS");
    return 0;
}
