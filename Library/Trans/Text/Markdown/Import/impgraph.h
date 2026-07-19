/********************************************************************
 This file added to provide some convenience
 07/2026 MeyerK
*********************************************************************/

#ifndef __MARKDOWN_IMPGRAPH_H
#define __MARKDOWN_IMPGRAPH_H

#include <file.h>
#include <htmldrv.h>
#include <library.h>
#include <resource.h>

#define IMP_GRAPH_PROTO_MAJOR 4
#define IMP_GRAPH_PROTO_MINOR 2

#if ERROR_CHECK
#define IMP_GRAPH_LIBRARY_NAME "EC Breadbox Graphics Imp Library"
#else
#define IMP_GRAPH_LIBRARY_NAME "Breadbox Graphics Imp Library"
#endif

/*
 * Store a used library handle in libraryH.  The caller may pass a null errorP.
 * Release a successful result with GeodeFreeLibrary().
 */
#define ImpGraphUseLibrary(libraryH, errorP)                              \
    do {                                                                 \
        GeodeLoadError impGraphError;                                    \
        GeodeLoadError *impGraphErrorP = (errorP);                       \
        if (impGraphErrorP == (void *)0)                                 \
            impGraphErrorP = &impGraphError;                             \
        FilePushDir();                                                   \
        FileSetStandardPath(SP_IMPORT_EXPORT_DRIVERS);                   \
        (libraryH) = GeodeUseLibrary(IMP_GRAPH_LIBRARY_NAME,             \
                                     IMP_GRAPH_PROTO_MAJOR,              \
                                     IMP_GRAPH_PROTO_MINOR,              \
                                     impGraphErrorP);                    \
        FilePopDir();                                                    \
    } while (0)

#if PROGRESS_DISPLAY
#define IMP_GRAPH_DEFAULT_PROGRESS , (ImportProgressData *)0
#else
#define IMP_GRAPH_DEFAULT_PROGRESS
#endif

/*
 * Store a static HugeBitmap VM block in bitmap.  Relative paths use the
 * caller's current directory.  The returned VM chain belongs to destFile and
 * must be freed by the caller when it is no longer needed.
 */
#define ImpGraphImportBitmap(bitmap, libraryH, fileP, destFile)           \
    do {                                                                 \
        entry_MimeDrvGraphicEx *impGraphEntryP;                          \
        GeodeHandle impGraphLibraryH = (libraryH);                       \
        const TCHAR *impGraphFileP = (fileP);                            \
        VMFileHandle impGraphDestFile = (destFile);                      \
        VMBlockHandle impGraphBitmap = NullHandle;                       \
        if (impGraphLibraryH != NullHandle &&                            \
            impGraphFileP != (void *)0 &&                               \
            impGraphFileP[0] != C_NULL &&                               \
            impGraphDestFile != NullHandle) {                            \
            impGraphEntryP = ProcGetLibraryEntry(                        \
                impGraphLibraryH, MIME_ENTRY_GRAPHIC_EX);                \
            if (impGraphEntryP != (void *)0) {                           \
                impGraphBitmap = ((pcfm_MimeDrvGraphicEx *)              \
                    ProcCallFixedOrMovable_pascal)(                      \
                        (TCHAR *)0, (TCHAR *)impGraphFileP,               \
                        impGraphDestFile,                                \
                        (ImageAdditionalData *)0,                        \
                        MIME_RES_DISPLAY_DEFAULT, NullWatcher,           \
                        (dword *)0, (MimeStatus *)0                      \
                        IMP_GRAPH_DEFAULT_PROGRESS,                      \
                        MIME_GREX_NO_ANIMATIONS, impGraphEntryP);        \
            }                                                            \
        }                                                                \
        (bitmap) = impGraphBitmap;                                       \
    } while (0)

#endif
