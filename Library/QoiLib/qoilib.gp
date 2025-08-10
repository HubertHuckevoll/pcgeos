##############################################################################
#
# QOI Library
#
##############################################################################

name            qoilib.lib
longname        "QOI Library"
tokenchars      "QOIL"
tokenid         0

# Library type: plain C API, single code segment
type            library, single, c-api

# Dependencies used by the implementation:
#  - geos: VM, HugeArray, Mem*, File*
#  - ansic: memcpy/strcmp/etc. (Ansi/string.h)
library         geos
library         ansic
library         extgraph

# Public exports (match the _pascal _export functions in your .goc/.c)
export QOIIMPORTBITMAPFNAME
export QOIIMPORTBITMAPFHANDLE
export QOIIMPORTTESTBITMAPFNAME
export QOIIMPORTTESTBITMAPFHANDLE

export QOIEXPORTBITMAPFHANDLE
