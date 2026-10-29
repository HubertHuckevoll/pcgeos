/* OpenCORE reference C routines; see NOTICE and core/CHANGES.md. */
#ifdef __WATCOMC__
#pragma code_seg("MP3SynthCode")
#endif
#include "core/pvmp3_poly_phase_synthesis.inc"
#ifndef MP3_386_DSP
#include "core/pvmp3_polyphase_filter_window.inc"
#include "core/pvmp3_dct_16.inc"
#endif
#include "core/pvmp3_equalizer.inc"
