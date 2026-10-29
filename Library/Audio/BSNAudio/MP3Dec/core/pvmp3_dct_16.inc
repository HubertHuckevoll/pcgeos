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

   Filename: pvmp3_dct_16.cpp

   Functions:
    dct_16
    pv_merge_in_place_N32
    pv_split

     Date: 09/21/2007

------------------------------------------------------------------------------
 REVISION HISTORY


 Description:

------------------------------------------------------------------------------
 INPUT AND OUTPUT DEFINITIONS

    dct_16

Input
    int32 vec[],        input vector length 16
    Int flag            processing direction: forward (1), backward ( 0)
 Returns

    int32 vec[],        dct length 16

------------------------------------------------------------------------------
 INPUT AND OUTPUT DEFINITIONS

    pv_merge_in_place_N32

Input
    int32 vec[],        input vector length 16

 Returns

    int32 vec[],        merged  output of two dct 16 to create a dct 32

------------------------------------------------------------------------------
 INPUT AND OUTPUT DEFINITIONS

    pv_split

Input
    int32 vec[],        input vector length 16

 Returns

    int32 vec[],        splitted even/odd and pre processing rotation

------------------------------------------------------------------------------
 FUNCTION DESCRIPTION

    dct 16 and tools to assemble a dct32 output

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

