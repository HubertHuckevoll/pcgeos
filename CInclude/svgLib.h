#ifndef __SVG_LIB_H
#define __SVG_LIB_H

#include <graphics.h>
#include <vm.h>
#include <xlatLib.h>

typedef Boolean _pascal SvgProgressCallback(word percent);

TransError _export _pascal
SvgImport(FileHandle sourceFile,
          VMFileHandle destinationFile,
          VMChain *resultChainP,
          RectDWord *boundsP,
          SvgProgressCallback *callback);

TransError _export _pascal
SvgExport(FileHandle outputFile,
          VMFileHandle sourceFile,
          VMChain sourceChain);

Boolean _export _pascal
SvgCheckHeader(FileHandle sourceFile);

#endif
