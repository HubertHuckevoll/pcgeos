##############################################################################
#
#	Copyright (C) 2000 Dirk Lausecker -- All Rights Reserved
#
# PROJECT:	BestSound
# MODULE:	BestSound QuickPlayer
# FILE:		bsqp.gp
#
# AUTHOR:	Dirk Lausecker
#
# DESCRIPTION:
#
##############################################################################

name bsqp.app

longname "WAV QuickPlayer"

type	appl, process, single

class	BSQPProcessClass


appobj	BSQPApp

tokenchars "BSQP"
tokenid 16427

heapspace 	10000
stack		5000

library	geos
library	ui
library bsnwav
# library bswav
library	ansic
library sound

#exempt bsnwav
#exempt bswav

resource AppResource 		ui-object
resource Interface 		ui-object
resource UIMainInfoResource 	ui-object
resource DISPLAYRESOURCE	ui-object
resource SELECTORRESOURCE	ui-object
resource OPTIONSMENURESOURCE	ui-object

resource APPLMONIKERRESOURCE 	data object read-only

export	BSQPApplicationClass
export	BSQPPrimaryClass

# usernotes "� D.Lausecker\x0dWAV-Quickplayer is licensed to NewDeal and is subject to its conditions of use."
