########################################################################
#
#     Copyright (c) Dirk Lausecker 1999-2000 -- All Rights Reserved
#
# PROJECT:      BestSound
# MODULE:       NewWave Library
# FILE:         bsnwav.gp
#
# AUTHOR:       Dirk Lausecker
#
# DESCRIPTION:
#   Geode definitions for the NEWWAVE-Library.
#
# REVISION HISTORY:
#   Date      Name      Description
#   --------  --------  -----------
#   21.06.98  DirkL     Initial Version.
#   06.10.98    DL      Ableitung von Template
#   08.10.99    DL      Ableitung von Mixer Library
#   27.12.99    DL      Ableitung von Recordlibrary
#   20.02.2000  DL      NewWave Routinen
#   08.08.2000  DL      Translating for ND
#
########################################################################

name bsnwav.lib
longname "BestSound Wave Library"
tokenchars "BSNW"
tokenid 16427

type    library, single, c-api

# platform geos201

#
# Libraries: list which libraries are used by the application.
#
library geos
# For playing the startup sound its necessary to exclude
# the use of the UI-Library which is not available at startup :-(
# No UI-Objects, No UserStandardDialog (replaced by SysNotify() )
# ANSIC uses UI too
#
library ansic
# library ui

# resource STATUSBOXRESOURCE    ui-object
# resource MONIKERRESOURCE  data object read-only

#
# Export classes
#       These are the classes exported by the library
#

# export StatusInteractionClass


#
# Routines
#       These are the routines exported by the library
#

entry   BSNWLIBENTRY

incminor

export  BSNWAVLOADDRIVER
export  BSNWAVGETMAXPROPERTIES
export  BSNWALLOCSECBUFFER
export  BSNWAVEPLAYFILE
export  BSNWAVEGETSTATUS
export  BSNWAVEGETAISTATE
export  BSNWAVESTOPRECORPLAY
export  BSNWAVEPLAYMEMORY
export  BSNWAVESTOP
export  BSNWAVESETPAUSE
export  BSNWAVEPLAYCALLBACK
export  BSNWAVECHECKDRIVER
export  BSNWAVECALCPLAYTIMETEXT
export  BSNWAVEGETPLAYSTATE
export  BSNWAVEGETLASTFORMAT
export  BSNWAVPLAYQOAFILE
export  BSNWAVSTOPQOA
export  BSNWAVPROBEQOAFILE
export  BSNWAVPLAYMP3FILE
export  BSNWAVPLAYMP3FILEHANDLE

# usernotes "NewWave-Library for best sound. \xa9 2000 Dirk Lausecker"

