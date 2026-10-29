/* Target ABI check: ignore a callback's virtual segment, use the live CS,
 * and keep Pascal arguments, return values and stack balance intact.
 */
#include <assert.h>
#include <stdio.h>
#include <alloca.h>
#include <geos.h>
#include "../core/s_tmp3dec_file.h"
#include "../core/pv_mp3_huffman.h"

#pragma code_seg("MP3HuffCode")
static tmp3Bits bits;

static uint16 _pascal
Decode(tmp3Bits *bitsP)
{
    assert(bitsP == &bits);
    bitsP->usedBits++;
    return 0x4d33;
}

int main(void)
{
    huffcodetab table;
    unsigned available, i;

    /* A GEOS-style virtual segment is deliberately not callable under DOS. */
    table.pdec_huff_tab = (Mp3HuffProc)(0xf1230000UL |
                                      ((uint32)Decode & 0xffffUL));
    available = stackavail();
    for (i = 0; i < 1000; i++) {
        assert(MP3_HUFF_CALL(&table, &bits) == 0x4d33);
        assert(((uint32)table.pdec_huff_tab >> 16) == 0xf123);
    }
    assert(bits.usedBits == 1000 && stackavail() == available);
    puts("Huffman live CS, virtual pointer retention and Pascal stack: PASS");
    return 0;
}
