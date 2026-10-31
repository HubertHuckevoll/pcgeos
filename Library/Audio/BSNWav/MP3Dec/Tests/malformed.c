/* Host sanitizer check: truncated input, corrupted headers and frame payloads. */
#include <assert.h>
#include <stdio.h>
#include "host.h"

static byte input[65535];
static sword pcm[2304];
static byte crcInput[2048];
int main(int argc, char **argvP)
{
    FILE *sourceP;
    Mp3DecHandle decoderH;
    Mp3DecFormat format;
    Mp3DecResult result;
    unsigned length, iteration, position, steps, at;
    uint32_t random = 1;
    word count, accepted, frames, ended, capacity;
    byte original;

    assert(argc == 3);
    /* Corrupt the stored CRC of a real protected frame, leaving its audio
     * header/payload intact. Concealment must remain an explicit result. */
    sourceP = fopen(argvP[2], "rb");
    assert(sourceP);
    count = (word)fread(crcInput, 1, sizeof(crcInput), sourceP);
    fclose(sourceP);
    for (at = 0; at + 6 < count; at++) {
        if (crcInput[at] == 255 && (crcInput[at+1] & 0xe7) == 0xe2) break;
    }
    assert(at + 6 < count);
    crcInput[at+4] ^= 1;
    assert(Mp3DecCreate(&decoderH) == MP3DEC_PCM);
    assert(Mp3DecFeed(decoderH, crcInput, count, 0, &accepted) == MP3DEC_PCM);
    for (steps = 0; steps < 16; steps++) {
        result = Mp3DecReadPCM(decoderH, pcm, sizeof(pcm), &frames, &format);
        if (result == MP3DEC_RECOVERABLE) break;
        assert(result == MP3DEC_PCM);
    }
    assert(result == MP3DEC_RECOVERABLE && frames);
    Mp3DecDestroy(decoderH);
    sourceP = fopen(argvP[1], "rb");
    assert(sourceP);
    length = (unsigned)fread(input, 1, sizeof(input), sourceP);
    assert(length > 100 && !ferror(sourceP));
    fclose(sourceP);
    assert(Mp3DecCreate(&decoderH) == MP3DEC_PCM);
    for (iteration = 0; iteration < 256; iteration++) {
        assert(Mp3DecReset(decoderH) == MP3DEC_PCM);
        random = random * 1664525UL + 1013904223UL;
        at = random % length;
        original = input[at];
        input[at] ^= (byte)(1U << (iteration & 7));
        position = ended = 0;
        capacity = 3;
        for (steps = 0; steps < length * 4 + 100; steps++) {
            result = Mp3DecReadPCM(decoderH, pcm, capacity, &frames, &format);
            assert(frames * format.channels * 2 <= capacity);
            if (result == MP3DEC_END || result == MP3DEC_TRUNCATED ||
                result == MP3DEC_FATAL) break;
            if (result == MP3DEC_OUTPUT_SMALL) {
                capacity = sizeof(pcm);
            } else if (result == MP3DEC_NEED_INPUT) {
                assert(!ended);
                count = length - position > 521 ? 521 : length - position;
                result = Mp3DecFeed(decoderH, input + position, count,
                                    count == length - position ? MP3DEC_FEED_END : 0,
                                    &accepted);
                assert(result == MP3DEC_PCM || result == MP3DEC_INPUT_FULL);
                position += accepted;
                if (position == length) ended = 1;
            } else {
                assert(result == MP3DEC_PCM || result == MP3DEC_RECOVERABLE ||
                       result == MP3DEC_FORMAT_CHANGED);
            }
        }
        assert(steps < length * 4 + 100);
        input[at] = original;
        /* Includes every possible short final suffix without a second corpus. */
        if ((iteration & 3) == 0) length--;
    }
    Mp3DecDestroy(decoderH);
    puts("256 corrupt/truncated stream cases: PASS");
    return 0;
}