#include "pvmp3_dct_16.h"
#include "pv_mp3dec_fxd_op.h"

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
const int32 CosTable_dct32[16] =
{
    1075036800L ,  1085490560L ,
    1106914688L ,  1140405248L ,
    1187781632L ,  1251843328L ,
    1336817408L ,  1449139840L ,
    1598879488L ,  1802489600L ,

    130535896L ,  156959568L ,
    199201200L ,  276190688L ,
    457361472L ,  1367679744L
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

void pvmp3_dct_16(int32 vec[], int32 flag)
{
    int32 tmp0;
    int32 tmp1;
    int32 tmp2;
    int32 tmp3;
    int32 tmp4;
    int32 tmp5;
    int32 tmp6;
    int32 tmp7;
    int32 tmp_o0;
    int32 tmp_o1;
    int32 tmp_o2;
    int32 tmp_o3;
    int32 tmp_o4;
    int32 tmp_o5;
    int32 tmp_o6;
    int32 tmp_o7;
    int32 itmp_e0;
    int32 itmp_e1;
    int32 itmp_e2;

    /*  split input vector */

    tmp_o0 = fxp_mul32_Q32((vec[ 0] - vec[15]), 1078937216L);
    tmp0   =  vec[ 0] + vec[15];

    tmp_o7 = fxp_mul32_Q32((vec[ 7] - vec[ 8]) << 3, 1369329152L);
    tmp7   =  vec[ 7] + vec[ 8];

    itmp_e0    = fxp_mul32_Q32((tmp0 - tmp7), 1094777728L);
    tmp7 = (tmp0 + tmp7);

    tmp_o1 = fxp_mul32_Q32((vec[ 1] - vec[14]), 1122057216L);
    tmp1   =  vec[ 1] + vec[14];

    tmp_o6 = fxp_mul32_Q32((vec[ 6] - vec[ 9]) << 1, 1849463552L);
    tmp6   =  vec[ 6] + vec[ 9];



    itmp_e1 = (tmp1 + tmp6);
    tmp6    = fxp_mul32_Q32((tmp1 - tmp6), 1291378304L);



    tmp_o2 = fxp_mul32_Q32((vec[ 2] - vec[13]), 1217503104L);
    tmp2   =  vec[ 2] + vec[13];
    tmp_o5 = fxp_mul32_Q32((vec[ 5] - vec[10]) << 1, 1138893952L);
    tmp5   =  vec[ 5] + vec[10];

    itmp_e2 = (tmp2 + tmp5);
    tmp5    = fxp_mul32_Q32((tmp2 - tmp5), 1932684160L);

    tmp_o3 = fxp_mul32_Q32((vec[ 3] - vec[12]), 1389039232L);
    tmp3   =  vec[ 3] + vec[12];
    tmp_o4 = fxp_mul32_Q32((vec[ 4] - vec[11]), 1692549120L);
    tmp4   =  vec[ 4] + vec[11];

    tmp1   = (tmp3 + tmp4);
    tmp4   =  fxp_mul32_Q32((tmp3 - tmp4) << 2, 1375954816L);

    /*  split even part of tmp_e */

    tmp0 = (tmp7 + tmp1);
    tmp1 = fxp_mul32_Q32((tmp7 - tmp1), 1162209792L);

    tmp3 = fxp_mul32_Q32((itmp_e1 - itmp_e2) << 1, 1402911360L);
    tmp7 = (itmp_e1 + itmp_e2);

    vec[ 0]  = (tmp0 + tmp7) >> 1;
    vec[ 8]  = fxp_mul32_Q32((tmp0 - tmp7), 1518500224L);
    tmp0     = fxp_mul32_Q32((tmp1 - tmp3) << 1, 1518500224L);
    vec[ 4]  =  tmp1 + tmp3 + tmp0;
    vec[12]  =  tmp0;

    /*  split odd part of tmp_e */

    tmp1 = fxp_mul32_Q32((itmp_e0 - tmp4) << 1, 1162209792L);
    tmp7 = itmp_e0 + tmp4;

    tmp3  = fxp_mul32_Q32((tmp6 - tmp5) << 2, 1402911360L);
    tmp6 += tmp5;

    tmp4  = fxp_mul32_Q32((tmp7 - tmp6) << 1, 1518500224L);
    tmp6 += tmp7;
    tmp7  = fxp_mul32_Q32((tmp1 - tmp3) << 1, 1518500224L);

    tmp1    +=  tmp3 + tmp7;
    vec[ 2]  =  tmp1 + tmp6;
    vec[ 6]  =  tmp1 + tmp4;
    vec[10]  =  tmp7 + tmp4;
    vec[14]  =  tmp7;


    /* dct8; */

    tmp1 = fxp_mul32_Q32((tmp_o0 - tmp_o7) << 1, 1094777728L);
    tmp7 = tmp_o0 + tmp_o7;

    tmp6   = tmp_o1 + tmp_o6;
    tmp_o1 = fxp_mul32_Q32((tmp_o1 - tmp_o6) << 1, 1291378304L);

    tmp5   = tmp_o2 + tmp_o5;
    tmp_o5 = fxp_mul32_Q32((tmp_o2 - tmp_o5) << 1, 1932684160L);

    tmp0 = fxp_mul32_Q32((tmp_o3 - tmp_o4) << 3, 1375954816L);
    tmp4 = tmp_o3 + tmp_o4;

    if (!flag)
    {
        tmp7   = -tmp7;
        tmp1   = -tmp1;
        tmp6   = -tmp6;
        tmp_o1 = -tmp_o1;
        tmp5   = -tmp5;
        tmp_o5 = -tmp_o5;
        tmp4   = -tmp4;
        tmp0   = -tmp0;
    }


    tmp2     =  fxp_mul32_Q32((tmp1 -   tmp0) << 1, 1162209792L);
    tmp0    +=  tmp1;
    tmp1     =  fxp_mul32_Q32((tmp7 -   tmp4) << 1, 1162209792L);
    tmp7    +=  tmp4;
    tmp4     =  fxp_mul32_Q32((tmp6 -   tmp5) << 2, 1402911360L);
    tmp6    +=  tmp5;
    tmp5     =  fxp_mul32_Q32((tmp_o1 - tmp_o5) << 2, 1402911360L);
    tmp_o1  += tmp_o5;


    vec[13]  =  fxp_mul32_Q32((tmp1 -   tmp4) << 1, 1518500224L);
    vec[ 5]  =  tmp1 + tmp4 + vec[13];

    vec[ 9]  =  fxp_mul32_Q32((tmp7 -   tmp6) << 1, 1518500224L);
    vec[ 1]  =  tmp7 + tmp6;

    tmp4     =  fxp_mul32_Q32((tmp0 - tmp_o1) << 1, 1518500224L);
    tmp0    +=  tmp_o1;
    tmp6     =  fxp_mul32_Q32((tmp2 -   tmp5) << 1, 1518500224L);
    tmp2    +=  tmp5 + tmp6;
    tmp0    +=  tmp2;

    vec[ 1] += tmp0;
    vec[ 3]  = tmp0 + vec[ 5];
    tmp2    += tmp4;
    vec[ 5]  = tmp2 + vec[ 5];
    vec[ 7]  = tmp2 + vec[ 9];
    tmp4    += tmp6;
    vec[ 9]  = tmp4 + vec[ 9];
    vec[11]  = tmp4 + vec[13];
    vec[13]  = tmp6 + vec[13];
    vec[15]  = tmp6;

}
/*----------------------------------------------------------------------------
; FUNCTION CODE
----------------------------------------------------------------------------*/
void pvmp3_merge_in_place_N32(int32 vec[])
{


    int32 temp0;
    int32 temp1;
    int32 temp2;
    int32 temp3;

    temp0   = vec[14];
    vec[14] = vec[ 7];
    temp1   = vec[12];
    vec[12] = vec[ 6];
    temp2   = vec[10];
    vec[10] = vec[ 5];
    temp3   = vec[ 8];
    vec[ 8] = vec[ 4];
    vec[ 6] = vec[ 3];
    vec[ 4] = vec[ 2];
    vec[ 2] = vec[ 1];

    vec[ 1] = (vec[16] + vec[17]);
    vec[16] = temp3;
    vec[ 3] = (vec[18] + vec[17]);
    vec[ 5] = (vec[19] + vec[18]);
    vec[18] = vec[9];

    vec[ 7] = (vec[20] + vec[19]);
    vec[ 9] = (vec[21] + vec[20]);
    vec[20] = temp2;
    temp2   = vec[13];
    temp3   = vec[11];
    vec[11] = (vec[22] + vec[21]);
    vec[13] = (vec[23] + vec[22]);
    vec[22] = temp3;
    temp3   = vec[15];

    vec[15] = (vec[24] + vec[23]);
    vec[17] = (vec[25] + vec[24]);
    vec[19] = (vec[26] + vec[25]);
    vec[21] = (vec[27] + vec[26]);
    vec[23] = (vec[28] + vec[27]);
    vec[24] = temp1;
    vec[25] = (vec[29] + vec[28]);
    vec[26] = temp2;
    vec[27] = (vec[30] + vec[29]);
    vec[28] = temp0;
    vec[29] = (vec[30] + vec[31]);
    vec[30] = temp3;
}


/*----------------------------------------------------------------------------
; FUNCTION CODE
----------------------------------------------------------------------------*/



void pvmp3_split(int32 *vect)
{

    int32 i;
    const int32 *pt_cosTerms = &CosTable_dct32[15];
    int32 *pt_vect   = vect;
    int32 *pt_vect_2 = pt_vect - 1;

    for (i = 3; i != 0; i--)
    {
        int32 tmp2 = *(pt_vect);
        int32 tmp1 = *(pt_vect_2);
        int32 cosx = *(pt_cosTerms--);
        *(pt_vect_2--) = (tmp1  + tmp2);
        *(pt_vect++)   = fxp_mul32_Q27((tmp1 - tmp2), cosx);

        tmp2 = *(pt_vect);
        tmp1 = *(pt_vect_2);
        cosx = *(pt_cosTerms--);
        *(pt_vect_2--) = (tmp1  + tmp2);
        *(pt_vect++)   = fxp_mul32_Q27((tmp1 - tmp2), cosx);

    }

    for (i = 5; i != 0; i--)
    {
        int32 tmp2 = *(pt_vect);
        int32 tmp1 = *(pt_vect_2);
        int32 cosx = *(pt_cosTerms--);
        *(pt_vect_2--) = (tmp1  + tmp2);
        *(pt_vect++) = fxp_mul32_Q32((tmp1 - tmp2) << 1, cosx);

        tmp2 = *(pt_vect);
        tmp1 = *(pt_vect_2);
        cosx = *(pt_cosTerms--);
        *(pt_vect_2--) = (tmp1  + tmp2);
        *(pt_vect++) = fxp_mul32_Q32((tmp1 - tmp2) << 1, cosx);
    }

}
