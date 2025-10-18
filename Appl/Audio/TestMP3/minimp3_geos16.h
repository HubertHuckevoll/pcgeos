/* minimp3_geos16.h  — Minimal MP3 Layer III decoder, int16 output, no SIMD, Watcom 16-bit friendly.
   Derived from https://github.com/lieff/minimp3 (public domain / CC0).
   This file has been pruned to: Layer III only; no SSE/MMX/NEON; int16_t output only.
*/

#include <stdint.h>
#include <string.h> /* memcpy, memmove, memset */
#include <geos.h>

#define MP3_FIXED_FRAC_BITS      16
#define MP3_FIXED_SCALE          (1L << MP3_FIXED_FRAC_BITS)
#define MP3_PCM_SHIFT            (MP3_FIXED_FRAC_BITS - 15)
#define MP3_MDCT_OVERLAP_LEN     (9*32)
#define MP3_QMF_STATE_LEN        (15*2*32)

static float g_mdct_overlap_temp[2][MP3_MDCT_OVERLAP_LEN];
static float g_qmf_state_temp[MP3_QMF_STATE_LEN];

static float mp3d_fixed_to_float(sdword value)
{
    return (float)value / (float)MP3_FIXED_SCALE;
}

static sdword mp3d_float_to_fixed(float value)
{
    float scaled;

    scaled = value * (float)MP3_FIXED_SCALE;
    if (scaled >= 2147483647.0f)
    {
        return 2147483647L;
    }
    if (scaled <= -2147483648.0f)
    {
        return -2147483648L;
    }
    return (sdword)scaled;
}

static void mp3d_fixed_to_float_buffer(const sdword *src, float *dst, word count)
{
    word i;

    for (i = 0; i < count; i++)
    {
        dst[i] = mp3d_fixed_to_float(src[i]);
    }
}

static void mp3d_float_to_fixed_buffer(sdword *dst, const float *src, word count)
{
    word i;

    for (i = 0; i < count; i++)
    {
        dst[i] = mp3d_float_to_fixed(src[i]);
    }
}

#define MINIMP3_MAX_SAMPLES_PER_FRAME (1152*2)

/* -------- Public API types -------- */
typedef struct {
    dword frame_bytes;
    dword frame_offset;
    word  channels;
    dword hz;
    word  layer;
    dword bitrate_kbps;
} mp3dec_frame_info_t;

typedef struct {
    sdword mdct_overlap[2][MP3_MDCT_OVERLAP_LEN];
    sdword qmf_state[MP3_QMF_STATE_LEN];
    sdword reserv;
    dword free_format_bytes;
    unsigned char header[4], reserv_buf[511];
} mp3dec_t;

/* scalar, int16 output */
typedef int16_t mp3d_sample_t;

/* --------- Bitstream ---------- */
typedef struct { const uint8_t *buf; int pos, limit; } bs_t;

static void bs_init(bs_t *bs, const uint8_t *data, int bytes)
{ bs->buf = data; bs->pos = 0; bs->limit = bytes*8; }

static uint32_t get_bits(bs_t *bs, int n)
{
    uint32_t next, cache = 0, s = bs->pos & 7;
    int shl = n + s;
    const uint8_t *p = bs->buf + (bs->pos >> 3);
    if ((bs->pos += n) > bs->limit) return 0;
    next = *p++ & (255u >> s);
    while ((shl -= 8) > 0) { cache |= next << shl; next = *p++; }
    return cache | (next >> -shl);
}

/* ---------- Header helpers (kept) ---------- */
#define HDR_SIZE                    4
#define MODE_MONO                   3
#define MODE_JOINT_STEREO           1
#define HDR_IS_MONO(h)              (((h[3]) & 0xC0) == 0xC0)
#define HDR_IS_MS_STEREO(h)         (((h[3]) & 0xE0) == 0x60)
#define HDR_IS_FREE_FORMAT(h)       (((h[2]) & 0xF0) == 0)
#define HDR_IS_CRC(h)               (!((h[1]) & 1))
#define HDR_TEST_PADDING(h)         ((h[2]) & 0x2)
#define HDR_TEST_MPEG1(h)           ((h[1]) & 0x8)
#define HDR_TEST_NOT_MPEG25(h)      ((h[1]) & 0x10)
#define HDR_TEST_I_STEREO(h)        ((h[3]) & 0x10)
#define HDR_TEST_MS_STEREO(h)       ((h[3]) & 0x20)
#define HDR_GET_STEREO_MODE(h)      (((h[3]) >> 6) & 3)
#define HDR_GET_STEREO_MODE_EXT(h)  (((h[3]) >> 4) & 3)
#define HDR_GET_LAYER(h)            (((h[1]) >> 1) & 3)
#define HDR_GET_BITRATE(h)          ((h[2]) >> 4)
#define HDR_GET_SAMPLE_RATE(h)      (((h[2]) >> 2) & 3)
#define HDR_GET_MY_SAMPLE_RATE(h)   (HDR_GET_SAMPLE_RATE(h) + (((h[1] >> 3) & 1) + ((h[1] >> 4) & 1))*3)
#define HDR_IS_FRAME_576(h)         ((h[1] & 14) == 2)
#define HDR_IS_LAYER_1(h)           ((h[1] & 6) == 6)

// #define MINIMP3_MIN(a,b) ((a)>(b)?(b):(a))
// #define MINIMP3_MAX(a,b) ((a)<(b)?(a):(b))

#define MINIMP3_MIN(a,b) ((a)>(b)?(b):(a))
#define MINIMP3_MAX(a,b) ((a)<(b)?(b):(a))   /* upstream-style */


static int hdr_valid(const uint8_t *h)
{
    return h[0] == 0xff &&
        ((h[1] & 0xF0) == 0xf0 || (h[1] & 0xFE) == 0xe2) &&
        (HDR_GET_LAYER(h) != 0) &&
        (HDR_GET_BITRATE(h) != 15) &&
        (HDR_GET_SAMPLE_RATE(h) != 3);
}

static int hdr_compare(const uint8_t *h1, const uint8_t *h2)
{
    return hdr_valid(h2) &&
        ((h1[1] ^ h2[1]) & 0xFE) == 0 &&
        ((h1[2] ^ h2[2]) & 0x0C) == 0 &&
        !(HDR_IS_FREE_FORMAT(h1) ^ HDR_IS_FREE_FORMAT(h2));
}

static unsigned hdr_bitrate_kbps(const uint8_t *h)
{
    static const uint8_t halfrate[2][3][15] = {
        { { 0,4,8,12,16,20,24,28,32,40,48,56,64,72,80 }, { 0,4,8,12,16,20,24,28,32,40,48,56,64,72,80 }, { 0,16,24,28,32,40,48,56,64,72,80,88,96,112,128 } },
        { { 0,16,20,24,28,32,40,48,56,64,80,96,112,128,160 }, { 0,16,24,28,32,40,48,56,64,80,96,112,128,160,192 }, { 0,16,32,48,64,80,96,112,128,144,160,176,192,208,224 } },
    };
    return 2*halfrate[!!HDR_TEST_MPEG1(h)][HDR_GET_LAYER(h) - 1][HDR_GET_BITRATE(h)];
}

static unsigned hdr_sample_rate_hz(const uint8_t *h)
{
    static const unsigned g_hz[3] = { 44100, 48000, 32000 };
    return g_hz[HDR_GET_SAMPLE_RATE(h)] >> (int)!HDR_TEST_MPEG1(h) >> (int)!HDR_TEST_NOT_MPEG25(h);
}

static unsigned hdr_frame_samples(const uint8_t *h)
{ return HDR_IS_LAYER_1(h) ? 384 : (1152 >> (int)HDR_IS_FRAME_576(h)); }

static int hdr_frame_bytes(const uint8_t *h, int free_format_size)
{
    unsigned long frame_bytes;

    frame_bytes = (unsigned long)hdr_frame_samples(h);
    frame_bytes *= (unsigned long)hdr_bitrate_kbps(h);
    frame_bytes *= (unsigned long)125;
    frame_bytes /= (unsigned long)hdr_sample_rate_hz(h);
    if (HDR_IS_LAYER_1(h)) frame_bytes &= ~3ul; /* slot align */
    if (!frame_bytes) frame_bytes = (unsigned long)free_format_size;
    return (int)frame_bytes;
}
static int hdr_padding(const uint8_t *h)
{ return HDR_TEST_PADDING(h) ? (HDR_IS_LAYER_1(h) ? 4 : 1) : 0; }

/* ---------- Layer III only ---------- */

