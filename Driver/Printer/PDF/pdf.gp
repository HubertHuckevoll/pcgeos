##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     Native PDF Printer Driver
# FILE:       pdf.gp
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Geode parameters for the file-only native PDF printer.
#     Import the PDF library and standard GEOS spooler support.
#
##############################################################################

name pdf.drvr
longname "Native PDF Printer Driver"
tokenchars "PRDR"
tokenid 0
type driver, single
library geos
library spool
library pdf
resource Entry fixed code read-only shared
resource CommonCode code read-only shared
resource DriverInfo data shared read-only conforming lmem
resource pdfDeviceInfo data shared read-only conforming
