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

InfoResource    segment lmem LMEM_TYPE_GENERAL, mask LMF_IN_RESOURCE

infoTable       dw      fmt_name, fmt_mask
                D_OPTR  VeneerImportDialog
                D_OPTR  VeneerExportDialog
                ImpexFormatInfo <mask IFI_IMPORT_CAPABLE or \
                                 mask IFI_EXPORT_CAPABLE>

fmt_name        chunk   char
        char    "Veneer sample",0
fmt_name        endc

fmt_mask        chunk   char
        char    "*.txt",0
fmt_mask        endc

InfoResource    ends