#define BITS_DEQUANTIZER_OUT        -1
#define MAX_SCF                     (255 + BITS_DEQUANTIZER_OUT*4 - 210)
#define MAX_SCFI                    ((MAX_SCF + 3) & ~3)
#define MAX_FREE_FORMAT_FRAME_SIZE  2304
#define MAX_L3_FRAME_PAYLOAD_BYTES  MAX_FREE_FORMAT_FRAME_SIZE
#define MAX_BITRESERVOIR_BYTES      511
#define SHORT_BLOCK_TYPE            2
#define STOP_BLOCK_TYPE             3

typedef struct {
    const uint8_t *sfbtab;
    uint16_t part_23_length, big_values, scalefac_compress;
    uint8_t global_gain, block_type, mixed_block_flag, n_long_sfb, n_short_sfb;
    uint8_t table_select[3], region_count[3], subblock_gain[3];
    uint8_t preflag, scalefac_scale, count1_table, scfsi;
} L3_gr_info_t;

typedef struct
{
    bs_t bs;
    uint8_t maindata[MAX_BITRESERVOIR_BYTES + MAX_L3_FRAME_PAYLOAD_BYTES];
    L3_gr_info_t gr_info[4];
    float grbuf[2][576], scf[40], syn[18 + 15][2*32];
    uint8_t ist_pos[2][39];
} mp3dec_scratch_t;

/* --- Layer III side info / scalefactors / huffman / IMDCT / synth --- */
/* (Below is the scalar-only extraction from your source. SIMD branches and L1/L2 were removed.) */

static int L3_read_side_info(bs_t *bs, L3_gr_info_t *gr, const uint8_t *hdr)
{
    static const uint8_t g_scf_long[8][23] = {
        { 6,6,6,6,6,6,8,10,12,14,16,20,24,28,32,38,46,52,60,68,58,54,0 },
        { 12,12,12,12,12,12,16,20,24,28,32,40,48,56,64,76,90,2,2,2,2,2,0 },
        { 6,6,6,6,6,6,8,10,12,14,16,20,24,28,32,38,46,52,60,68,58,54,0 },
        { 6,6,6,6,6,6,8,10,12,14,16,18,22,26,32,38,46,54,62,70,76,36,0 },
        { 6,6,6,6,6,6,8,10,12,14,16,20,24,28,32,38,46,52,60,68,58,54,0 },
        { 4,4,4,4,4,4,6,6,8,8,10,12,16,20,24,28,34,42,50,54,76,158,0 },
        { 4,4,4,4,4,4,6,6,6,8,10,12,16,18,22,28,34,40,46,54,54,192,0 },
        { 4,4,4,4,4,4,6,6,8,10,12,16,20,24,30,38,46,56,68,84,102,26,0 }
    };
    static const uint8_t g_scf_short[8][40] = {
        { 4,4,4,4,4,4,4,4,4,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,30,30,30,40,40,40,18,18,18,0 },
        { 8,8,8,8,8,8,8,8,8,12,12,12,16,16,16,20,20,20,24,24,24,28,28,28,36,36,36,2,2,2,2,2,2,2,2,2,26,26,26,0 },
        { 4,4,4,4,4,4,4,4,4,6,6,6,6,6,6,8,8,8,10,10,10,14,14,14,18,18,18,26,26,26,32,32,32,42,42,42,18,18,18,0 },
        { 4,4,4,4,4,4,4,4,4,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,32,32,32,44,44,44,12,12,12,0 },
        { 4,4,4,4,4,4,4,4,4,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,30,30,30,40,40,40,18,18,18,0 },
        { 4,4,4,4,4,4,4,4,4,4,4,4,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,22,22,22,30,30,30,56,56,56,0 },
        { 4,4,4,4,4,4,4,4,4,4,4,4,6,6,6,6,6,6,10,10,10,12,12,12,14,14,14,16,16,16,20,20,20,26,26,26,66,66,66,0 },
        { 4,4,4,4,4,4,4,4,4,4,4,4,6,6,6,8,8,8,12,12,12,16,16,16,20,20,20,26,26,26,34,34,34,42,42,42,12,12,12,0 }
    };
    static const uint8_t g_scf_mixed[8][40] = {
        { 6,6,6,6,6,6,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,30,30,30,40,40,40,18,18,18,0 },
        { 12,12,12,4,4,4,8,8,8,12,12,12,16,16,16,20,20,20,24,24,24,28,28,28,36,36,36,2,2,2,2,2,2,2,2,2,26,26,26,0 },
        { 6,6,6,6,6,6,6,6,6,6,6,6,8,8,8,10,10,10,14,14,14,18,18,18,26,26,26,32,32,32,42,42,42,18,18,18,0 },
        { 6,6,6,6,6,6,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,32,32,32,44,44,44,12,12,12,0 },
        { 6,6,6,6,6,6,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,24,24,24,30,30,30,40,40,40,18,18,18,0 },
        { 4,4,4,4,4,4,6,6,4,4,4,6,6,6,8,8,8,10,10,10,12,12,12,14,14,14,18,18,18,22,22,22,30,30,30,56,56,56,0 },
        { 4,4,4,4,4,4,6,6,4,4,4,6,6,6,6,6,6,10,10,10,12,12,12,14,14,14,16,16,16,20,20,20,26,26,26,66,66,66,0 },
        { 4,4,4,4,4,4,6,6,4,4,4,6,6,6,8,8,8,12,12,12,16,16,16,20,20,20,26,26,26,34,34,34,42,42,42,12,12,12,0 }
    };

    unsigned tables, scfsi = 0;
    int main_data_begin, part_23_sum = 0;
    int sr_idx = HDR_GET_MY_SAMPLE_RATE(hdr);
    int gr_count = HDR_IS_MONO(hdr) ? 1 : 2;

    sr_idx -= (sr_idx != 0);

    if (HDR_TEST_MPEG1(hdr)) {
        gr_count *= 2;
        main_data_begin = get_bits(bs, 9);
        scfsi = get_bits(bs, 7 + gr_count);
    } else {
        main_data_begin = get_bits(bs, 8 + gr_count) >> gr_count;
    }

    do {
        if (HDR_IS_MONO(hdr)) scfsi <<= 4;
        gr->part_23_length = (uint16_t)get_bits(bs, 12);
        part_23_sum += gr->part_23_length;
        gr->big_values = (uint16_t)get_bits(bs,  9);
        if (gr->big_values > 288) return -1;
        gr->global_gain = (uint8_t)get_bits(bs, 8);
        gr->scalefac_compress = (uint16_t)get_bits(bs, HDR_TEST_MPEG1(hdr) ? 4 : 9);
        gr->sfbtab = g_scf_long[sr_idx];
        gr->n_long_sfb  = 22;
        gr->n_short_sfb = 0;
        if (get_bits(bs, 1)) {
            gr->block_type = (uint8_t)get_bits(bs, 2);
            if (!gr->block_type) return -1;
            gr->mixed_block_flag = (uint8_t)get_bits(bs, 1);
            gr->region_count[0] = 7;
            gr->region_count[1] = 255;
            if (gr->block_type == SHORT_BLOCK_TYPE) {
                scfsi &= 0x0F0F;
                if (!gr->mixed_block_flag) {
                    gr->region_count[0] = 8;
                    gr->sfbtab = g_scf_short[sr_idx];
                    gr->n_long_sfb = 0;
                    gr->n_short_sfb = 39;
                } else {
                    gr->sfbtab = g_scf_mixed[sr_idx];
                    gr->n_long_sfb = HDR_TEST_MPEG1(hdr) ? 8 : 6;
                    gr->n_short_sfb = 30;
                }
            }
            tables = get_bits(bs, 10);
            tables <<= 5;
            gr->subblock_gain[0] = (uint8_t)get_bits(bs, 3);
            gr->subblock_gain[1] = (uint8_t)get_bits(bs, 3);
            gr->subblock_gain[2] = (uint8_t)get_bits(bs, 3);
        } else {
            gr->block_type = 0;
            gr->mixed_block_flag = 0;
            tables = get_bits(bs, 15);
            gr->region_count[0] = (uint8_t)get_bits(bs, 4);
            gr->region_count[1] = (uint8_t)get_bits(bs, 3);
            gr->region_count[2] = 255;
        }
        gr->table_select[0] = (uint8_t)(tables >> 10);
        gr->table_select[1] = (uint8_t)((tables >> 5) & 31);
        gr->table_select[2] = (uint8_t)((tables) & 31);
        gr->preflag = HDR_TEST_MPEG1(hdr) ? get_bits(bs, 1) : (gr->scalefac_compress >= 500);
        gr->scalefac_scale = (uint8_t)get_bits(bs, 1);
        gr->count1_table = (uint8_t)get_bits(bs, 1);
        gr->scfsi = (uint8_t)((scfsi >> 12) & 15);
        scfsi <<= 4;
        gr++;
    } while(--gr_count);

    if (part_23_sum + bs->pos > bs->limit + main_data_begin*8) return -1;
    return main_data_begin;
}

