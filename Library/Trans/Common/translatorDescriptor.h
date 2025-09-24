#ifndef _TRANSLATOR_DESCRIPTOR_H_
#define _TRANSLATOR_DESCRIPTOR_H_

#include <geoworks.h>
#include <xlatLib.h>

#define IFI_IMPORT_CAPABLE 0x8000
#define IFI_EXPORT_CAPABLE 0x4000

typedef struct
{
    const char _far *formatName;
    const char _far *fileMask;
    optr importUI;
    optr exportUI;
    word formatFlags;
} TransFormatInfo;

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

#define XLAT_DESCRIPTOR_FORMAT_ENTRY(symbol, nameLiteral, maskLiteral, importUIOptr, exportUIOptr, flagsValue) \
    { (const char _far *)(nameLiteral), (const char _far *)(maskLiteral), (importUIOptr), (exportUIOptr), (word)(flagsValue) }

TransDescriptor _far * _pascal XLAT_GetDescriptor(void);

#endif /* _TRANSLATOR_DESCRIPTOR_H_ */
