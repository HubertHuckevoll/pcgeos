/* Identical host/Watcom product corpus; watcom.pl compares all results. */
#include <stdio.h>
#include <assert.h>
#include "../core/pvmp3_audio_type_defs.h"
#include "../mp3fxp.h"

int main(void)
{
    static const int32 edges[] = {0, 1, -1, INT32_MAX, INT32_MIN,
                                  65535, 65536, -65536, 0x40000000L};
    uint32 state = 1;
    unsigned i, j, shift;
    int32 a, b, c;
    FILE *fileP;

    fileP = fopen("math.pcm", "wb");
    assert(fileP && sizeof(int32) == 4 && sizeof(int16) == 2);
    for (i = 0; i < 1000; i++) {
        state = state * 1664525UL + 1013904223UL;
        a = (int32)state;
        state = state * 1664525UL + 1013904223UL;
        b = (int32)state;
        for (shift = 27; shift <= 32; shift++) {
            c = Mp3MulShift(a, b, shift);
            assert(fwrite(&c, 4, 1, fileP) == 1);
        }
    }
    for (i = 0; i < sizeof(edges) / sizeof(edges[0]); i++) {
        for (j = 0; j < sizeof(edges) / sizeof(edges[0]); j++) {
            for (shift = 27; shift <= 32; shift++) {
                c = Mp3MulShift(edges[i], edges[j], shift);
                assert(fwrite(&c, 4, 1, fileP) == 1);
            }
        }
    }
    assert(!fclose(fileP));
    return 0;
}
