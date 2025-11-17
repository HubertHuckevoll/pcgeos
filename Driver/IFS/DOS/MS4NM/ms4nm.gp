##############################################################################
#
#       Copyright (c) Breadbox Ensemble 2024 -- All Rights Reserved
#
# PROJECT:      PC GEOS
# MODULE:       MS DOS NetMount IFS Driver
# FILE:         ms4nm.gp
#
# AUTHOR:       FreeGEOS Maintainers
#
#       A NetMount-aware build of the classic MS4 IFS driver.
#
##############################################################################
#
name ms4nm.ifsd
type driver, single system
library geos

#
# Desktop-related things
#
longname "MS DOS 4.X NetMount IFS Driver"
tokenchars "IFSD"
tokenid 0

#
# Special resource definitions
#
ifdef GP_FULL_EXECUTE_IN_PLACE
resource Resident               code shared read-only
resource ResidentXIP            fixed code shared read-only
else
resource Resident               fixed code shared read-only
endif
resource DriverExtendedInfo     lmem shared read-only
resource Strings                fixed lmem read-only shared
#
# XIP-enabled
#
