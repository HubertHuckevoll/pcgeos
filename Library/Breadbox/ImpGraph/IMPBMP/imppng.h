#ifndef __IMPPNG_H
#define __IMPPNG_H

#include "IMPBMP/ibcommon.h"
#include "pnglib.h"

VMBlockHandle
PngImport(
    TCHAR *file,
    VMFileHandle vmf,
    XYSize *picsize,
    MimeRes resolution,
    AllocWatcherHandle watcher,
    dword *usedMem,
    Boolean *p_completeGraphic
    , _ImportProgressParams_
    , MimeStatus *mimeStatus
);

#endif
