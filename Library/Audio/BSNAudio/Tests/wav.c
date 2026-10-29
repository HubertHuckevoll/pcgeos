/* Real WAV reader, native-file shim; no playback or decoder copies. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <bsnaudio.h>
static FILE *inputP;
static byte bytes[512];
static word used, failRead;
static void Put16(word v)
{
    bytes[used++] = (byte)v; bytes[used++] = (byte)(v>>8);
}
static void Put32(dword v)
{
    Put16((word)v); Put16((word)(v>>16));
}
static void Patch32(word at, dword v)
{
    word save = used;
    used = at; Put32(v); used = save;
}
static void Format(word bits, word channels, dword rate)
{
    Put32(0x20746d66UL); Put32(16);
    Put16(1); Put16(channels); Put32(rate);
    Put32(rate * channels * (bits/8));
    Put16(channels * (bits/8)); Put16(bits);
}
static void Data(word count)
{
    word i;
    Put32(0x61746164UL); Put32(count);
    for (i=0; i<count; i++) bytes[used++] = (byte)i;
    if (count & 1) bytes[used++] = 0;
}
static void Make(word bits, word channels, word count, word dataFirst)
{
    used = 0;
    Put32(0x46464952UL); Put32(0); Put32(0x45564157UL);
    /* An odd-sized unknown chunk requires its pad byte. */
    Put32(0x4b4e554aUL); Put32(1); Put16(0x007f);
    if (dataFirst) Data(count);
    Format(bits, channels, 48000);
    if (!dataFirst) Data(count);
    Patch32(4, used-8);
}
static void OpenInput(const char *pathP)
{
    if (inputP) fclose(inputP);
    inputP = fopen(pathP, "wb+"); assert(inputP);
    assert(fwrite(bytes, 1, used, inputP) == used);
    assert(fflush(inputP) == 0);
    failRead = 0;
}
dword FileSize(FileHandle file)
{
    long pos, end;
    assert(file == 1);
    pos = ftell(inputP); assert(fseek(inputP, 0, SEEK_END) == 0);
    end = ftell(inputP); assert(fseek(inputP, pos, SEEK_SET) == 0);
    return (dword)end;
}
dword FilePos(FileHandle file, dword offset, word mode)
{
    assert(file == 1 && mode == FILE_POS_START);
    return fseek(inputP, (long)offset, SEEK_SET) ? 0xffffffffUL : offset;
}
word FileRead(FileHandle file, void *destP, word count, word flags)
{
    assert(file == 1); (void)flags;
    if (failRead) return 0;
    return (word)fread(destP, 1, count, inputP);
}
int main(int argc, char **argv)
{
    BSNWav wav;
    byte pcm[17];
    word bits, channels, frames, order, count, total, i;
    assert(argc == 2);
    for (bits=8; bits<=16; bits+=8) {
        for (channels=1; channels<=2; channels++) {
            for (frames=0; frames<20; frames++) {
                for (order=0; order<2; order++) {
                    Make(bits, channels, frames*channels*(bits/8), order);
                    OpenInput(argv[1]);
                    assert(BSNWavOpen(&wav, 1) == BSNW_STATUS_OK);
                    assert(wav.source.format.sampleRate == 48000);
                    assert(wav.source.contextP == &wav);
                    total = 0;
                    while ((count = wav.source.readP(&wav, pcm, sizeof(pcm))) != 0) {
                        assert(count != BSN_PCM_READ_ERROR && count <= sizeof(pcm));
                        assert(count % wav.source.format.blockAlign == 0);
                        for (i=0; i<count; i++) assert(pcm[i] == (byte)(total+i));
                        total += count;
                    }
                    assert(total == frames*channels*(bits/8));
                    assert(ftell(inputP) == (long)(wav.dataOffset+total));
                    BSNWavClose(&wav); BSNWavClose(&wav);
                    assert(FileSize(1) == used); /* Borrow remains open. */
                }
            }
        }
    }
    Make(16, 2, 16, 0); OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) == BSNW_STATUS_OK);
    assert(BSNWavReadPCM(&wav, pcm, 3) == BSN_PCM_READ_ERROR);
    failRead = 1;
    assert(BSNWavReadPCM(&wav, pcm, sizeof(pcm)) == BSN_PCM_READ_ERROR);
    BSNWavClose(&wav);
    assert(BSNWavReadPCM(&wav, pcm, 16) == BSN_PCM_READ_ERROR);
    /* Every truncation is rejected, including a missing odd-chunk pad. */
    Make(8, 1, 7, 0); count = used;
    for (i=0; i<count; i++) {
        used = i; OpenInput(argv[1]);
        assert(BSNWavOpen(&wav, 1) != BSNW_STATUS_OK);
    }
    Make(16, 2, 7, 0); OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) == BSNW_UNKNOWN_WAVE_FORMAT);
    Make(16, 2, 16, 0); Patch32(26, 0xffffffffUL); OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) != BSNW_STATUS_OK); /* Oversized fmt chunk. */
    Make(16, 2, 16, 0); bytes[44] = 1; OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) == BSNW_UNKNOWN_WAVE_FORMAT); /* Bad align. */
    Make(16, 2, 16, 0); Patch32(34, 0xffffffffUL); OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) == BSNW_UNKNOWN_WAVE_FORMAT); /* Rate overflow. */
    Make(8, 1, 16, 0); bytes[0] = 0; OpenInput(argv[1]);
    assert(BSNWavOpen(&wav, 1) == BSNW_MEMORY_ERROR);
    fclose(inputP);
    puts("WAV formats, chunk bounds/padding/order, truncation, borrowed file: PASS");
    return 0;
}
