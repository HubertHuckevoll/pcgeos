name veneersample.lib

longname "Veneer Sample Translator"
tokenchars "TVEN"
tokenid 0

type library, single

entry LibraryEntry

library geos
library ui
library impex
library text
library ansic

nosort
resource ResidentCode code read-only shared
resource InfoResource lmem read-only shared
resource VeneerUI ui-object read-only

export TransGetImportUI
export TransGetExportUI
export TransInitImportUI
export TransInitExportUI
export TransGetImportOptions
export TransGetExportOptions
export TransImport
export TransExport
export TransGetFormat