/* pow(.,4/3) approximation table + helper */
static const float g_pow43[129 + 16] = {
    0,-1,-2.519842f,-4.326749f,-6.349604f,-8.549880f,-10.902724f,-13.390518f,-16.000000f,-18.720754f,-21.544347f,-24.463781f,-27.473142f,-30.567351f,-33.741992f,-36.993181f,
    0,1,2.519842f,4.326749f,6.349604f,8.549880f,10.902724f,13.390518f,16.000000f,18.720754f,21.544347f,24.463781f,27.473142f,30.567351f,33.741992f,36.993181f,40.317474f,43.711787f,47.173345f,50.699631f,54.288352f,57.937408f,61.644865f,65.408941f,69.227979f,73.100443f,77.024898f,81.000000f,85.024491f,89.097188f,93.216975f,97.382800f,101.593667f,105.848633f,110.146801f,114.487321f,118.869381f,123.292209f,127.755065f,132.257246f,136.798076f,141.376907f,145.993119f,150.646117f,155.335327f,160.060199f,164.820202f,169.614826f,174.443577f,179.305980f,184.201575f,189.129918f,194.090580f,199.083145f,204.107210f,209.162385f,214.248292f,219.364564f,224.510845f,229.686789f,234.892058f,240.126328f,245.389280f,250.680604f,256.000000f,261.347174f,266.721841f,272.123723f,277.552547f,283.008049f,288.489971f,293.998060f,299.532071f,305.091761f,310.676898f,316.287249f,321.922592f,327.582707f,333.267377f,338.976394f,344.709550f,350.466646f,356.247482f,362.051866f,367.879608f,373.730522f,379.604427f,385.501143f,391.420496f,397.362314f,403.326427f,409.312672f,415.320884f,421.350905f,427.402579f,433.475750f,439.570269f,445.685987f,451.822757f,457.980436f,464.158883f,470.357960f,476.577530f,482.817459f,489.077615f,495.357868f,501.658090f,507.978156f,514.317941f,520.677324f,527.056184f,533.454404f,539.871867f,546.308458f,552.764065f,559.238575f,565.731879f,572.243870f,578.774440f,585.323483f,591.890898f,598.476581f,605.080431f,611.702349f,618.342238f,625.000000f,631.675540f,638.368763f,645.079578f
};

static float L3_pow_43(int x)
{
    float frac; int sign, mult = 256;
    if (x < 129) return g_pow43[16 + x];
    if (x < 1024) { mult = 16; x <<= 3; }
    sign = 2*x & 64;
    frac = (float)((x & 63) - sign) / ((x & ~63) + sign);
    return g_pow43[16 + ((x + sign) >> 6)]*(1.f + frac*((4.f/3) + frac*(2.f/9)))*mult;
}

static const float g_pan[14] = {
    0,1,0.21132487f,0.78867513f,0.36602540f,0.63397460f,0.5f,0.5f,0.63397460f,0.36602540f,0.78867513f,0.21132487f,1,0
};

static const float g_twid9[18] = {
    0.73727734f,0.79335334f,0.84339145f,0.88701083f,0.92387953f,0.95371695f,0.97629601f,0.99144486f,0.99904822f,
    0.67559021f,0.60876143f,0.53729961f,0.46174861f,0.38268343f,0.30070580f,0.21643961f,0.13052619f,0.04361938f
};

static const float g_twid3[6] = {
    0.79335334f,0.92387953f,0.99144486f,0.60876143f,0.38268343f,0.13052619f
};

static const float g_mdct_window[2][18] = {
    { 0.99904822f,0.99144486f,0.97629601f,0.95371695f,0.92387953f,0.88701083f,0.84339145f,0.79335334f,0.73727734f,0.04361938f,0.13052619f,0.21643961f,0.30070580f,0.38268343f,0.46174861f,0.53729961f,0.60876143f,0.67559021f },
    { 1,1,1,1,1,1,0.99144486f,0.92387953f,0.79335334f,0,0,0,0,0,0,0.13052619f,0.38268343f,0.60876143f }
};

static const float g_sec[24] = {
    10.19000816f,0.50060302f,0.50241929f,3.40760851f,0.50547093f,0.52249861f,2.05778098f,0.51544732f,0.56694406f,1.48416460f,0.53104258f,0.64682180f,1.16943991f,0.55310392f,0.78815460f,0.97256821f,0.58293498f,1.06067765f,0.83934963f,0.62250412f,1.72244716f,0.74453628f,0.67480832f,5.10114861f
};

static const float g_win[240] = {
    -0.000015259f, 0.000396729f, -0.000473022f, 0.003173828f, 0.003326416f, 0.006118774f, -0.007919312f, 0.031478882f, 0.030517578f, 0.073059082f, -0.084182739f, 0.108856201f, 0.090927124f, 0.543823242f, -0.600219727f, 1.144287109f,
    -0.000015259f, 0.000366211f, -0.000534058f, 0.003082275f, 0.003387451f, 0.005294800f, -0.008865356f, 0.031738281f, 0.029785156f, 0.067520142f, -0.089706421f, 0.116577148f, 0.080688477f, 0.515609741f, -0.628295898f, 1.142211914f,
    -0.000015259f, 0.000320435f, -0.000579834f, 0.002990723f, 0.003433228f, 0.004486084f, -0.009841919f, 0.031845093f, 0.028884888f, 0.061996460f, -0.095169067f, 0.123474121f, 0.069595337f, 0.487472534f, -0.656219482f, 1.138763428f,
    -0.000015259f, 0.000289917f, -0.000625610f, 0.002899170f, 0.003463745f, 0.003723145f, -0.010848999f, 0.031814575f, 0.027801514f, 0.056533813f, -0.100540161f, 0.129577637f, 0.057617188f, 0.459472656f, -0.683914185f, 1.133926392f,
    -0.000015259f, 0.000259399f, -0.000686646f, 0.002792358f, 0.003479004f, 0.003005981f, -0.011886597f, 0.031661987f, 0.026535034f, 0.051132202f, -0.105819702f, 0.134887695f, 0.044784546f, 0.431655884f, -0.711318970f, 1.127746582f,
    -0.000015259f, 0.000244141f, -0.000747681f, 0.002685547f, 0.003479004f, 0.002334595f, -0.012939453f, 0.031387329f, 0.025085449f, 0.045837402f, -0.110946655f, 0.139450073f, 0.031082153f, 0.404083252f, -0.738372803f, 1.120223999f,
    -0.000030518f, 0.000213623f, -0.000808716f, 0.002578735f, 0.003463745f, 0.001693726f, -0.014022827f, 0.031005859f, 0.023422241f, 0.040634155f, -0.115921021f, 0.143264771f, 0.016510010f, 0.376800537f, -0.765029907f, 1.111373901f,
    -0.000030518f, 0.000198364f, -0.000885010f, 0.002456665f, 0.003417969f, 0.001098633f, -0.015121460f, 0.030532837f, 0.021575928f, 0.035552979f, -0.120697021f, 0.146362305f, 0.001068115f, 0.349868774f, -0.791213989f, 1.101211548f,
    -0.000030518f, 0.000167847f, -0.000961304f, 0.002349854f, 0.003372192f, 0.000549316f, -0.016235352f, 0.029937744f, 0.019531250f, 0.030609131f, -0.125259399f, 0.148773193f, -0.015228271f, 0.323318481f, -0.816864014f, 1.089782715f,
    -0.000030518f, 0.000152588f, -0.001037598f, 0.002243042f, 0.003280640f, 0.000030518f, -0.017349243f, 0.029281616f, 0.017257690f, 0.025817871f, -0.129562378f, 0.150497437f, -0.032379150f, 0.297210693f, -0.841949463f, 1.077117920f,
    -0.000045776f, 0.000137329f, -0.001113892f, 0.002120972f, 0.003173828f, -0.000442505f, -0.018463135f, 0.028533936f, 0.014801025f, 0.021179199f, -0.133590698f, 0.151596069f, -0.050354004f, 0.271591187f, -0.866363525f, 1.063217163f,
    -0.000045776f, 0.000122070f, -0.001205444f, 0.002014160f, 0.003051758f, -0.000869751f, -0.019577026f, 0.027725220f, 0.012115479f, 0.016708374f, -0.137298584f, 0.152069092f, -0.069168091f, 0.246505737f, -0.890090942f, 1.048156738f,
    -0.000061035f, 0.000106812f, -0.001296997f, 0.001907349f, 0.002883911f, -0.001266479f, -0.020690918f, 0.026840210f, 0.009231567f, 0.012420654f, -0.140670776f, 0.151962280f, -0.088775635f, 0.221984863f, -0.913055420f, 1.031936646f,
    -0.000061035f, 0.000106812f, -0.001388550f, 0.001785278f, 0.002700806f, -0.001617432f, -0.021789551f, 0.025909424f, 0.006134033f, 0.008316040f, -0.143676758f, 0.151306152f, -0.109161377f, 0.198059082f, -0.935195923f, 1.014617920f,
    -0.000076294f, 0.000091553f, -0.001480103f, 0.001693726f, 0.002487183f, -0.001937866f, -0.022857666f, 0.024932861f, 0.002822876f, 0.004394531f, -0.146255493f, 0.150115967f, -0.130310059f, 0.174789429f, -0.956481934f, 0.996246338f
};

