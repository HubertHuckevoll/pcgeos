##############################################################################
#
#	Copyright (C) 2000 Dirk Lausecker -- All Rights Reserved
#
# PROJECT:	BestSound
# MODULE:	Soundcheck
# FILE:		bsqp.gp
#
# AUTHOR:	Dirk Lausecker
#
# DESCRIPTION:
#
##############################################################################

name sndchk.app

longname "SoundCheck"

type	appl, process, single

class	SDCKProcessClass

appobj	SDCKApp

tokenchars "SDCK"
tokenid 16427

heapspace 5000

library	geos
library	ui
library bsnwav
library wav
library	ansic
library sound
#
# Libraries exempt from checking
#
#exempt bsnwav
#exempt wav

resource AppResource 		ui-object
resource Interface 		ui-object
# resource UIMainInfoResource 	ui-object
resource APPLMONIKERRESOURCE 	data object read-only
resource MONIKERRESOURCE 	data object read-only
resource MAINGROUPRESOURCE	ui-object
resource MENURESOURCE		ui-object
resource MAINTEXTOBJRESOURCE 	ui-object

# usernotes "� 2000 D. Lausecker"
