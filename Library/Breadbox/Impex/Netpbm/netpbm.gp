name netpbm.lib

#long GEOS name
longname "Netpbm Translator"

#fixed Token for images converters: Translator Graphics
tokenchars "TLGR"
tokenid 0

#Library which can loaded only once at the same time
type library, single

#entry function for the library, defined in asm file
entry LibraryEntry

library geos
library ui
library impex
library extgraph
library ansic
#library color
#library pnglib

#UI objects for import and export dialogs
#Objects are defined in ui.goc
#resource ExportInterface object
#resource ImportInterface object

#Functions exported by the library, expected by Impex
export TransGetImportUI
export TransGetExportUI
export TransInitImportUI
export TransInitExportUI
export TransGetImportOptions
export TransGetExportOptions
export TransImport
export TransExport
export TransGetFormat

#export PngImportGroupClass