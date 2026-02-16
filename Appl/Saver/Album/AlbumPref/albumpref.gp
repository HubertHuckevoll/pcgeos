##############################################################################
#
#	Copyright (c) GeoWorks 1992 -- All Rights Reserved
#
# PROJECT:	Preferences
# MODULE:	
# FILE:		albumpref.gp
#
##############################################################################
#
# Permanent name
#
name albumpf.lib
#
# Long name
#
longname "Album Options"
#
# Desktop-related definitions
#
tokenchars "PREF"
tokenid 0
#
# Specify geode type
#
type	library, single
#

# Import library routine definitions
#
library	geos
library	ui
library config
#
# Define resources other than standard discardable code
#
nosort
resource AlbumOptions	object

#
# Exported routines. These MUST be exported first, and they must be
# in the same order as the PrefModuleEntryType etype
#

export AlbumPrefGetPrefUITree
export AlbumPrefGetModuleInfo
