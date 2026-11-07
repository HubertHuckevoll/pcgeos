##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     Native PDF Translation Library
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
#     Geode parameters for the streaming PDF 1.1 translation library.
#     Exported symbol order forms the stable C/assembly library ABI.
#
##############################################################################

name pdf.lib
longname "Native PDF Translation"
tokenchars "TLPD"
tokenid 0
type library, single, c-api
library geos
library ansic
resource PdfCode code read-only shared
# Append new exports; keep ordinal order stable.
export PDFCREATE
export PDFSTARTPAGE
export PDFSETTRANSFORM
export PDFGSTRING
export PDFENDPAGE
export PDFDESTROY
