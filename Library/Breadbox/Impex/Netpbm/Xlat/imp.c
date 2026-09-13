/***********************************************************************
 *
 * MODULE:    imppng.goc (PNG Import)
 * FILE:      imppng.goc
 *
 ***********************************************************************/

/*
 ***************************************************************************
 *      Include files
 ***************************************************************************
 */

/* #include <pnglib.h> */
#include <geos.h>
#include <stdio.h>
#include <Ansi/stdlib.h>
#include <Ansi/string.h>
#include <graphics.h>
#include <vm.h>
#include <hugearr.h>
#include <xlatLib.h>
#include <extgraph.h>
#include <heap.h>
#include <file.h>
#include <system.h>


VMBlockHandle _pascal _export readPBMText(FileHandle fileHan, VMFileHandle vmFile);
int _pascal _export checkPBMHeader(FileHandle file);
int _pascal _export getPBMSize(FileHandle file, word *width, word *height);
VMBlockHandle _pascal _export initiateOutputBitmap(VMFileHandle vmFile, word width, word height, BMFormat fmt);


dword _pascal ImportProcedure(ImportFrame *frame, VMChain *chain)
{

    VMBlockHandle bmpBlock;
    /*
    pngAlphaTransformData pngAlphaTransform;
    pngAlphaTransformData* optionsP;

    pngAlphaTransform.method = PNG_AT_TRESHOLD;
    pngAlphaTransform.alphaThreshold = 128;
    pngAlphaTransform.blendColor.RGB_red = 255;
    pngAlphaTransform.blendColor.RGB_green = 255;
    pngAlphaTransform.blendColor.RGB_blue = 255;
*/
    *chain = 0;
/*
    if (frame->IF_importOptions != NullHandle)
    {
        optionsP = (pngAlphaTransformData*) MemLock(frame->IF_importOptions);
        if (optionsP != (pngAlphaTransformData*)0)
        {
            pngAlphaTransform = *optionsP;
            MemUnlock(frame->IF_importOptions);
        }
    }

    bmblock = pngImportConvertFile(frame->IF_sourceFile, frame->IF_transferVMFile, &pngAlphaTransform);
*/

    bmpBlock = readPBMText(frame->IF_sourceFile, frame->IF_transferVMFile);

    if (bmpBlock != NullHandle)
    {
        *chain = VMCHAIN_MAKE_FROM_VM_BLOCK(bmpBlock);
        return (TE_NO_ERROR | (((dword)CIF_BITMAP) << 16));
    }

    return (TE_INVALID_FORMAT);
}

word _pascal TestFile(FileHandle file)
{
    Boolean isPNG;

    /* isPNG = pngImportCheckHeader(file); */
    isPNG = TRUE;

    if (!isPNG)
    {
        return NO_IDEA_FORMAT;
    }

    return TE_NO_ERROR;
}


VMBlockHandle _pascal _export readPBMText(FileHandle fileHan, VMFileHandle vmFile)
{

    word width = 0;
    word height = 0;
    VMBlockHandle vmBlock = NullHandle;
    BMFormat fmt = 0;

    //Header einlesen und Bildgröße bestimmen
    if (!checkPBMHeader(fileHan))
    {
        return NullHandle; /* not a PBM file */
    }

    if (!getPBMSize(fileHan, &width, &height))
    {
        return NullHandle; /* not a PBM file */
    }

    /* Initialize output bitmap */
    fmt = BMF_MONO;
    vmBlock = initiateOutputBitmap(vmFile, width, height, fmt);
    if (vmBlock == NullHandle)
    {
        return NullHandle; /* failed to create bitmap */
    }

    //Bilddaten einlesen und in die Bitmap schreiben

    //return vmBlock;


    return NullHandle;
}


/* check PBM Header */
int _pascal _export checkPBMHeader(FileHandle file)
{
    unsigned char header[2] = {0};

     /* make sure we start at the beginning of the file */
	FilePos(file, 0, FILE_POS_START);

    /* Read header */
    if (FileRead(file, header, sizeof(header), FALSE) != sizeof(header))
    {
        return 0; /* file not long enough, no PBM */
    }

    /* Compare header with PBM-signature */
    if (memcmp(header, "P1", sizeof("P1")) != 0)
    {
        return 0; /* no PBM signature */
    }

    /* a PBM-signature it is */
    return 1;
}


int _pascal _export getPBMSize(FileHandle file, word *width, word *height)
{
    char header[20] = {0};
    char numberBuffer[10] = {0};
    Boolean isNumber;
    char asciiValue;
    byte indexBuffer = 0;
    byte countNumber = 0;
    int i;

    *width = 0;
    *height = 0;

     /* make sure we start at the beginning of the file */
	FilePos(file, 2, FILE_POS_START);

    /* Read header */
    if (FileRead(file, header, sizeof(header), FALSE) != sizeof(header))
    {
        return 0; /* file not long enough, no PBM */
    }

    /* read width and height */
    isNumber = FALSE;
    countNumber = 0;
    for (i = 0; i < strlen(header); i++)
    {
        asciiValue = header[i];

        if (asciiValue == ' ' || asciiValue == '\n' || asciiValue == '\r' || asciiValue == '\t')
        {
            if (isNumber == TRUE)
            {
                isNumber = FALSE;
                numberBuffer[indexBuffer] = '\0'; // Null-terminate the number string

                if (countNumber == 1)
                {
                    //*width = atoi((char*)numberBuffer);
                    UtilAsciiToHex32(numberBuffer, (sdword*) width);
                }
                else if (countNumber == 2)
                {
                    //*height = atoi((char*)numberBuffer);
                    UtilAsciiToHex32(numberBuffer, (sdword*) height);
                    break; // We have both width and height, exit the loop
                }
            }
            continue; /* skip whitespace */
        }
        else if (asciiValue >= '0' && asciiValue <= '9')
        {
            if (isNumber == FALSE)
            {
                isNumber = TRUE;
                countNumber++;
                indexBuffer = 0;
            }
            numberBuffer[indexBuffer++] = asciiValue;
        }
        else
        {
            return 0; /* invalid character, not a PBM */
        }
    }

    /* a PBM-signature it is */
    return 1;
}


/* create the GEOS Bitmap */
VMBlockHandle _pascal _export initiateOutputBitmap(VMFileHandle vmFile, word width, word height, BMFormat fmt)
{
    GStateHandle bmpState;
    VMBlockHandle vmBlock = NullHandle;

    vmBlock = GrCreateBitmap(
        fmt,
        width, height,
        vmFile,
        0,
        &bmpState
    );

    GrDestroyBitmap(bmpState, BMD_LEAVE_DATA);

    return vmBlock;
}
