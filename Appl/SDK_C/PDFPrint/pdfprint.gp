##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     Native PDF Printer Test Application
# FILE:       pdfprint.gp
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Geode parameters for a normal PrintControl test application.
#     The application exercises the native PDF printer through the spooler.
#
##############################################################################

name pdfprint.app
longname "PDF Print Test"
tokenchars "PDFT"
tokenid 8
type appl, process, single
class PDFPrintProcessClass
appobj PDFPrintApp
heapspace 4000
stack 3000
library geos
library ui
library spool
resource Application ui-object
resource Interface ui-object