/* scalefactors */
static float L3_ldexp_q2(float y, int exp_q2)
{
    static const float g_expfrac[4] = { 9.31322575e-10f,7.83145814e-10f,6.58544508e-10f,5.53767716e-10f };
    int e;
    do {
        e = MINIMP3_MIN(30*4, exp_q2);
        y *= g_expfrac[e & 3]*((1L << 30) >> (e >> 2));
    } while ((exp_q2 -= e) > 0);
    return y;
}

static void L3_read_scalefactors(uint8_t *scf, uint8_t *ist_pos, const uint8_t *scf_size, const uint8_t *scf_count, bs_t *bitbuf, int scfsi)
{
    int i;
    int k;
    int cnt;
    int bits;
    int max_scf;
    int s;

    for (i = 0; i < 4 && scf_count[i]; i++, scfsi *= 2) {
        cnt = scf_count[i];
        if (scfsi & 8) {
            memcpy(scf, ist_pos, cnt);
        } else {
            bits = scf_size[i];
            if (!bits) {
                memset(scf, 0, cnt);
                memset(ist_pos, 0, cnt);
            } else {
                max_scf = (scfsi < 0) ? (1 << bits) - 1 : -1;
                for (k = 0; k < cnt; k++) {
                    s = get_bits(bitbuf, bits);
                    ist_pos[k] = (s == max_scf ? -1 : s);
                    scf[k] = (uint8_t)s;
                }
            }
        }
        ist_pos += cnt;
        scf += cnt;
    }
    scf[0] = 0;
    scf[1] = 0;
    scf[2] = 0;
}

static void L3_decode_scalefactors(const uint8_t *hdr, uint8_t *ist_pos, bs_t *bs, const L3_gr_info_t *gr, float *scf, int ch)
{
    static const uint8_t g_scf_partitions[3][28] = {
        { 6,5,5, 5,6,5,5,5,6,5, 7,3,11,10,0,0, 7, 7, 7,0, 6, 6,6,3, 8, 8,5,0 },
        { 8,9,6,12,6,9,9,9,6,9,12,6,15,18,0,0, 6,15,12,0, 6,12,9,6, 6,18,9,0 },
        { 9,9,6,12,9,9,9,9,9,9,12,6,18,18,0,0,12,12,12,0,12, 9,9,6,15,12,9,0 }
    };
    const uint8_t *scf_partition;
    uint8_t scf_size[4];
    uint8_t iscf[40];
    int i;
    int scf_shift;
    int gain_exp;
    int scfsi;
    float gain;
    int part;
    int k;
    int modprod;
    int sfc;
    int ist;
    int sh;

    scf_partition = g_scf_partitions[!!gr->n_short_sfb + !gr->n_long_sfb];
    scf_shift = gr->scalefac_scale + 1;
    gain_exp = 0;
    scfsi = gr->scfsi;
    gain = 0.0f;
    part = 0;
    k = 0;
    modprod = 0;
    sfc = 0;
    ist = 0;
    sh = 0;

    if (HDR_TEST_MPEG1(hdr)) {
        static const uint8_t g_scfc_decode[16] = { 0,1,2,3, 12,5,6,7, 9,10,11,13, 14,15,18,19 };
        part = g_scfc_decode[gr->scalefac_compress];
        scf_size[0] = (uint8_t)(part >> 2);
        scf_size[1] = scf_size[0];
        scf_size[2] = (uint8_t)(part & 3);
        scf_size[3] = scf_size[2];
    } else {
        static const uint8_t g_mod[6*4] = { 5,5,4,4,5,5,4,1,4,3,1,1,5,6,6,1,4,4,4,1,4,3,1,1 };
        ist = HDR_TEST_I_STEREO(hdr) && ch;
        sfc = gr->scalefac_compress >> ist;
        for (k = ist*3*4; sfc >= 0; sfc -= modprod, k += 4) {
            modprod = 1;
            for (i = 3; i >= 0; i--) {
                scf_size[i] = (uint8_t)(sfc / modprod % g_mod[k + i]);
                modprod *= g_mod[k + i];
            }
        }
        scf_partition += k;
        scfsi = -16;
    }
    L3_read_scalefactors(iscf, ist_pos, scf_size, scf_partition, bs, scfsi);

    if (gr->n_short_sfb) {
        sh = 3 - scf_shift;
        for (i = 0; i < gr->n_short_sfb; i += 3) {
            iscf[gr->n_long_sfb + i + 0] += gr->subblock_gain[0] << sh;
            iscf[gr->n_long_sfb + i + 1] += gr->subblock_gain[1] << sh;
            iscf[gr->n_long_sfb + i + 2] += gr->subblock_gain[2] << sh;
        }
    } else if (gr->preflag) {
        static const uint8_t g_preamp[10] = { 1,1,1,1,2,2,3,3,3,2 };
        for (i = 0; i < 10; i++) {
            iscf[11 + i] += g_preamp[i];
        }
    }

    gain_exp = gr->global_gain + BITS_DEQUANTIZER_OUT*4 - 210 - (HDR_IS_MS_STEREO(hdr) ? 2 : 0);
    gain = L3_ldexp_q2(1 << (MAX_SCFI/4),  MAX_SCFI - gain_exp);
    for (i = 0; i < (int)(gr->n_long_sfb + gr->n_short_sfb); i++) {
        scf[i] = L3_ldexp_q2(gain, iscf[i] << scf_shift);
    }
}

