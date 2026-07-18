#ifndef __IMPGRAPH_H
#define __IMPGRAPH_H

#include <geos.h>

#define IMP_GRAPH_PROTO_MAJOR               4
#define IMP_GRAPH_PROTO_MINOR               3

#define IMP_GRAPH_ENTRY_IMPORT_FILE         4
#define IMP_GRAPH_ENTRY_IMPORT_FILE_HANDLE  5

typedef word ImpGraphFormat;

#define IG_FORMAT_AUTO       0
#define IG_FORMAT_PNG        1
#define IG_FORMAT_JPEG       2
#define IG_FORMAT_GIF        3

typedef word ImpGraphImportOptions;

#define IGIO_COMPRESS            0x0001
#define IGIO_USE_SYSTEM_PALETTE  0x0002

/*
 * Future versions may append fields.  The V1 fields and their types are
 * part of the library ABI and must not change.
 */
typedef struct {
    word                    IGIP_size;
    ImpGraphFormat          IGIP_format;
    ImpGraphImportOptions   IGIP_optionMask;
    ImpGraphImportOptions   IGIP_options;
    optr                    IGIP_status;
} ImpGraphImportParams;

#define IMP_GRAPH_IMPORT_PARAMS_V1_SIZE 12

typedef VMBlockHandle _pascal pcfm_ImpGraphImportFile(
    const TCHAR *fileP,
    VMFileHandle destFile,
    const ImpGraphImportParams *paramsP,
    void *pf);

typedef VMBlockHandle _pascal pcfm_ImpGraphImportFileHandle(
    FileHandle sourceFile,
    VMFileHandle destFile,
    const ImpGraphImportParams *paramsP,
    void *pf);

VMBlockHandle _export _pascal
ImpGraphImportFile(
    const TCHAR *fileP,
    VMFileHandle destFile,
    const ImpGraphImportParams *paramsP);

VMBlockHandle _export _pascal
ImpGraphImportFileHandle(
    FileHandle sourceFile,
    VMFileHandle destFile,
    const ImpGraphImportParams *paramsP);

#endif
