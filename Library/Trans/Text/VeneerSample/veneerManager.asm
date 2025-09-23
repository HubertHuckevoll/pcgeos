include geos.def
include impex.def
include Library/Trans/TransCommon/transCommonGlobal.def

TransVeneerHeader InfoResource, 1, mask IDC_TEXT
TransVeneerImportUI      TransGetImportUIHelper
TransVeneerExportUI      TransGetExportUIHelper
TransVeneerInitImportUI  TransInitImportUIHelper
TransVeneerInitExportUI  TransInitExportUIHelper
TransVeneerImportOptions TransGetImportOptionsHelper
TransVeneerExportOptions TransGetExportOptionsHelper

include Library/Trans/TransCommon/transCStub.asm
