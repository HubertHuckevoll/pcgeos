COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        Copyright (c) GeoWorks 1992-2024 -- All Rights Reserved

PROJECT:        PC GEOS
MODULE:         Translation Libraries
FILE:           transCStub.asm

AUTHOR:         ChatGPT, 3 Apr 2024

DESCRIPTION:
        Shared veneer that marshals between the Impex register ABI and
        translator-supplied C helpers.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include stdapp.def
include vm.def
include impex.def
include Objects/gCtrlC.def
include Internal/xlatLib.def

ifndef  TRANS_STRINGS_RESOURCE
ErrMessage      <TRANS_STRINGS_RESOURCE must be defined before including transCStub.asm>
endif

ifndef  TRANS_FORMAT_COUNT
ErrMessage      <TRANS_FORMAT_COUNT must be defined before including transCStub.asm>
endif

ifndef  TRANS_DATA_CLASS
ErrMessage      <TRANS_DATA_CLASS must be defined before including transCStub.asm>
endif

ifndef  TRANS_EXPORT_HELPER
TRANS_EXPORT_HELPER      textequ <EXPORTPROCEDURE>
endif

ifndef  TRANS_IMPORT_HELPER
TRANS_IMPORT_HELPER      textequ <IMPORTPROCEDURE>
endif

ifndef  TRANS_GETFORMAT_HELPER
TRANS_GETFORMAT_HELPER   textequ <GETFORMAT>
endif

ifndef  TRANS_IMPORT_UI_HELPER
TRANS_IMPORT_UI_HELPER   textequ <TransStubDefaultGetImportUI>
endif

ifndef  TRANS_EXPORT_UI_HELPER
TRANS_EXPORT_UI_HELPER   textequ <TransStubDefaultGetExportUI>
endif

ifndef  TRANS_INIT_IMPORT_UI_HELPER
TRANS_INIT_IMPORT_UI_HELPER      textequ <TransStubDefaultInitImportUI>
endif

ifndef  TRANS_INIT_EXPORT_UI_HELPER
TRANS_INIT_EXPORT_UI_HELPER      textequ <TransStubDefaultInitExportUI>
endif

ifndef  TRANS_IMPORT_OPTIONS_HELPER
TRANS_IMPORT_OPTIONS_HELPER      textequ <TransStubDefaultGetImportOptions>
endif

ifndef  TRANS_EXPORT_OPTIONS_HELPER
TRANS_EXPORT_OPTIONS_HELPER      textequ <TransStubDefaultGetExportOptions>
endif

TransStub_TEXT   segment byte public 'CODE'
        extrn   TRANS_EXPORT_HELPER:far
        extrn   TRANS_IMPORT_HELPER:far
        extrn   TRANS_GETFORMAT_HELPER:far

ifdifi <TRANS_IMPORT_UI_HELPER>,<TransStubDefaultGetImportUI>
        extrn   TRANS_IMPORT_UI_HELPER:far
endif

ifdifi <TRANS_EXPORT_UI_HELPER>,<TransStubDefaultGetExportUI>
        extrn   TRANS_EXPORT_UI_HELPER:far
endif

ifdifi <TRANS_INIT_IMPORT_UI_HELPER>,<TransStubDefaultInitImportUI>
        extrn   TRANS_INIT_IMPORT_UI_HELPER:far
endif

ifdifi <TRANS_INIT_EXPORT_UI_HELPER>,<TransStubDefaultInitExportUI>
        extrn   TRANS_INIT_EXPORT_UI_HELPER:far
endif

ifdifi <TRANS_IMPORT_OPTIONS_HELPER>,<TransStubDefaultGetImportOptions>
        extrn   TRANS_IMPORT_OPTIONS_HELPER:far
endif

ifdifi <TRANS_EXPORT_OPTIONS_HELPER>,<TransStubDefaultGetExportOptions>
        extrn   TRANS_EXPORT_OPTIONS_HELPER:far
endif
TransStub_TEXT   ends

public  LibraryEntry
public  TransExport
public  TransImport
public  TransGetFormat
public  TransGetImportUI
public  TransGetExportUI
public  TransInitImportUI
public  TransInitExportUI
public  TransGetImportOptions
public  TransGetExportOptions

ResidentCode    segment resource
        assume  cs:ResidentCode

TranslationHeader label byte
        TranslationLibraryHeader \
                <TLH_VALID, TRANS_STRINGS_RESOURCE, TRANS_FORMAT_COUNT,\
                TRANS_DATA_CLASS, TLH_VALID>

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                LibraryEntry
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Default translation library entry point

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

LibraryEntry    proc    far
        clc
        ret
LibraryEntry    endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransExport
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Export entry that forwards to the translator's C helper

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransExport     proc    far
        uses    es, ds, si, di
        .enter
                push    ds
                push    si
                mov     ax, idata
                mov     ds, ax
                call    TRANS_EXPORT_HELPER
        .leave
        ret
TransExport     endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransImport
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Import entry that forwards to the translator's C helper

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransImport     proc    far
        uses    es, ds, si, di
