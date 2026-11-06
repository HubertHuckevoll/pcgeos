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
