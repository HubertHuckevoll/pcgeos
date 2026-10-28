/* OpenCORE reference C routines; see NOTICE and core/CHANGES.md. */
#ifdef __WATCOMC__
#pragma code_seg("MP3ImdctCode")
#endif
#include "core/pvmp3_imdct_synth.inc"
#include "core/pvmp3_mdct_18.inc"
#include "core/pvmp3_mdct_6.inc"
#include "core/pvmp3_dct_9.inc"
#undef cos_pi_6
#include "core/pvmp3_dct_6.inc"
#include "core/pvmp3_normalize.inc"
#include "core/pvmp3_alias_reduction.inc"
