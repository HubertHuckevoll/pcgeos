include geos.def
include impex.def
include Library/Trans/TransCommon/transCommonGlobal.def

TransVeneerHeader InfoResource, 1, mask IDC_TEXT

include Library/Trans/TransCommon/transCStub.asm

InfoResource    segment lmem LMEM_TYPE_GENERAL, mask LMF_IN_RESOURCE

infoTable       dw      fmt_name, fmt_mask
                D_OPTR  0
                dw      0, 0
                dw      0C000h

                dw      0

fmt_name        chunk   char
        char    "Veneer sample",0
fmt_name        endc

fmt_mask        chunk   char
        char    "*.txt",0
fmt_mask        endc

InfoResource    ends
