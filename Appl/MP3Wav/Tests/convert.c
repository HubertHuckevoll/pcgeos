/* Host integration: public pull API plus the real WAV writer. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../wavwriter.h"

static FILE *sourceP, *outputP;
word FileRead(FileHandle fileH, void *dataP, word size, word flags)
{
    (void)flags;
    assert(fileH == 1);
    return (word)fread(dataP, 1, size, sourceP);
}
word FileWrite(FileHandle fileH, const void *dataP, word size, word flags)
{
    (void)flags;
    assert(fileH == 2);
    return (word)fwrite(dataP, 1, size, outputP);
}
dword FilePos(FileHandle fileH, dword offset, word mode)
{
    FILE *fileP;
    (void)mode;
    fileP = fileH == 1 ? sourceP : outputP;
    return fseek(fileP, offset, SEEK_SET) ? 0xffffffffUL : (dword)ftell(fileP);
}
int main(int argc, char **argvP)
{
    static sword pcm[1024];
    BSNMP3Dec decoder;
    WavWriter writer;
    word count;

    assert(argc == 3);
    sourceP = fopen(argvP[1], "rb");
    outputP = fopen(argvP[2], "wb");
    assert(sourceP && outputP);
    assert(BSNMP3DecOpen(&decoder, 1) == BSNW_STATUS_OK);
    assert(!decoder.damaged);
    assert(!WavWriterBegin(&writer, 2, &decoder.source.format));
    for (;;) {
        count = BSNMP3DecReadPCM(&decoder, pcm, sizeof(pcm));
        if (count == BSN_PCM_READ_ERROR || decoder.damaged) {
            BSNMP3DecClose(&decoder);
            fclose(sourceP); fclose(outputP);
            remove(argvP[2]);
            return 1;
        }
        if (!count) break;
        assert(!WavWriterAppend(&writer, pcm,
                  count / decoder.source.format.blockAlign,
                  &decoder.source.format));
    }
    assert(writer.bytes && !WavWriterFinish(&writer));
    BSNMP3DecClose(&decoder);
    assert(!fclose(sourceP) && !fclose(outputP));
    return 0;
}