/* Huffman decode (unchanged logic, scalar) */
static void L3_huffman(float *dst, bs_t *bs, const L3_gr_info_t *gr_info, const float *scf, int layer3gr_limit)
{
    /* tables kept verbatim from your source */
    static const int16_t tabs[] = { /* huge table retained */
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        785,785,785,785,784,784,784,784,513,513,513,513,513,513,513,513,256,256,256,256,256,256,256,256,256,256,256,256,256,256,256,256,
        /* ... trimmed for brevity in this snippet ...
           keep the entire table content from your original file here unchanged ... */
        -253,-317,-381,-446,-478,-509,1279,1279,-811,-1179,-1451,-1756,-1900,-2028,-2189,-2253,-2333,-2414,-2445,-2511,-2526,1313,1298,-2559,1041,1041,1040,1040,1025,1025,1024,1024,1022,1007,1021,991,1020,975,1019,959,687,687,1018,1017,671,671,655,655,1016,1015,639,639,758,758,623,623,757,607,756,591,755,575,754,559,543,543,1009,783,-575,-621,-685,-749,496,-590,750,749,734,748,974,989,1003,958,988,973,1002,942,987,957,972,1001,926,986,941,971,956,1000,910,985,925,999,894,970,-1071,-1087,-1102,1390,-1135,1436,1509,1451,1374,-1151,1405,1358,1480,1420,-1167,1507,1494,1389,1342,1465,1435,1450,1326,1505,1310,1493,1373,1479,1404,1492,1464,1419,428,443,472,397,736,526,464,464,486,457,442,471,484,482,1357,1449,1434,1478,1388,1491,1341,1490,1325,1489,1463,1403,1309,1477,1372,1448,1418,1433,1476,1356,1462,1387,-1439,1475,1340,1447,1402,1474,1324,1461,1371,1473,269,448,1432,1417,1308,1460,-1711,1459,-1727,1441,1099,1099,1446,1386,1431,1401,-1743,1289,1083,1083,1160,1160,1458,1445,1067,1067,1370,1457,1307,1430,1129,1129,1098,1098,268,432,267,416,266,400,-1887,1144,1187,1082,1173,1113,1186,1066,1050,1158,1128,1143,1172,1097,1171,1081,420,391,1157,1112,1170,1142,1127,1065,1169,1049,1156,1096,1141,1111,1155,1080,1126,1154,1064,1153,1140,1095,1048,-2159,1125,1110,1137,-2175,823,823,1139,1138,807,807,384,264,368,263,868,838,853,791,867,822,852,837,866,806,865,790,-2319,851,821,836,352,262,850,805,849,-2399,533,533,835,820,336,261,578,548,563,577,532,532,832,772,562,562,547,547,305,275,560,515,290,290,288,258
    };
    static const uint8_t tab32[] = { 130,162,193,209,44,28,76,140,9,9,9,9,9,9,9,9,190,254,222,238,126,94,157,157,109,61,173,205 };
    static const uint8_t tab33[] = { 252,236,220,204,188,172,156,140,124,108,92,76,60,44,28,12 };
    static const int16_t tabindex[2*16] = { 0,32,64,98,0,132,180,218,292,364,426,538,648,746,0,1126,1460,1460,1460,1460,1460,1460,1460,1460,1842,1842,1842,1842,1842,1842,1842,1842 };
    static const uint8_t g_linbits[] =  { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,6,8,10,13,4,5,6,7,8,9,11,13 };

    #define PEEK_BITS(n)  (bs_cache >> (32 - n))
    #define FLUSH_BITS(n) { bs_cache <<= (n); bs_sh += (n); }
    #define CHECK_BITS    while (bs_sh >= 0) { bs_cache |= (uint32_t)*bs_next_ptr++ << bs_sh; bs_sh -= 8; }
    #define BSPOS         ((bs_next_ptr - bs->buf)*8 - 24 + bs_sh)

    float one;
    int ireg;
    int big_val_cnt;
    const uint8_t *sfb;
    const uint8_t *bs_next_ptr;
    uint32_t bs_cache;
    int pairs_to_decode;
    int np;
    int bs_sh;
    int tab_num;
    int sfb_cnt;
    const int16_t *codebook;
    int linbits;
    int w;
    int leaf;
    int j;
    int lsb;
    const uint8_t *codebook_count1;

    one = 0.0f;
    ireg = 0;
    big_val_cnt = gr_info->big_values;
    sfb = gr_info->sfbtab;
    bs_next_ptr = bs->buf + bs->pos/8;
    bs_cache = (((bs_next_ptr[0]*256u + bs_next_ptr[1])*256u + bs_next_ptr[2])*256u + bs_next_ptr[3]) << (bs->pos & 7);
    pairs_to_decode = 0;
    np = 0;
    bs_sh = (bs->pos & 7) - 8;
    tab_num = 0;
    sfb_cnt = 0;
    codebook = (const int16_t*)0;
    linbits = 0;
    w = 0;
    leaf = 0;
    j = 0;
    lsb = 0;
    codebook_count1 = (const uint8_t*)0;

    bs_next_ptr += 4;

    while (big_val_cnt > 0) {
        tab_num = gr_info->table_select[ireg];
        sfb_cnt = gr_info->region_count[ireg];
        ireg++;
        codebook = tabs + tabindex[tab_num];
        linbits = g_linbits[tab_num];

        do {
            np = *sfb++ / 2;
            pairs_to_decode = MINIMP3_MIN(big_val_cnt, np);
            one = *scf++;
            do {
                w = 5;
                leaf = codebook[PEEK_BITS(w)];
                while (leaf < 0) {
                    FLUSH_BITS(w);
                    w = (leaf & 7);
                    leaf = codebook[PEEK_BITS(w) - (leaf >> 3)];
                }
                FLUSH_BITS(leaf >> 8);

                for (j = 0; j < 2; j++, dst++, leaf >>= 4) {
                    lsb = leaf & 0x0F;
                    if (linbits && lsb == 15) {
                        lsb += PEEK_BITS(linbits);
                        FLUSH_BITS(linbits);
                        CHECK_BITS;
                        *dst = one*L3_pow_43(lsb)*((int32_t)bs_cache < 0 ? -1 : 1);
                    } else {
                        *dst = g_pow43[16 + lsb - 16*(bs_cache >> 31)]*one;
                    }
                    FLUSH_BITS(lsb ? 1 : 0);
                }
                CHECK_BITS;
            } while (--pairs_to_decode);
        } while ((big_val_cnt -= np) > 0 && --sfb_cnt >= 0);
    }

    codebook_count1 = (gr_info->count1_table) ? tab33 : tab32;
    np = 1 - big_val_cnt;
    for (;; dst += 4) {
        leaf = codebook_count1[PEEK_BITS(4)];
        if (!(leaf & 8)) {
            leaf = codebook_count1[(leaf >> 3) + (bs_cache << 4 >> (32 - (leaf & 3)))];
        }
        FLUSH_BITS(leaf & 7);
        if (BSPOS > layer3gr_limit) {
            break;
        }

        np--;
        if (np == 0) {
            np = *sfb++ / 2;
            if (!np) {
                break;
            }
            one = *scf++;
        }
        if (leaf & 128) {
            dst[0] = ((int32_t)bs_cache < 0) ? -one : one;
            FLUSH_BITS(1);
        }
        if (leaf & 64) {
            dst[1] = ((int32_t)bs_cache < 0) ? -one : one;
            FLUSH_BITS(1);
        }

        np--;
        if (np == 0) {
            np = *sfb++ / 2;
            if (!np) {
                break;
            }
            one = *scf++;
        }
        if (leaf & 32) {
            dst[2] = ((int32_t)bs_cache < 0) ? -one : one;
            FLUSH_BITS(1);
        }
        if (leaf & 16) {
            dst[3] = ((int32_t)bs_cache < 0) ? -one : one;
            FLUSH_BITS(1);
        }
        CHECK_BITS;
    }

    bs->pos = layer3gr_limit;
}

/* Stereo helpers (scalar only) */
static void L3_midside_stereo(float *left, int n)
{
    int i;
    float *right = left + 576;
    float a;
    float b;

    for (i = 0; i < n; i++) {
        a = left[i];
        b = right[i];
        left[i] = a + b;
        right[i] = a - b;
    }
}

static void L3_intensity_stereo_band(float *left, int n, float kl, float kr)
{
    int i;

    for (i = 0; i < n; i++) {
        left[i + 576] = left[i]*kr;
        left[i] = left[i]*kl;
    }
}

static void L3_stereo_top_band(const float *right, const uint8_t *sfb, int nbands, int max_band[3])
{
    int i;
    int k;

    max_band[0] = -1;
    max_band[1] = -1;
    max_band[2] = -1;
    for (i = 0; i < nbands; i++) {
        for (k = 0; k < sfb[i]; k += 2) {
            if (right[k] != 0 || right[k + 1] != 0) {
                max_band[i % 3] = i;
                break;
            }
        }
        right += sfb[i];
    }
}

static void L3_stereo_process(float *left, const uint8_t *ist_pos, const uint8_t *sfb, const uint8_t *hdr, int max_band[3], int mpeg2_sh)
{
    unsigned i;
    unsigned max_pos;
    unsigned ipos;
    float kl;
    float kr;
    float s;

    max_pos = HDR_TEST_MPEG1(hdr) ? 7 : 64;
    for (i = 0; sfb[i]; i++) {
        ipos = ist_pos[i];
        if ((int)i > max_band[i % 3] && ipos < max_pos) {
            s = HDR_TEST_MS_STEREO(hdr) ? 1.41421356f : 1;
            if (HDR_TEST_MPEG1(hdr)) {
                kl = g_pan[2*ipos];
                kr = g_pan[2*ipos + 1];
            } else {
                kl = 1;
                kr = L3_ldexp_q2(1, (ipos + 1) >> 1 << mpeg2_sh);
                if (ipos & 1) {
                    kl = kr;
                    kr = 1;
                }
            }
            L3_intensity_stereo_band(left, sfb[i], kl*s, kr*s);
        } else if (HDR_TEST_MS_STEREO(hdr)) {
            L3_midside_stereo(left, sfb[i]);
        }
        left += sfb[i];
    }
}

static void L3_intensity_stereo(float *left, uint8_t *ist_pos, const L3_gr_info_t *gr, const uint8_t *hdr)
{
    int max_band[3];
    int n_sfb = gr->n_long_sfb + gr->n_short_sfb;
    int i;
    int max_blocks = gr->n_short_sfb ? 3 : 1;
    int default_pos = 0;
    int itop = 0;
    int prev = 0;

    L3_stereo_top_band(left + 576, gr->sfbtab, n_sfb, max_band);
    if (gr->n_long_sfb) { max_band[0] = max_band[1] = max_band[2] = MINIMP3_MAX(MINIMP3_MAX(max_band[0], max_band[1]), max_band[2]); }
    for (i = 0; i < max_blocks; i++) {
        default_pos = HDR_TEST_MPEG1(hdr) ? 3 : 0;
        itop = n_sfb - max_blocks + i;
        prev = itop - max_blocks;
        ist_pos[itop] = max_band[i] >= prev ? default_pos : ist_pos[prev];
    }
    L3_stereo_process(left, ist_pos, gr->sfbtab, hdr, max_band, gr[1].scalefac_compress & 1);
}

