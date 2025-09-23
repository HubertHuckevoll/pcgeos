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

export TransGetImportUI
export TransGetExportUI
export TransInitImportUI
export TransInitExportUI
export TransGetImportOptions
export TransGetExportOptions
export TransImport
export TransExport
export TransGetFormat
