/***********************************************************************
 *
 * MODULE:    exppng (PNG Export)
 * FILE:      exppng.goc
 *
 ***********************************************************************/

/*
 ***************************************************************************
 *              Include files
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

dword _pascal writePBMText(ExportFrame *frame, VMBlockHandle bmpBlock);

/****************************************************************************
*  GLOBALS
****************************************************************************/


/**************************************************************************/

dword _pascal ExportProcedure(ExportFrame *frame)
{
    BMType desttype;
    EGError egstat = EGE_NO_ERROR;
    VMBlockHandle bmpBlock;
    dword err = TE_NO_ERROR;

    desttype = BMF_MONO;

        // convert gstring to bmp

    bmpBlock = BmpGStringToBitmap(
        frame->EF_transferVMFile,
        VMCHAIN_GET_VM_BLOCK(frame->EF_transferVMChain),
        frame->EF_transferVMFile,
        desttype,
        &egstat);

    if(egstat != EGE_NO_ERROR)
    {
        // error code translation
        switch(egstat)
        {
            case EGE_BLOCK_LOCKING_FAILURE:
            case EGE_CANT_CREATE_BITMAP:
                return(TE_OUT_OF_MEMORY);

            case EGE_ILLEGAL_BITMAP_SIZE:
                return(TE_INVALID_FORMAT);

            default:
                return(TE_ERROR);
        }
    }

    if(!bmpBlock) return(TE_OUT_OF_MEMORY);



    err = writePBMText(frame, bmpBlock);

    return err;

// Fehlerdefinitionen in pcgeos/Include/Internal/xlatLib.def

    /* PngError gstat = PE_NO_ERROR; */
    /*
    EGError egstat = EGE_NO_ERROR;
    VMBlockHandle bmblock;
    BMType desttype;
    word *optptr;

    if(!frame->EF_transferVMChain) return(TE_ERROR);
*/
    /*
    // get the selected output format
    if(frame->EF_exportOptions)
    {
        // getting and prepairing options
        optptr = (word*) MemLock(frame->EF_exportOptions);

        if(optptr)
        {
            desttype = *optptr;
            MemUnlock(frame->EF_exportOptions);
        }
        else
        {
            return(TE_ERROR);
        }
    }
    else
    {
        return(TE_ERROR);
    }

    if(desttype == BMF_4BIT) desttype |= BMT_PALETTE;
    if(desttype == BMF_8BIT) desttype |= BMT_PALETTE;
    if(desttype == BMF_24BIT) desttype |= BMT_MASK;
*/
    // convert gstring to bmp
    /*
    bmblock = BmpGStringToBitmap(
        frame->EF_transferVMFile,
        VMCHAIN_GET_VM_BLOCK(frame->EF_transferVMChain),
        frame->EF_transferVMFile,
        desttype,
        &egstat);

    if(egstat != EGE_NO_ERROR)
    {
        // error code translation
        switch(egstat)
        {
            case EGE_BLOCK_LOCKING_FAILURE:
            case EGE_CANT_CREATE_BITMAP:
                return(TE_OUT_OF_MEMORY);

            case EGE_ILLEGAL_BITMAP_SIZE:
                return(TE_INVALID_FORMAT);

            default:
                return(TE_ERROR);
        }
    }

    if(!bmblock) return(TE_OUT_OF_MEMORY);
*/
    /* gstat = pngExportBitmapFHandle(frame->EF_transferVMFile, bmblock, frame->EF_outputFile); */

    // free bmblock
    // VMFreeVMChain(frame->EF_transferVMFile, VMCHAIN_MAKE_FROM_VM_BLOCK(bmblock));

    /*
    if(gstat != PE_NO_ERROR)
    {
        // error code translation
        switch(gstat)
        {
            case PE_WRITE_PROBLEM:
                return(TE_FILE_WRITE);

            case PE_BLOCK_LOCK_FAILURE:
            case PE_OUT_OF_MEMORY:
                return(TE_OUT_OF_MEMORY);

            case PE_INVALID_BITMAP:
                return(TE_EXPORT_ERROR);

            default:
                return(TE_ERROR);
        }
    }
*/
    //return(TE_NO_ERROR);
}