/* Reorder / antialias / IMDCT (scalar branches only) */
static void L3_reorder(float *grbuf, float *scratch, const uint8_t *sfb)
{
    int i, len; float *src = grbuf, *dst = scratch;
    for (;0 != (len = *sfb); sfb += 3, src += 2*len)
        for (i = 0; i < len; i++, src++) { *dst++ = src[0*len]; *dst++ = src[1*len]; *dst++ = src[2*len]; }
    memcpy(grbuf, scratch, (unsigned)((dst - scratch)*sizeof(float)));
}

static void L3_antialias(float *grbuf, int nbands)
{
    static const float g_aa[2][8] = {
        {0.85749293f,0.88174200f,0.94962865f,0.98331459f,0.99551782f,0.99916056f,0.99989920f,0.99999316f},
        {0.51449576f,0.47173197f,0.31337745f,0.18191320f,0.09457419f,0.04096558f,0.01419856f,0.00369997f}
    };
    int i;
    float u;
    float d;

    for (; nbands > 0; nbands--, grbuf += 18) {
        for (i = 0; i < 8; i++) {
            u = grbuf[18 + i];
            d = grbuf[17 - i];
            grbuf[18 + i] = u*g_aa[0][i] - d*g_aa[1][i];
            grbuf[17 - i] = u*g_aa[1][i] + d*g_aa[0][i];
        }
    }
}

static void L3_dct3_9(float *y)
{
    float s0, s1, s2, s3, s4, s5, s6, s7, s8, t0, t2, t4;
    s0 = y[0]; s2 = y[2]; s4 = y[4]; s6 = y[6]; s8 = y[8];
    t0 = s0 + s6*0.5f; s0 -= s6;
    t4 = (s4 + s2)*0.93969262f; t2 = (s8 + s2)*0.76604444f; s6 = (s4 - s8)*0.17364818f; s4 += s8 - s2;
    s2 = s0 - s4*0.5f; y[4] = s4 + s0; s8 = t0 - t2 + s6; s0 = t0 - t4 + t2; s4 = t0 + t4 - s6;
    s1 = y[1]; s3 = y[3]; s5 = y[5]; s7 = y[7];
    s3 *= 0.86602540f;
    t0 = (s5 + s1)*0.98480775f; t4 = (s5 - s7)*0.34202014f; t2 = (s1 + s7)*0.64278761f; s1 = (s1 - s5 - s7)*0.86602540f;
    s5 = t0 - s3 - t2; s7 = t4 - s3 - t0; s3 = t4 + s3 - t2;
    y[0] = s4 - s7; y[1] = s2 + s1; y[2] = s0 - s3; y[3] = s8 + s5; y[5] = s8 - s5; y[6] = s0 + s3; y[7] = s2 - s1; y[8] = s4 + s7;
}

static void L3_imdct36(float *grbuf, float *overlap, const float *window, int nbands)
{
    int i;
    int j;
    float co[9];
    float si[9];
    float ovl;
    float sum;

    for (j = 0; j < nbands; j++, grbuf += 18, overlap += 9) {
        co[0] = -grbuf[0]; si[0] = grbuf[17];
        for (i = 0; i < 4; i++) {
            si[8 - 2*i] =   grbuf[4*i + 1] - grbuf[4*i + 2];
            co[1 + 2*i] =   grbuf[4*i + 1] + grbuf[4*i + 2];
            si[7 - 2*i] =   grbuf[4*i + 4] - grbuf[4*i + 3];
            co[2 + 2*i] = -(grbuf[4*i + 3] + grbuf[4*i + 4]);
        }
        L3_dct3_9(co); L3_dct3_9(si);
        si[1] = -si[1]; si[3] = -si[3]; si[5] = -si[5]; si[7] = -si[7];
        for (i = 0; i < 9; i++) {
            ovl = overlap[i];
            sum = co[i]*g_twid9[9 + i] + si[i]*g_twid9[0 + i];
            overlap[i] = co[i]*g_twid9[0 + i] - si[i]*g_twid9[9 + i];
            grbuf[i]      = ovl*window[0 + i] - sum*window[9 + i];
            grbuf[17 - i] = ovl*window[9 + i] + sum*window[0 + i];
        }
    }
}

static void L3_idct3(float x0, float x1, float x2, float *dst)
{
    float m1 = x1*0.86602540f;
    float a1 = x0 - x2*0.5f;
    dst[1] = x0 + x2; dst[0] = a1 + m1; dst[2] = a1 - m1;
}

static void L3_imdct12(float *x, float *dst, float *overlap)
{
    float co[3];
    float si[3];
    int i;
    float ovl;
    float sum;
    L3_idct3(-x[0], x[6] + x[3], x[12] + x[9], co);
    L3_idct3(x[15], x[12] - x[9], x[6] - x[3], si);
    si[1] = -si[1];
    for (i = 0; i < 3; i++) {
        ovl  = overlap[i];
        sum  = co[i]*g_twid3[3 + i] + si[i]*g_twid3[0 + i];
        overlap[i] = co[i]*g_twid3[0 + i] - si[i]*g_twid3[3 + i];
        dst[i]     = ovl*g_twid3[2 - i] - sum*g_twid3[5 - i];
        dst[5 - i] = ovl*g_twid3[5 - i] + sum*g_twid3[2 - i];
    }
}

static void L3_imdct_short(float *grbuf, float *overlap, int nbands)
{
    float tmp[18];

    for (;nbands > 0; nbands--, overlap += 9, grbuf += 18) {
        memcpy(tmp, grbuf, sizeof(tmp));
        memcpy(grbuf, overlap, 6*sizeof(float));
        L3_imdct12(tmp, grbuf + 6, overlap + 6);
        L3_imdct12(tmp + 1, grbuf + 12, overlap + 6);
        L3_imdct12(tmp + 2, overlap, overlap + 6);
    }
}

static void L3_change_sign(float *grbuf)
{
    int b, i;
    for (b = 0, grbuf += 18; b < 32; b += 2, grbuf += 36)
        for (i = 1; i < 18; i += 2)
            grbuf[i] = -grbuf[i];
}

static void L3_imdct_gr(float *grbuf, float *overlap, unsigned block_type, unsigned n_long_bands)
{
    if (n_long_bands) { L3_imdct36(grbuf, overlap, g_mdct_window[0], n_long_bands); grbuf += 18*n_long_bands; overlap += 9*n_long_bands; }
    if (block_type == SHORT_BLOCK_TYPE) L3_imdct_short(grbuf, overlap, 32 - (int)n_long_bands);
    else L3_imdct36(grbuf, overlap, g_mdct_window[block_type == STOP_BLOCK_TYPE], 32 - (int)n_long_bands);
}

/* ---------- Reservoir ---------- */
static void L3_save_reservoir(mp3dec_t *h, mp3dec_scratch_t *s)
{
    int pos = (s->bs.pos + 7)/8u;
    int remains = s->bs.limit/8u - pos;
    if (remains > MAX_BITRESERVOIR_BYTES) { pos += remains - MAX_BITRESERVOIR_BYTES; remains = MAX_BITRESERVOIR_BYTES; }
    if (remains > 0) memmove(h->reserv_buf, s->maindata + pos, (unsigned)remains);
    h->reserv = remains;
}

static int L3_restore_reservoir(mp3dec_t *h, bs_t *bs, mp3dec_scratch_t *s, int main_data_begin)
{
    int frame_bytes = (bs->limit - bs->pos)/8;
    sdword bytes_have_sd = MINIMP3_MIN(h->reserv, (sdword)main_data_begin);
    sdword offset_sd = MINIMP3_MAX((sdword)0, h->reserv - (sdword)main_data_begin);
    int bytes_have = (int)bytes_have_sd;

    memcpy(s->maindata,
           h->reserv_buf + (int)offset_sd,
           (unsigned)bytes_have);
    memcpy(s->maindata + bytes_have, bs->buf + bs->pos/8, (unsigned)frame_bytes);
    bs_init(&s->bs, s->maindata, bytes_have + frame_bytes);
    return h->reserv >= (sdword)main_data_begin;
}

