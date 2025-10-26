#ifndef _TRANSLATOR_DESCRIPTOR_H_
#define _TRANSLATOR_DESCRIPTOR_H_

#include <geoworks.h>
#include <xlatLib.h>

#define TRANS_IFI_IMPORT_CAPABLE 0x8000
#define TRANS_IFI_EXPORT_CAPABLE 0x4000

typedef struct
{
    optr importUI;
    optr exportUI;
    word formatFlags;
} TransFormatInfo;

#pragma pack(1)
typedef struct
{
    char marker[2];
    word stringsResource;
    word numberOfFormats;
    word dataClass;
    char marker2[2];
} TransLibraryHeaderRecord;

typedef struct
{
    word formatNameChunk;
    word fileMaskChunk;
    optr importUI;
    optr exportUI;
    word formatInfo;
} TransImpexFormatRecord;
#pragma pack()

typedef dword (_far _pascal *TransImportCallback)(ImportFrame *frameP, VMChain *chainP);
typedef dword (_far _pascal *TransExportCallback)(ExportFrame *frameP);
typedef word (_far _pascal *TransTestCallback)(FileHandle file);
typedef MemHandle (_far _pascal *TransOptionsCallback)(Handle dialogH);
typedef void (_far _pascal *TransInitUICallback)(Handle dialogH);

typedef struct
{
    const TransFormatInfo _far *formats;
    word formatCount;
    word dataClass;
    TransImportCallback importProc;
    TransExportCallback exportProc;
    TransTestCallback testProc;
    TransOptionsCallback getImportOptionsProc;
    TransOptionsCallback getExportOptionsProc;
    TransInitUICallback initImportUICallback;
    TransInitUICallback initExportUICallback;
} TransDescriptor;

TransDescriptor _far * _pascal XLAT_GetDescriptor(void);

#endif /* _TRANSLATOR_DESCRIPTOR_H_ */