dword _pascal writePBMText(ExportFrame *frame, VMBlockHandle bmpBlock)
{

    void *lineptr;
    word size, y, z;
    char header[72] = {0};
    //char info[20] = {0};
    byte pixelValue;
    byte index;
    Boolean isEnd;
    int i, iMin;

    dword width = 0;
    dword height = 0;
    //BMType bmptype = 0;
    //BMFormat bitform = 0;
    SizeAsDWord size_xy = 0;
    EGError egStat = EGE_NO_ERROR;


     /* Determine bitmap size */
    size_xy = BmpGetBitmapSize(frame->EF_transferVMFile, bmpBlock, &egStat);
    if (egStat != EGE_NO_ERROR) {
        return TE_EXPORT_ERROR;
    }
    width = DWORD_WIDTH(size_xy);
    height = DWORD_HEIGHT(size_xy);



    // Write PPM Header (P1 format)
    sprintf(header, "P1\n%lu %lu\n", width, height);
    if (FileWrite(frame->EF_outputFile, header, strlen(header), FALSE) != strlen(header))
    {
        //FileClose(frame->EF_outputFile, 0);
        return(TE_EXPORT_ERROR);
    }




    // Write each scanline as raw RGB data
    index = 0;
    for (y = 0; y < height; y++)
    {
        if (HAL_COUNT(HugeArrayLock(frame->EF_transferVMFile, bmpBlock, y, &lineptr, &size)))
        {
/*
            sprintf(info, "AAA%u-%u-", y, size);
            if (FileWrite(frame->EF_outputFile, info, strlen(info), FALSE) != strlen(info))
                        {
                            HugeArrayUnlock(lineptr);
                            //FileClose(frame->EF_outputFile, 0);
                            return(TE_EXPORT_ERROR); // Writing failed
                        }
*/

            for (z = 0; z < size; z++)
            {
                // Convert each pixel to ASCII '0' or '1' for PBM format
                pixelValue = ((byte*) lineptr)[z] ;


                if (z == size - 1)
                {
                    iMin = (width % 8 > 0) ? 8 - (width % 8) : 0; // Last pixel in the row
                }
                else
                {
                    iMin = 0; // Not the last pixel, write whole byte
                }

                for (i = 7; i >= iMin; i--)
                {
                    header[index++] = ((pixelValue >> i) & 1) ? '1' : '0';

                    isEnd = (y == height - 1) && (z == size - 1) && (i == iMin);

                    if (index == 70 || isEnd) // Limit line length to 70 characters
                    {
                        header[index] = '\n';
                        if (FileWrite(frame->EF_outputFile, header, index + 1, FALSE) != index + 1)
                        {
                            HugeArrayUnlock(lineptr);
                            //FileClose(frame->EF_outputFile, 0);
                            return(TE_EXPORT_ERROR); // Writing failed
                        }
/*
                        for (index = 0; index < 72; index++) // Reset header buffer
                        {
                            header[index] = 0;
                        }
*/
                        index = 0;
                    }
                }
            }
/*
            if (FileWrite(frame->EF_outputFile, "XXX", 3, FALSE) != 3)
                        {
                            HugeArrayUnlock(lineptr);
                            //FileClose(frame->EF_outputFile, 0);
                            return(TE_EXPORT_ERROR); // Writing failed
                        }
*/
/*
            // Directly write the RGB scanline data (already in 24-bit format)
            if (FileWrite(frame->EF_outputFile, lineptr, size, FALSE) != size)
            {
                HugeArrayUnlock(lineptr);
                FileClose(frame->EF_outputFile, 0);
                return(TE_EXPORT_ERROR); // Writing failed
            }
*/
            HugeArrayUnlock(lineptr);
        }
        else
        {
            //FileClose(frame->EF_outputFile, 0);
            return TE_EXPORT_ERROR; // Failed to lock scanline
        }
    }


    return TE_NO_ERROR;

}
