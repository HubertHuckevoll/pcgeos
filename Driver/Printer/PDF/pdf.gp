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
