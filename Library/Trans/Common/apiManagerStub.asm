include stdapp.def
include xlatLib.def
include geos.def
include resource.def

TransFormatInfo struct
    TFI_importUI        dword
    TFI_exportUI        dword
    TFI_formatFlags     word
TransFormatInfo ends

TransDescriptor struct
    TD_formats              dword
    TD_formatCount          word
    TD_dataClass            word
    TD_importProc           dword
    TD_exportProc           dword
    TD_testProc             dword
    TD_getImportOptionsProc dword
    TD_getExportOptionsProc dword
    TD_initImportUICallback dword
    TD_initExportUICallback dword
TransDescriptor ends

idata segment
XLAT_descriptorOffset   dw 0
XLAT_descriptorSegment  dw 0
idata ends

extrn   XLAT_GetDescriptor:far

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

CommonCode segment resource

GetDescriptor proc near
        push    ds
        mov     ax, idata
        mov     ds, ax
        mov     ax, XLAT_descriptorOffset
        mov     dx, XLAT_descriptorSegment
        or      ax, dx
        jne     descriptorReady
        call    far ptr XLAT_GetDescriptor
        mov     XLAT_descriptorOffset, ax
        mov     XLAT_descriptorSegment, dx
        jmp     short descriptorLoaded

descriptorReady:
        mov     ax, XLAT_descriptorOffset
        mov     dx, XLAT_descriptorSegment

descriptorLoaded:
        pop     ds
        ret
GetDescriptor endp

ResetDescriptor proc near
        push    ds
        mov     ax, idata
        mov     ds, ax
        xor     ax, ax
        mov     XLAT_descriptorOffset, ax
        mov     XLAT_descriptorSegment, ax
        pop     ds
        ret
ResetDescriptor endp

LibraryEntry proc far
        call    ResetDescriptor
        clc
        ret
LibraryEntry endp

GetFormatEntry proc near
; CX = format index
; returns ES:BX -> TransFormatInfo, carry set if invalid
        push    ax
        push    dx
        push    ds
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        mov     ax, [si].TransDescriptor.TD_formatCount
        cmp     cx, ax
        jae     formatInvalid
        les     bx, [si].TransDescriptor.TD_formats
        mov     ax, cx
        mov     dx, size TransFormatInfo
        mul     dx
        add     bx, ax
        clc
        jmp     short formatDone

formatInvalid:
        stc

formatDone:
        pop     ds
        pop     dx
        pop     ax
        ret
GetFormatEntry endp

TransImport proc far uses es ds si di
_vmChain        local   dword
        .enter
        mov     word ptr _vmChain, 0
        mov     word ptr _vmChain+2, 0
        push    ds
        push    si
        push    ss
        lea     ax, _vmChain
        push    ax
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_importProc
        mov     ax, es
        or      ax, bx
        je      importMissing
        call    far es:[bx]
        mov     bx, dx
        mov     cx, word ptr _vmChain
        mov     dx, word ptr _vmChain+2
        .leave
        ret

importMissing:
        mov     ax, TE_ERROR
        mov     bx, 0
        mov     cx, 0
        mov     dx, 0
        .leave
        ret
TransImport endp

TransExport proc far uses es ds si di
        .enter
        push    ds
        push    si
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_exportProc
        mov     ax, es
        or      ax, bx
        je      exportMissing
        call    far es:[bx]
        mov     bx, dx
        .leave
        ret

exportMissing:
        mov     ax, TE_ERROR
        mov     bx, 0
        mov     cx, 0
        mov     dx, 0
        .leave
        ret
TransExport endp

TransGetFormat proc far uses es ds si di
        .enter
        push    si
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_testProc
        mov     ax, es
        or      ax, bx
        je      formatUnknown
        call    far es:[bx]
        mov     cx, ax
        xor     ax, ax
        .leave
        ret

formatUnknown:
        mov     cx, NO_IDEA_FORMAT
        xor     ax, ax
        .leave
        ret
TransGetFormat endp

TransGetImportUI proc far uses ax bx dx si di
        call    GetFormatEntry
        jc      noImportUI
        mov     cx, es:[bx].TransFormatInfo.TFI_importUI+2
        mov     dx, es:[bx].TransFormatInfo.TFI_importUI
        xor     ax, ax
        xor     bx, bx
        ret

noImportUI:
        xor     ax, ax
        xor     bx, bx
        xor     cx, cx
        xor     dx, dx
        ret
TransGetImportUI endp

TransGetExportUI proc far uses ax bx dx si di
        call    GetFormatEntry
        jc      noExportUI
        mov     cx, es:[bx].TransFormatInfo.TFI_exportUI+2
        mov     dx, es:[bx].TransFormatInfo.TFI_exportUI
        xor     ax, ax
        xor     bx, bx
        ret

noExportUI:
        xor     ax, ax
        xor     bx, bx
        xor     cx, cx
        xor     dx, dx
        ret
TransGetExportUI endp

TransGetImportOptions proc far uses ax bx cx si di ds es
        .enter
        push    dx
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_getImportOptionsProc
        mov     ax, es
        or      ax, bx
        je      noImportOptions
        call    far es:[bx]
        mov     dx, ax
        .leave
        ret

noImportOptions:
        xor     ax, ax
        xor     dx, dx
        .leave
        ret
TransGetImportOptions endp

TransGetExportOptions proc far uses ax bx cx si di ds es
        .enter
        push    dx
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_getExportOptionsProc
        mov     ax, es
        or      ax, bx
        je      noExportOptions
        call    far es:[bx]
        mov     dx, ax
        .leave
        ret

noExportOptions:
        xor     ax, ax
        xor     dx, dx
        .leave
        ret
TransGetExportOptions endp

TransInitImportUI proc far uses ax bx cx si di ds es
        .enter
        push    dx
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_initImportUICallback
        mov     ax, es
        or      ax, bx
        je      noImportInit
        call    far es:[bx]
noImportInit:
        .leave
        ret
TransInitImportUI endp

TransInitExportUI proc far uses ax bx cx si di ds es
        .enter
        push    dx
        call    GetDescriptor
        mov     ds, dx
        mov     si, ax
        les     bx, [si].TransDescriptor.TD_initExportUICallback
        mov     ax, es
        or      ax, bx
        je      noExportInit
        call    far es:[bx]
noExportInit:
        .leave
        ret
TransInitExportUI endp

CommonCode ends

end
