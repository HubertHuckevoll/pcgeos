/* ------------------------------------------------------------------
 * Copyright (C) 1998-2009 PacketVideo
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 * -------------------------------------------------------------------
 */
/* PC/GEOS port: C89 and 16-bit Watcom adaptations. See the port report. */
/*
------------------------------------------------------------------------------
   PacketVideo Corp.
   MP3 Decoder Library

   Filename: pv_mp3dec_fxd_op.h

     Date: 09/21/2007

------------------------------------------------------------------------------
 REVISION HISTORY


 Description:
------------------------------------------------------------------------------
 INCLUDE DESCRIPTION

 Fixed-point multiply/accumulate primitives.

 microMP3: upstream dispatched here to one of four platform variants
 (PV_ARM_V5/V4, PV_ARM_GCC_V5/V4, PV_ARM_MSC_EVC_V5/V4, or the C equivalent)
 based on build macros that this fork never defines. The non-generic variants
 and their assembly were dropped and the C-equivalent routines (formerly in
 pv_mp3dec_fxd_op_c_equivalent.h) folded in here. See CHANGES.md.

------------------------------------------------------------------------------
*/

#ifndef PV_MP3DEC_FXD_OP_H
#define PV_MP3DEC_FXD_OP_H

#ifdef __cplusplus
extern "C"
{
#endif

#include "pvmp3_audio_type_defs.h"



    static __inline int32 pv_abs(int32 a)
    {
        int32 b = (a < 0) ? -a : a;
        return b;
    }

/* microMP3: round-to-nearest bias (+0.5 LSB) on the fixed-point shift, replacing
 * upstream's truncation (floor). This removes a systematic per-product downward
 * bias that costs ~4-6 dB PSNR vs a float decoder and produces worst-case sample
 * errors up to 5 LSB on dense, full-spectrum content. The Q32 ops are left
 * truncating on purpose: ((int64)a*b) >> 32 maps to a single Xtensa mulsh, and
 * adding a bias would force a full 64-bit multiply. The other shifts are already
 * full 64-bit multiplies, so rounding them is free. */
#include "../mp3fxp.h"

#define fxp_mul32_Q30(a,b) Mp3MulShift((a), (b), 30)
#define fxp_mul32_Q32(a,b) Mp3MulShift((a), (b), 32)
#define fxp_mul32_Q28(a,b) Mp3MulShift((a), (b), 28)
#define fxp_mul32_Q27(a,b) Mp3MulShift((a), (b), 27)
#define fxp_mul32_Q29(a,b) Mp3MulShift((a), (b), 29)
#define fxp_mac32_Q30(a,b,c) ((int32)((uint32)(c) + \
                                    (uint32)fxp_mul32_Q30((a),(b))))
#define fxp_mac32_Q32(c,a,b) ((int32)((uint32)(c) + \
                                    (uint32)fxp_mul32_Q32((a),(b))))
#define fxp_msb32_Q32(c,a,b) ((int32)((uint32)(c) - \
                                    (uint32)fxp_mul32_Q32((a),(b))))

#ifdef __cplusplus
}
#endif

#endif  /* PV_MP3DEC_FXD_OP_H */
