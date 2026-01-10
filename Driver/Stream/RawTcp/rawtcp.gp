##############################################################################
#
#	Copyright (c) GeoWorks 2024 -- All Rights Reserved
#
# PROJECT:	PC GEOS
# MODULE:	RawTcp Stream Driver
# FILE:		rawtcp.gp
#
# AUTHOR:	OpenAI Assistant
#
##############################################################################
#
# Specify permanent name first
#
name	rawtcp.drvr
#
# Specify geode type
#
type	driver, single
#
# Import kernel routine definitions
#
library	geos
library	socket

driver	stream
#
# Desktop-related things
#
longname	"RawTcp Stream Driver"
tokenchars	"ISTR"
tokenid		0
#
# Define resources other than standard discardable code
#
resource Resident fixed code read-only shared
#
# Exported routines
#
export	RawTcpStrategy
#
# XIP-enabled
#
