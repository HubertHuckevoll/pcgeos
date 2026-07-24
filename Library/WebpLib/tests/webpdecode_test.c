#include <assert.h>
#include <stdio.h>

#define WEBP_HOST_TEST
#include "../webpbit.c"
#include "../webpriff.c"
#include "../webpdsp.c"
#include "../webpvp8.c"
#include "../webpapi.c"

static void
FillPackBitsInput(byte *dataP, word size, word pattern)
{
    word index;

    for (index = 0; index < size; index++) {
        if (pattern == 0) {
            dataP[index] = (byte)(index * 37 + index / 127);
        } else if (pattern == 1) {
            dataP[index] = (byte)((index / 3) * 29);
        } else if (index % 17 < 5) {
            dataP[index] = (byte)(index / 17);
        } else {
            dataP[index] = (byte)(index * 53 + index / 11);
        }
    }
}

static void
TestOverlappingPackBits(void)
{
    static const word sizes[] = {
        1, 2, 3, 4, 126, 127, 128, 129, 130,
        255, 256, 257, WEBP_MAX_DIMENSION * 3
    };
    byte *expectedP;
    byte *separateP;
    byte *overlapAllocationP;
    byte *overlapP;
    byte *decodedP;
    HostBitmap bitmap;
    word size;
    word gap;
    word separateSize;
    word overlapSize;
    word pattern;
    word test;

    size = WEBP_MAX_DIMENSION * 3;
    gap = WEBP_PACKBITS_GAP(size);
    expectedP = (byte *)malloc(size);
    separateP = (byte *)malloc(size + gap);
    overlapAllocationP = (byte *)malloc(size + gap + 2);
    decodedP = (byte *)malloc(size);
    assert(expectedP != (void *)0);
    assert(separateP != (void *)0);
    assert(overlapAllocationP != (void *)0);
    assert(decodedP != (void *)0);
    overlapP = overlapAllocationP + 1;

    for (pattern = 0; pattern < 3; pattern++) {
        for (test = 0; test < sizeof(sizes) / sizeof(sizes[0]); test++) {
            size = sizes[test];
            gap = WEBP_PACKBITS_GAP(size);
            FillPackBitsInput(expectedP, size, pattern);
            separateSize = WebPPackBits(separateP, expectedP, size);

            memset(overlapAllocationP, 0xa5, size + gap + 2);
            memcpy(overlapP + gap, expectedP, size);
            overlapSize = WebPPackBits(overlapP, overlapP + gap, size);
            assert(overlapSize == separateSize);
            assert(overlapSize <= size + ((size + 127) >> 7));
            assert(memcmp(overlapP, separateP, overlapSize) == 0);
            assert(overlapP[-1] == 0xa5);
            assert(overlapP[size + gap] == 0xa5);

            memset(&bitmap, 0, sizeof(bitmap));
            memset(decodedP, 0, size);
            bitmap.height = 1;
            bitmap.rowBytes = size;
            bitmap.pixelsP = decodedP;
            assert(HugeArrayAppend((void *)0, &bitmap, overlapSize,
                                   overlapP) == 0);
            assert(memcmp(decodedP, expectedP, size) == 0);
        }
    }

    free(decodedP);
    free(overlapAllocationP);
    free(separateP);
    free(expectedP);
}

int
main(int argc, char **argv)
{
    FILE *inputP;
    FILE *outputP;
    byte *dataP;
    long size;
    TestFile source;
    WebPImportHandle decoder;
    VMBlockHandle bitmap;
    WebPImageInfo info;
    WebPResult result;
    word firstLine;
    word lineCount;
    word expectedLine;

    if (argc != 3) {
        fprintf(stderr, "usage: webpdecode_test input.webp output.rgb\n");
        return 2;
    }
    TestOverlappingPackBits();
    inputP = fopen(argv[1], "rb");
    assert(inputP != (void *)0);
    assert(fseek(inputP, 0, SEEK_END) == 0);
    size = ftell(inputP);
    assert(size > 0);
    assert(fseek(inputP, 0, SEEK_SET) == 0);
    dataP = (byte *)malloc((size_t)size);
    assert(dataP != (void *)0);
    assert(fread(dataP, 1, (size_t)size, inputP) == (size_t)size);
    fclose(inputP);

    source.dataP = dataP;
    source.size = (dword)size;
    source.position = 0;
    result = WebPImportBegin(&source, (void *)0, &decoder,
                             &bitmap, &info);
    assert(result == WEBP_RESULT_OK);
    expectedLine = 0;
    do {
        result = WebPImportNext(decoder, &firstLine, &lineCount);
        if (result == WEBP_RESULT_OK) {
            assert(lineCount != 0);
            assert(firstLine == expectedLine);
            expectedLine += lineCount;
        }
    } while (result == WEBP_RESULT_OK);
    assert(result == WEBP_RESULT_DONE);
    assert(expectedLine == info.height);
    WebPImportDestroy(decoder);

    outputP = fopen(argv[2], "wb");
    assert(outputP != (void *)0);
    assert(fwrite(bitmap->pixelsP, bitmap->rowBytes,
                  bitmap->height, outputP) == bitmap->height);
    fclose(outputP);
    free(bitmap->pixelsP);
    free(bitmap);
    free(dataP);
    printf("%u %u\n", info.width, info.height);
    return 0;
}