_vmResult       local   dword
        .enter
                push    ds
                push    si
                push    ss
                lea     ax, _vmResult
                push    ax
                mov     ax, idata
                mov     ds, ax
                call    TRANS_IMPORT_HELPER
                mov     bx, dx
                mov     dx, word ptr _vmResult
                mov     cx, word ptr _vmResult+2
        .leave
        ret
TransImport     endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransGetFormat
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Format identification entry

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransGetFormat  proc    far
        uses    es, ds, si, di
        .enter
                push    si
                mov     ax, idata
                mov     ds, ax
                call    TRANS_GETFORMAT_HELPER
                mov     cx, ax
                xor     ax, ax
        .leave
        retf
TransGetFormat  endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransGetImportUI
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional import UI query

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransGetImportUI        proc    far
        uses    ds, si, di
_uiRoot         local   dword
_uiClass        local   dword
        .enter
                mov     word ptr _uiRoot, 0
                mov     word ptr _uiRoot+2, 0
                mov     word ptr _uiClass, 0
                mov     word ptr _uiClass+2, 0
                mov     ax, idata
                mov     ds, ax
                push    cx
                push    ss
                lea     ax, _uiRoot
                push    ax
                push    ss
                lea     ax, _uiClass
                push    ax
                call    TRANS_IMPORT_UI_HELPER
                mov     dx, word ptr _uiRoot
                mov     cx, word ptr _uiRoot+2
                mov     ax, word ptr _uiClass
                mov     bx, word ptr _uiClass+2
        .leave
        ret
TransGetImportUI        endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransGetExportUI
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional export UI query

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransGetExportUI        proc    far
        uses    ds, si, di
_uiRoot         local   dword
_uiClass        local   dword
        .enter
                mov     word ptr _uiRoot, 0
                mov     word ptr _uiRoot+2, 0
                mov     word ptr _uiClass, 0
                mov     word ptr _uiClass+2, 0
                mov     ax, idata
                mov     ds, ax
                push    cx
                push    ss
                lea     ax, _uiRoot
                push    ax
                push    ss
                lea     ax, _uiClass
                push    ax
                call    TRANS_EXPORT_UI_HELPER
                mov     dx, word ptr _uiRoot
                mov     cx, word ptr _uiRoot+2
                mov     ax, word ptr _uiClass
                mov     bx, word ptr _uiClass+2
        .leave
        ret
TransGetExportUI        endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransInitImportUI
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional import UI initializer

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransInitImportUI       proc    far
        uses    ds
        .enter
                mov     ax, idata
                mov     ds, ax
                push    dx
                push    cx
                call    TRANS_INIT_IMPORT_UI_HELPER
        .leave
        ret
TransInitImportUI       endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransInitExportUI
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional export UI initializer

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransInitExportUI       proc    far
        uses    ds
        .enter
                mov     ax, idata
                mov     ds, ax
                push    dx
                push    cx
                call    TRANS_INIT_EXPORT_UI_HELPER
        .leave
        ret
TransInitExportUI       endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransGetImportOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional import options collector

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransGetImportOptions   proc    far
        uses    ds
        .enter
                mov     ax, idata
                mov     ds, ax
                push    cx
                push    dx
                call    TRANS_IMPORT_OPTIONS_HELPER
                mov     dx, ax
                xor     ax, ax
        .leave
        ret
TransGetImportOptions   endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                TransGetExportOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Optional export options collector

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransGetExportOptions   proc    far
        uses    ds
        .enter
                mov     ax, idata
                mov     ds, ax
                push    cx
                push    dx
                call    TRANS_EXPORT_OPTIONS_HELPER
                mov     dx, ax
                xor     ax, ax
        .leave
        ret
TransGetExportOptions   endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                Default helper implementations
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

TransStubDefaultGetImportUI proc far
        push    bp
        mov     bp, sp
        push    es
        les     di, [bp+6]
        mov     word ptr es:[di], 0
        mov     word ptr es:[di+2], 0
        les     di, [bp+10]
        mov     word ptr es:[di], 0
        mov     word ptr es:[di+2], 0
        pop     es
        pop     bp
        retf    10
TransStubDefaultGetImportUI endp

TransStubDefaultGetExportUI proc far
        push    bp
        mov     bp, sp
        push    es
        les     di, [bp+6]
        mov     word ptr es:[di], 0
        mov     word ptr es:[di+2], 0
        les     di, [bp+10]
        mov     word ptr es:[di], 0
        mov     word ptr es:[di+2], 0
        pop     es
        pop     bp
        retf    10
TransStubDefaultGetExportUI endp

TransStubDefaultInitImportUI proc far
        retf    4
TransStubDefaultInitImportUI endp

TransStubDefaultInitExportUI proc far
        retf    4
TransStubDefaultInitExportUI endp

TransStubDefaultGetImportOptions proc far
        xor     ax, ax
        retf    4
TransStubDefaultGetImportOptions endp

TransStubDefaultGetExportOptions proc far
        xor     ax, ax
        retf    4
TransStubDefaultGetExportOptions endp

ResidentCode    ends

        end
