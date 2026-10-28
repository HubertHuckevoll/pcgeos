/* Standalone host/Watcom DSP regression, including the -ox shift bug. */
#include <stdio.h>
#include <assert.h>
#ifdef __WATCOMC__
#include <dos.h>
#include <i86.h>
#endif
#include "pvmp3_mdct_6.h"
#include "pvmp3_mdct_18.h"
#include "pvmp3_dct_16.h"
#include "pvmp3_imdct_synth.h"
extern const int32 normal_win[];

int main(void)
{
#ifdef __WATCOMC__
    int32 *v, *h, *scratch;
    unsigned vSeg, hSeg, scratchSeg;
#else
    static int32 v[576], h[576], scratch[198];
#endif
    unsigned i;
    FILE *fileP;

#ifdef __WATCOMC__
    /* Distinct DOS blocks exercise DS, ES and GS independently. */
    assert(!_dos_allocmem(144, &vSeg));
    assert(!_dos_allocmem(144, &hSeg));
    assert(!_dos_allocmem(50, &scratchSeg));
    v = (int32 *)MK_FP(vSeg, 0);
    h = (int32 *)MK_FP(hSeg, 0);
    scratch = (int32 *)MK_FP(scratchSeg, 0);
    assert(vSeg != hSeg && vSeg != scratchSeg && hSeg != scratchSeg);
#endif
    fileP = fopen("dsp.bin", "wb");
    assert(fileP);
    for (i = 0; i < 576; i++) {
        v[i] = (i * 1234567L + 7654321L) % 12345679L;
        h[i] = 0;
    }
    pvmp3_dct_6(v);
    assert(fwrite(v, 4, 6, fileP) == 6);
    pvmp3_dct_9(v);
    assert(fwrite(v, 4, 9, fileP) == 9);
    pvmp3_mdct_6(v, h);
    assert(fwrite(v, 4, 6, fileP) == 6 && fwrite(h, 4, 6, fileP) == 6);
    pvmp3_mdct_18(v, h, normal_win);
    assert(fwrite(v, 4, 18, fileP) == 18 && fwrite(h, 4, 18, fileP) == 18);
    assert(h[6] == -52622884L && h[9] == -10415105L);
    pvmp3_imdct_synth(v, h, 2, 0, 17, scratch);
    assert(fwrite(v, 4, 576, fileP) == 576 && fwrite(h, 4, 576, fileP) == 576);
    assert(!fclose(fileP));
#ifdef __WATCOMC__
    assert(!_dos_freemem(vSeg));
    assert(!_dos_freemem(hSeg));
    assert(!_dos_freemem(scratchSeg));
#endif
    return 0;
}
