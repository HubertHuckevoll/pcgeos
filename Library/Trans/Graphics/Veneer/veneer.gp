name veneer.lib

longname "Veneer Translator"

tokenchars "VNRX"
tokenid 0

type library, single

entry LibraryEntry

library geos
library ui
library impex

resource ResidentCode read-only data shared
resource InfoResource lmem read-only shared

export TransGetImportUI
export TransGetExportUI
export TransInitImportUI
export TransInitExportUI
export TransGetImportOptions
export TransGetExportOptions
export TransImport
export TransExport
export TransGetFormat
