/* Target ABI regression: the Pascal dispatcher consumes the final argument
 * as the callback address. Host direct-callback tests do not cover this path.
 */
#include <assert.h>
#include <stdio.h>
#include <alloca.h>
#include <geos.h>
#include <resource.h>
#include "../core/s_tmp3dec_file.h"

static tmp3Bits bits;
static uint16 _pascal Decode(tmp3Bits *bitsP);
static uint16 _pascal TestPascalThunk(tmp3Bits *bitsP, Mp3HuffProc proc);

/* Substitute only the kernel trampoline; exercise the real GEOS call macro. */
#define ProcCallFixedOrMovable_pascal TestPascalThunk
#include "../core/pv_mp3_huffman.h"

static uint16 _pascal
Decode(tmp3Bits *bitsP)
{
    assert(bitsP == &bits);
    bitsP->usedBits++;
    return 0x4d33;
}

static uint16 _pascal
TestPascalThunk(tmp3Bits *bitsP, Mp3HuffProc proc)
{
    assert(bitsP == &bits && proc == Decode);
    return proc(bitsP);
}

int main(void)
{
    huffcodetab table;
    unsigned available, i;

    table.pdec_huff_tab = Decode;
    available = stackavail();
    for (i = 0; i < 1000; i++) {
        assert(MP3_HUFF_CALL(&table, &bits) == 0x4d33);
    }
    assert(bits.usedBits == 1000 && stackavail() == available);
    puts("Pascal Huffman thunk argument order and stack balance: PASS");
    return 0;
}
