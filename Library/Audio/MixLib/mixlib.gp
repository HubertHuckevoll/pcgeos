########################################################################
#
#     Copyright (c) Dirk Lausecker 1997 -- All Rights Reserved
#
# PROJECT:      BestSound
# MODULE:       Mixer Library
# FILE:         mixlib.gp
#
# AUTHOR:       Dirk Lausecker
#
# RCS STAMP:
#   $Id$
#
# DESCRIPTION:
#   Geode definitions for the MIXLIB-Library.
#
# REVISION HISTORY:
#   Date      Name      Description
#   --------  --------  -----------
#   21.06.98  DirkL     Initial Version.
#   06.10.98	DL	Ableitung von Template
#
########################################################################

name mixlib.lib
longname "BestSound Mixer Library"
tokenchars "BSML"
tokenid 16427

type    library, single, c-api

#platform geos20

#
# Libraries: list which libraries are used by the application.
#
library geos
library ui
library ansic
library sound

#exempt ansic
#exempt sound

resource STRINGRESOURCE	data, lmem, read-only, shared

entry	LIBMIXENTRY
#
# Export classes
#       These are the classes exported by the library
#

#
# Routines
#       These are the routines exported by the library
#
incminor

export	BSMIXERGETSTATE
export	BSMIXERGETSUBTOKEN
export	BSMIXERSPECVALUE
export  BSMIXERLOADDRIVER
export	BSMIXERGETCAP
export	BSMIXERGETVALUE
export	BSMIXERSETVALUE
export	BSMIXERGETTOKENTEXT

#usernotes "Mixerlibrary to control the soundcard levels \xa9 1998-2000 Dirk Lausecker"