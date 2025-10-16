##############################################################################
#
#	Copyright (C) 2000 Dirk Lausecker -- All Rights Reserved
#
# PROJECT:	BestSound
# MODULE:	Soundcheck
# FILE:		bsqp.gp
#
#
# DESCRIPTION:
#
##############################################################################

name testmp3.app

longname "TestMP3"

type	appl, process, single

class	TestMP3ProcessClass

appobj	AppObj

tokenchars "TMP3"
tokenid 0

heapspace 5000
stack 8000

library	geos
library	ui
library bsnwav
library	ansic
library sound
#
# Libraries exempt from checking
#
#exempt bsnwav
#exempt wav

resource AppResource 		ui-object
resource Interface 		ui-object