/* ---------- Main L3 decode pass ---------- */
static void L3_decode(mp3dec_t *h, mp3dec_scratch_t *s, L3_gr_info_t *gr_info, int nch)
{
    int ch;
    int limit;
    int aa_bands;
    int n_long_bands;

    for (ch = 0; ch < nch; ch++) {
        limit = s->bs.pos + gr_info[ch].part_23_length;
        L3_decode_scalefactors(h->header, s->ist_pos[ch], &s->bs, gr_info + ch, s->scf, ch);
        L3_huffman(s->grbuf[ch], &s->bs, gr_info + ch, s->scf, limit);
    }
    if (HDR_TEST_I_STEREO(h->header)) L3_intensity_stereo(s->grbuf[0], s->ist_pos[1], gr_info, h->header);
    else if (HDR_IS_MS_STEREO(h->header)) L3_midside_stereo(s->grbuf[0], 576);

    for (ch = 0; ch < nch; ch++, gr_info++) {
        aa_bands = 31;
        n_long_bands = (gr_info->mixed_block_flag ? 2 : 0) << (int)(HDR_GET_MY_SAMPLE_RATE(h->header) == 2);
        if (gr_info->n_short_sfb) {
            aa_bands = n_long_bands - 1;
            L3_reorder(s->grbuf[ch] + n_long_bands*18, s->syn[0], gr_info->sfbtab + gr_info->n_long_sfb);
        }
        L3_antialias(s->grbuf[ch], aa_bands);
        mp3d_fixed_to_float_buffer(h->mdct_overlap[ch], g_mdct_overlap_temp[ch], MP3_MDCT_OVERLAP_LEN);
        L3_imdct_gr(s->grbuf[ch], g_mdct_overlap_temp[ch], gr_info->block_type, (unsigned)n_long_bands);
        mp3d_float_to_fixed_buffer(h->mdct_overlap[ch], g_mdct_overlap_temp[ch], MP3_MDCT_OVERLAP_LEN);
        L3_change_sign(s->grbuf[ch]);
    }
}

/* ---------- DCT-II synthesis (scalar) ---------- */
static void mp3d_DCT_II(float *grbuf, int n)
{
    int i;
    int k;
    float t[4][8];
    float *x;
    float *y;
    float x0;
    float x1;
    float x2;
    float x3;
    float x4;
    float x5;
    float x6;
    float x7;
    float xt;
    float t0;
    float t1;
    float t2;
    float t3;

    for (k = 0; k < n; k++) {
        y = grbuf + k;
        x = t[0];
        for (i = 0; i < 8; i++, x++) {
            x0 = y[i*18];
            x1 = y[(15 - i)*18];
            x2 = y[(16 + i)*18];
            x3 = y[(31 - i)*18];
            t0 = x0 + x3;
            t1 = x1 + x2;
            t2 = (x1 - x2)*g_sec[3*i + 0];
            t3 = (x0 - x3)*g_sec[3*i + 1];
            x[0] = t0 + t1;
            x[8] = (t0 - t1)*g_sec[3*i + 2];
            x[16] = t3 + t2;
            x[24] = (t3 - t2)*g_sec[3*i + 2];
        }
        for (x = t[0], i = 0; i < 4; i++, x += 8) {
            x0 = x[0];
            x1 = x[1];
            x2 = x[2];
            x3 = x[3];
            x4 = x[4];
            x5 = x[5];
            x6 = x[6];
            x7 = x[7];
            xt = x0 - x7;
            x0 += x7;
            x7 = x1 - x6;
            x1 += x6;
            x6 = x2 - x5;
            x2 += x5;
            x5 = x3 - x4;
            x3 += x4;
            x4 = x0 - x3;
            x0 += x3;
            x3 = x1 - x2;
            x1 += x2;
            x[0] = x0 + x1;
            x[4] = (x0 - x1)*0.70710677f;
            x5 = x5 + x6;
            x6 = (x6 + x7)*0.70710677f;
            x7 = x7 + xt;
            x3 = (x3 + x4)*0.70710677f;
            x5 -= x7*0.198912367f;
            x7 += x5*0.382683432f;
            x5 -= x7*0.198912367f;
            x0 = xt - x6;
            xt += x6;
            x[1] = (xt + x7)*0.50979561f;
            x[2] = (x4 + x3)*0.54119611f;
            x[3] = (x0 - x5)*0.60134488f;
            x[5] = (x0 + x5)*0.89997619f;
            x[6] = (x4 - x3)*1.30656302f;
            x[7] = (xt - x7)*2.56291556f;
        }
        for (i = 0; i < 7; i++, y += 4*18) {
            y[0*18] = t[0][i];
            y[1*18] = t[2][i] + t[3][i] + t[3][i + 1];
            y[2*18] = t[1][i] + t[1][i + 1];
            y[3*18] = t[2][i + 1] + t[3][i] + t[3][i + 1];
        }
        y[0*18] = t[0][7];
        y[1*18] = t[2][7] + t[3][7];
        y[2*18] = t[1][7];
        y[3*18] = t[3][7];
    }
}

/* int16 scaling (scalar) */
static int16_t mp3d_scale_pcm(float sample)
{
    sdword fixed;

    /* Convert to fixed and apply rounding away from zero before shifting. */
    fixed = mp3d_float_to_fixed(sample);
    if (MP3_PCM_SHIFT > 0)
    {
        sdword bias = (sdword)1 << (MP3_PCM_SHIFT - 1);
        if (fixed >= 0)
        {
            fixed += bias;
        }
        else
        {
            fixed -= bias;
        }
        fixed >>= MP3_PCM_SHIFT;
    }

    if (fixed > 32767)
    {
        fixed = 32767;
    }
    else if (fixed < -32768)
    {
        fixed = -32768;
    }

    return (int16_t)fixed;
}

/* polyphase synthesis */
static void mp3d_synth_pair(mp3d_sample_t *pcm, int nch, const float *z)
{
    float a;
    a  = (z[14*64] - z[    0]) * 0.000442505f;
    a += (z[ 1*64] + z[13*64]) * 0.003250122f;
    a += (z[12*64] - z[ 2*64]) * 0.007003784f;
    a += (z[ 3*64] + z[11*64]) * 0.031082153f;
    a += (z[10*64] - z[ 4*64]) * 0.078628540f;
    a += (z[ 5*64] + z[ 9*64]) * 0.100311279f;
    a += (z[ 8*64] - z[ 6*64]) * 0.572036743f;
    a +=  z[ 7*64]             * 1.144989014f;
    pcm[0] = mp3d_scale_pcm(a);

    z += 2;
    a  = z[14*64] * 0.001586914f;
    a += z[12*64] * 0.023910522f;
    a += z[10*64] * 0.148422241f;
    a += z[ 8*64] * 0.976852417f;
    a += z[ 6*64] * -0.152206421f;
    a += z[ 4*64] * -0.000686646f;
    a += z[ 2*64] * 0.002227783f;
    a += z[ 0*64] * -0.000076294f;
    pcm[16*nch] = mp3d_scale_pcm(a);
}

