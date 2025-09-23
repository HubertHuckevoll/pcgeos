include geos.def
include impex.def
include Library/Trans/TransCommon/transCommonGlobal.def

VENEER_SAMPLE_FORMAT_COUNT    equ     2

TransVeneerHeader InfoResource, VENEER_SAMPLE_FORMAT_COUNT, mask IDC_TEXT
TransVeneerImportUI      TransGetImportUIHelper
TransVeneerExportUI      TransGetExportUIHelper
TransVeneerInitImportUI  TransInitImportUIHelper
TransVeneerInitExportUI  TransInitExportUIHelper
TransVeneerImportOptions TransGetImportOptionsHelper
TransVeneerExportOptions TransGetExportOptionsHelper

include Library/Trans/TransCommon/transCStub.asm
