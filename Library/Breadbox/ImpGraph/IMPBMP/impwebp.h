#ifndef __IMPWEBP_H
#define __IMPWEBP_H

#include "IMPBMP/ibcommon.h"
#include <webplib.h>

ImpBmpStatus _pascal ImpWebP(TCHAR *file, VMFileHandle vmf,
                     ImageAdditionalData *iad, AllocWatcherHandle watcher,
                     dword *usedMem, ImpBmpParams *params,
                     Boolean *isCompacted, VMBlockHandle *bitmap,
                     ImportProgressData *importProgressDataP,
                     MimeStatus *mimeStatus);

#endif