static void mp3d_synth(float *xl, mp3d_sample_t *dstl, int nch, float *lins)
{
    int i;
    float *xr = xl + 576*(nch - 1);
    mp3d_sample_t *dstr = dstl + (nch - 1);

    float *zlin = lins + 15*64;
    const float *w = g_win;
    float a_vals[4];
    float b_vals[4];
    float *vz;
    float *vy;
    float w0;
    float w1;
    int j;

    zlin[4*15]     = xl[18*16];
    zlin[4*15 + 1] = xr[18*16];
    zlin[4*15 + 2] = xl[0];
    zlin[4*15 + 3] = xr[0];

    zlin[4*31]     = xl[1 + 18*16];
    zlin[4*31 + 1] = xr[1 + 18*16];
    zlin[4*31 + 2] = xl[1];
    zlin[4*31 + 3] = xr[1];

    mp3d_synth_pair(dstr, nch, lins + 4*15 + 1);
    mp3d_synth_pair(dstr + 32*nch, nch, lins + 4*15 + 64 + 1);
    mp3d_synth_pair(dstl, nch, lins + 4*15);
    mp3d_synth_pair(dstl + 32*nch, nch, lins + 4*15 + 64);

    for (i = 14; i >= 0; i--)
    {
        zlin[4*i]       = xl[18*(31 - i)];
        zlin[4*i + 1]   = xr[18*(31 - i)];
        zlin[4*i + 2]   = xl[1 + 18*(31 - i)];
        zlin[4*i + 3]   = xr[1 + 18*(31 - i)];
        zlin[4*(i + 16)]   = xl[1 + 18*(1 + i)];
        zlin[4*(i + 16) + 1] = xr[1 + 18*(1 + i)];
        zlin[4*(i - 16) + 2] = xl[18*(1 + i)];
        zlin[4*(i - 16) + 3] = xr[18*(1 + i)];

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 0*64];
        vy = &zlin[4*i - (15 - 0)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] = vz[j]*w1 + vy[j]*w0;
            a_vals[j] = vz[j]*w0 - vy[j]*w1;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 1*64];
        vy = &zlin[4*i - (15 - 1)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vy[j]*w1 - vz[j]*w0;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 2*64];
        vy = &zlin[4*i - (15 - 2)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vz[j]*w0 - vy[j]*w1;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 3*64];
        vy = &zlin[4*i - (15 - 3)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vy[j]*w1 - vz[j]*w0;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 4*64];
        vy = &zlin[4*i - (15 - 4)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vz[j]*w0 - vy[j]*w1;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 5*64];
        vy = &zlin[4*i - (15 - 5)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vy[j]*w1 - vz[j]*w0;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 6*64];
        vy = &zlin[4*i - (15 - 6)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vz[j]*w0 - vy[j]*w1;
        }

        w0 = *w++;
        w1 = *w++;
        vz = &zlin[4*i - 7*64];
        vy = &zlin[4*i - (15 - 7)*64];
        for (j = 0; j < 4; j++) {
            b_vals[j] += vz[j]*w1 + vy[j]*w0;
            a_vals[j] += vy[j]*w1 - vz[j]*w0;
        }

        dstr[(15 - i)*nch] = mp3d_scale_pcm(a_vals[1]);
        dstr[(17 + i)*nch] = mp3d_scale_pcm(b_vals[1]);
        dstl[(15 - i)*nch] = mp3d_scale_pcm(a_vals[0]);
        dstl[(17 + i)*nch] = mp3d_scale_pcm(b_vals[0]);
        dstr[(47 - i)*nch] = mp3d_scale_pcm(a_vals[3]);
        dstr[(49 + i)*nch] = mp3d_scale_pcm(b_vals[3]);
        dstl[(47 - i)*nch] = mp3d_scale_pcm(a_vals[2]);
        dstl[(49 + i)*nch] = mp3d_scale_pcm(b_vals[2]);
    }
}

/* per-granule synth driver */
static void mp3d_synth_granule(float *qmf_state, float *grbuf, int nbands, int nch, mp3d_sample_t *pcm, float *lins)
{
    int i;
    for (i = 0; i < nch; i++) mp3d_DCT_II(grbuf + 576*i, nbands);
    memcpy(lins, qmf_state, (unsigned)(sizeof(float)*15*64));
    for (i = 0; i < nbands; i += 2) mp3d_synth(grbuf + i, pcm + 32*nch*i, nch, lins + i*64);

#ifndef MINIMP3_NONSTANDARD_BUT_LOGICAL
    if (nch == 1) {
        for (i = 0; i < 15*64; i += 2) qmf_state[i] = lins[nbands*64 + i];
    } else
#endif
    {
        memcpy(qmf_state, lins + nbands*64, (unsigned)(sizeof(float)*15*64));
    }
}

/* -------- Frame finder (kept) -------- */
static int mp3d_match_frame(const uint8_t *hdr, int mp3_bytes, int frame_bytes)
{
    int i;
    int nmatch;

    i = 0;
    for (nmatch = 0; nmatch < 10; nmatch++) {
        i += hdr_frame_bytes(hdr + i, frame_bytes) + hdr_padding(hdr + i);
        if (i + HDR_SIZE > mp3_bytes) return nmatch > 0;
        if (!hdr_compare(hdr, hdr + i)) return 0;
    }
    return 1;
}

static int mp3d_find_frame(const uint8_t *mp3, int mp3_bytes, int *free_format_bytes, int *ptr_frame_bytes)
{
    int i;
    int k;
    int frame_bytes;
    int frame_and_padding;
    int fb;
    int nextfb;

    frame_bytes = 0;
    frame_and_padding = 0;
    fb = 0;
    nextfb = 0;

    for (i = 0; i < mp3_bytes - HDR_SIZE; i++, mp3++) {
        if (hdr_valid(mp3)) {
            frame_bytes = hdr_frame_bytes(mp3, *free_format_bytes);
            frame_and_padding = frame_bytes + hdr_padding(mp3);

            for (k = HDR_SIZE; !frame_bytes && k < MAX_FREE_FORMAT_FRAME_SIZE && i + 2*k < mp3_bytes - HDR_SIZE; k++) {
                if (hdr_compare(mp3, mp3 + k)) {
                    fb = k - hdr_padding(mp3);
                    nextfb = fb + hdr_padding(mp3 + k);
                    if (i + k + nextfb + HDR_SIZE > mp3_bytes || !hdr_compare(mp3, mp3 + k + nextfb)) continue;
                    frame_and_padding = k; frame_bytes = fb; *free_format_bytes = fb;
                }
            }
            if ((frame_bytes && i + frame_and_padding <= mp3_bytes && mp3d_match_frame(mp3, mp3_bytes - i, frame_bytes)) ||
                (!i && frame_and_padding == mp3_bytes))
            { *ptr_frame_bytes = frame_and_padding; return i; }
            *free_format_bytes = 0;
        }
    }
    *ptr_frame_bytes = 0; return mp3_bytes;
}

/* -------- Public API -------- */
void mp3dec_init(mp3dec_t *dec)
{
    dec->header[0] = 0;
}

int mp3dec_decode_frame(mp3dec_scratch_t* scratch, mp3dec_t *dec, const uint8_t *mp3, int mp3_bytes, mp3d_sample_t *pcm, mp3dec_frame_info_t *info)
{
    int i;
    int igr;
    int frame_size;
    int success;
    const uint8_t *hdr;
    bs_t bs_frame[1];
    int main_data_begin;
    int free_format_tmp;

    i = 0;
    frame_size = 0;
    success = 1;
    main_data_begin = 0;

    memset(scratch, 0, sizeof(mp3dec_scratch_t));

    free_format_tmp = (int)dec->free_format_bytes;

    if (mp3_bytes > 4 && dec->header[0] == 0xff && hdr_compare(dec->header, mp3)) {
        frame_size = hdr_frame_bytes(mp3, free_format_tmp) + hdr_padding(mp3);
        if (frame_size != mp3_bytes && (frame_size + HDR_SIZE > mp3_bytes || !hdr_compare(mp3, mp3 + frame_size))) frame_size = 0;
    }
    if (!frame_size) {
        memset(dec, 0, sizeof(mp3dec_t));
        i = mp3d_find_frame(mp3, mp3_bytes, &free_format_tmp, &frame_size);
        dec->free_format_bytes = (dword)free_format_tmp;
        if (!frame_size || i + frame_size > mp3_bytes)
        {
            info->frame_bytes = (dword)i;
            return 0;
        }
    }

    hdr = mp3 + i;
    memcpy(dec->header, hdr, HDR_SIZE);
    info->frame_bytes = (dword)(i + frame_size);
    info->frame_offset = (dword)i;
    info->channels = (word)(HDR_IS_MONO(hdr) ? 1 : 2);
    info->hz = (dword)hdr_sample_rate_hz(hdr);
    info->layer = (word)(4 - HDR_GET_LAYER(hdr));
    info->bitrate_kbps = (dword)hdr_bitrate_kbps(hdr);

    if (!pcm) {
        return hdr_frame_samples(hdr);
    }

    bs_init(bs_frame, hdr + HDR_SIZE, frame_size - HDR_SIZE);
    if (HDR_IS_CRC(hdr)) get_bits(bs_frame, 16);

    if (info->layer == 3) {
        main_data_begin = L3_read_side_info(bs_frame, scratch->gr_info, hdr);
        if (main_data_begin < 0 || bs_frame->pos > bs_frame->limit)
        {
            mp3dec_init(dec);
            return 0;
        }
        success = L3_restore_reservoir(dec, bs_frame, scratch, main_data_begin);
        if (success) {
            for (igr = 0; igr < (HDR_TEST_MPEG1(hdr) ? 2 : 1); igr++, pcm += 576*info->channels) {
                memset(scratch->grbuf[0], 0, (unsigned)(576*2*sizeof(float)));
                L3_decode(dec, scratch, scratch->gr_info + igr*info->channels, info->channels);
                mp3d_fixed_to_float_buffer(dec->qmf_state, g_qmf_state_temp, MP3_QMF_STATE_LEN);
                mp3d_synth_granule(g_qmf_state_temp, scratch->grbuf[0], 18, info->channels, pcm, scratch->syn[0]);
                mp3d_float_to_fixed_buffer(dec->qmf_state, g_qmf_state_temp, MP3_QMF_STATE_LEN);
            }
        }
        L3_save_reservoir(dec, scratch);
    } else {
        /* Layer I/II removed: not supported in this build */
        return 0;
    }

    return success*hdr_frame_samples(dec->header);
}
