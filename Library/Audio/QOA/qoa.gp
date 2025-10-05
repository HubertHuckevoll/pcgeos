##############################################################################
#
#  QOA audio decoder/player library for PC/GEOS.
#
##############################################################################

name            qoa.lib
longname        "QOA Audio Decoder"
tokenchars      "QOA0"
tokenid         0

type            library, single, c-api

library         geos
library         ansic
library         bsnwav

entry           QOALIBENTRY

export          QOAPLAYFILE
export          QOASTOP
export          QOAPROBEFILE
