/* OpenCORE reference C routines; see NOTICE and core/CHANGES.md. */
#ifdef __WATCOMC__
#pragma code_seg("MP3FrameCode")
#endif
#include "core/pvmp3_framedecoder.inc"
#include "core/pvmp3_decode_header.inc"
#include "core/pvmp3_get_main_data_size.inc"
#include "core/pvmp3_get_side_info.inc"
#include "core/pvmp3_get_scale_factors.inc"
#include "core/pvmp3_mpeg2_get_scale_data.inc"
#include "core/pvmp3_mpeg2_get_scale_factors.inc"
#include "core/pvmp3_seek_synch.inc"
#include "core/pvmp3_crc.inc"
#include "core/pvmp3_reorder.inc"
