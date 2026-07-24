#include <assert.h>
#include <stdio.h>

#define WEBP_HOST_TEST
#include "../webpbit.c"
#include "../webpriff.c"
#include "../webpdsp.c"
#include "../webpvp8.c"
#include "../webpapi.c"

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
