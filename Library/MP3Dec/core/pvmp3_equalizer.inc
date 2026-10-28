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
/* PC/GEOS: Q constants frozen to host reference values; see port report. */
/*
------------------------------------------------------------------------------

   PacketVideo Corp.
   MP3 Decoder Library

   Filename: pvmp3_equalizer.cpp


     Date: 09/21/2007

------------------------------------------------------------------------------
 REVISION HISTORY


 Description:

------------------------------------------------------------------------------
 INPUT AND OUTPUT DEFINITIONS

  Input
    int32          *inData,           pointer to the spectrum frequency-line
    e_equalization equalizerType,     equalization mode
    int32          *pt_work_buff

  Output
    int32          *pt_work_buff      pointer to the equalized frequency-line

------------------------------------------------------------------------------
 FUNCTION DESCRIPTION

    Equalizer
    Each subband sample is scaled according to a spectrum shape setting
    defined by "equalizerType"

------------------------------------------------------------------------------
 REQUIREMENTS


------------------------------------------------------------------------------
 REFERENCES

------------------------------------------------------------------------------
 PSEUDO-CODE

------------------------------------------------------------------------------
*/


/*----------------------------------------------------------------------------
; INCLUDES
----------------------------------------------------------------------------*/

#include "pvmp3_equalizer.h"
#include "pv_mp3dec_fxd_op.h"
#include "pvmp3_dec_defs.h"

/*----------------------------------------------------------------------------
; MACROS
; Define module specific macros here
----------------------------------------------------------------------------*/


/*----------------------------------------------------------------------------
; DEFINES
; Include all pre-processor statements here. Include conditional
; compile variables also.
----------------------------------------------------------------------------*/



/*----------------------------------------------------------------------------
; LOCAL FUNCTION DEFINITIONS
; Function Prototype declaration
----------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------
; LOCAL STORE/BUFFER/POINTER DEFINITIONS
; Variable declaration - defined here and used outside this module
----------------------------------------------------------------------------*/

const int32 equalizerTbl[8][SUBBANDS_NUMBER] =
{
    /*  FLAT */
    {
        2147483520L,

        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L
    },
    /*  BASS BOOST */
    {
        2147483520L,

        1806882304L, 1518500224L,

        1279174656L, 1073741824L,
        1073741824L, 1073741824L,

        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,

        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L, 1073741824L,
        1073741824L
    },
    /*  ROCK */
    {
        2147483520L,

        1806882304L, 1518500224L,

        1279174656L, 1073741824L,
        1073741824L, 1073741824L,

        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1806882304L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L
    },
    /*  POP */
    {
        1073741824L,

        1518500224L, 1518500224L,

        1806882304L, 2147483520L,
        2147483520L, 2147483520L,

        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,

        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L, 759250112L,
        759250112L
    },
    /*  JAZZ */
    {
        2147483520L,

        1073741824L, 1073741824L,

        759250112L, 759250112L,
        759250112L, 759250112L,

        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1806882304L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L
    },
    /*  CLASSICAL */
    {
        2147483520L,

        759250112L, 759250112L,

        759250112L, 759250112L,
        759250112L, 759250112L,

        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1806882304L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L
    },
    /*  TALK */
    {
        759250112L,

        1073741824L, 1073741824L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 1806882304L,

        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L, 1518500224L,
        1518500224L
    },
    /*  FLAT */
    {
        2147483520L,

        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,

        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L, 2147483520L,
        2147483520L
    }
};

/*----------------------------------------------------------------------------
; EXTERNAL FUNCTION REFERENCES
; Declare functions defined elsewhere and referenced in this module
----------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------
; EXTERNAL GLOBAL STORE/BUFFER/POINTER REFERENCES
; Declare variables used in this module but defined elsewhere
----------------------------------------------------------------------------*/


/*----------------------------------------------------------------------------
; FUNCTION CODE
----------------------------------------------------------------------------*/

void pvmp3_equalizer(int32 *circ_buffer,
                     e_equalization equalizerType,
                     int32 *work_buff)
{
    int32 band;


    if (equalizerType == flat)
    {
        for (band = 0; band < FILTERBANK_BANDS; band += 2)
        {

            int32 *pt_work_buff = &work_buff[band];
            int32 *inData = &circ_buffer[544 - (band<<5)];

            int32 i;
            for (i = 0; i < SUBBANDS_NUMBER*FILTERBANK_BANDS; i += FILTERBANK_BANDS << 2)
            {
                int32 temp1 = (pt_work_buff[ i ]);
                int32 temp2 = (pt_work_buff[ i +   FILTERBANK_BANDS ]);
                int32 temp3 = (pt_work_buff[ i + 2*FILTERBANK_BANDS ]);
                int32 temp4 = (pt_work_buff[ i + 3*FILTERBANK_BANDS ]);
                *(inData++) = temp1;
                *(inData++) = temp2;
                *(inData++) = temp3;
                *(inData++) = temp4;
            }

            inData -= SUBBANDS_NUMBER << 1;
            pt_work_buff++;

            for (i = 0; i < SUBBANDS_NUMBER*FILTERBANK_BANDS; i += FILTERBANK_BANDS << 2)
            {
                int32 temp1 = (pt_work_buff[ i ]);
                int32 temp2 = (pt_work_buff[ i +   FILTERBANK_BANDS ]);
                int32 temp3 = (pt_work_buff[ i + 2*FILTERBANK_BANDS ]);
                int32 temp4 = (pt_work_buff[ i + 3*FILTERBANK_BANDS ]);
                *(inData++) = temp1;
                *(inData++) = temp2;
                *(inData++) = temp3;
                *(inData++) = temp4;
            }
        }
    }
    else
    {
        const int32 *pt_equalizer = equalizerTbl[equalizerType&7];


        for (band = 0; band < FILTERBANK_BANDS; band += 2)
        {
            int32 *inData = &circ_buffer[544 - (band<<5)];

            int32 *pt_work_buff = &work_buff[band];
            int32 i;

            for (i = 0; i < SUBBANDS_NUMBER*FILTERBANK_BANDS; i += FILTERBANK_BANDS << 2)
            {
                int32 temp1 = (pt_work_buff[ i ]);
                int32 temp2 = (pt_work_buff[ i +   FILTERBANK_BANDS ]);
                int32 temp3 = (pt_work_buff[ i + 2*FILTERBANK_BANDS ]);
                int32 temp4 = (pt_work_buff[ i + 3*FILTERBANK_BANDS ]);
                *(inData++) = fxp_mul32_Q32(temp1 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp2 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp3 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp4 << 1, *(pt_equalizer++));
            }

            pt_equalizer -= SUBBANDS_NUMBER;

            inData -= SUBBANDS_NUMBER << 1;
            pt_work_buff++;

            for (i = 0; i < SUBBANDS_NUMBER*FILTERBANK_BANDS; i += FILTERBANK_BANDS << 2)
            {
                int32 temp1 = (pt_work_buff[ i ]);
                int32 temp2 = (pt_work_buff[ i +   FILTERBANK_BANDS ]);
                int32 temp3 = (pt_work_buff[ i + 2*FILTERBANK_BANDS ]);
                int32 temp4 = (pt_work_buff[ i + 3*FILTERBANK_BANDS ]);
                *(inData++) = fxp_mul32_Q32(temp1 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp2 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp3 << 1, *(pt_equalizer++));
                *(inData++) = fxp_mul32_Q32(temp4 << 1, *(pt_equalizer++));
            }
            pt_equalizer -= SUBBANDS_NUMBER;

        }
    }
}
