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
