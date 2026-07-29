include stdapp.def
include vm.def
include Objects/gCtrlC.def

UseLib math.def

;
; EC-only SVG export breadcrumbs. Keep this order synchronized with
; VCImpexWarning in vconv_ui.h.
;
VCIMPEX_WARNING_TRANS_EXPORT_ENTERED		enum	Warnings
VCIMPEX_WARNING_EXPORT_PROCEDURE_ENTERED	enum	Warnings
VCIMPEX_WARNING_LOAD_GSTRING_RETURNED		enum	Warnings
VCIMPEX_WARNING_BUFFER_HEAP_ALLOC_RETURNED	enum	Warnings
VCIMPEX_WARNING_VALIDATION_ENTERED		enum	Warnings
VCIMPEX_WARNING_VALIDATION_RETURNED		enum	Warnings
VCIMPEX_WARNING_BOUNDS_ENTERED			enum	Warnings
VCIMPEX_WARNING_BOUNDS_RETURNED			enum	Warnings
VCIMPEX_WARNING_OUTPUT_FILE_READY		enum	Warnings
VCIMPEX_WARNING_INIT_WRITER_RETURNED		enum	Warnings
VCIMPEX_WARNING_EXPORT_GSTRING_ENTERED		enum	Warnings
VCIMPEX_WARNING_PLAYBACK_HEAP_ALLOC_RETURNED	enum	Warnings
VCIMPEX_WARNING_CREATE_PLAYBACK_GSTRING_RETURNED	enum	Warnings
VCIMPEX_WARNING_WRITE_HEADER_RETURNED		enum	Warnings
VCIMPEX_WARNING_DRAW_LOOP_ENTERED		enum	Warnings
VCIMPEX_WARNING_DRAW_LOOP_LEFT			enum	Warnings
VCIMPEX_WARNING_PLAYBACK_GSTRING_DESTROY_ENTERED enum	Warnings
VCIMPEX_WARNING_PLAYBACK_GSTRING_DESTROY_RETURNED enum	Warnings
VCIMPEX_WARNING_EXPORT_GSTRING_RETURNED		enum	Warnings
VCIMPEX_WARNING_BUFFER_HEAP_FREE_ENTERED	enum	Warnings
VCIMPEX_WARNING_BUFFER_HEAP_FREE_RETURNED	enum	Warnings
VCIMPEX_WARNING_SOURCE_GSTRING_DESTROY_ENTERED	enum	Warnings
VCIMPEX_WARNING_SOURCE_GSTRING_DESTROY_RETURNED	enum	Warnings
VCIMPEX_WARNING_EXPORT_PROCEDURE_RETURNING	enum	Warnings
VCIMPEX_WARNING_TRANS_EXPORT_RETURNED		enum	Warnings

global _booleanOptions: nptr
global _ImportSettings: nptr

; segment must be "public 'CODE'" to ensure that it combines
; with properly the C segment of the same name.

imptproc_TEXT   segment public 'CODE'
  extrn  IMPORTPROCEDURE: far
  extrn  GETFORMAT: far
imptproc_TEXT   ends

svgexpproc_TEXT segment public 'CODE'
  extrn  EXPORTPROCEDURE: far
svgexpproc_TEXT ends

global  LibraryEntry: far
global  TransExport: far
global  TransImport: far
global  TransGetFormat: far
global  TransGetImportUI: far
global  TransGetExportUI: far
global  TransInitImportUI: far
global  TransInitExportUI: far
global  TransGetImportOptions: far
global  TransGetExportOptions: far


INIT    segment resource
        assume cs:INIT

        db      "OK"
        dw      InfoResource            ; resource containing format names
        dw      3                       ; contains three sub-formats
        dw      4000h                   ; this is a graphics translator
        db      "OK"

LibraryEntry proc far
        clc
        ret
LibraryEntry endp

INIT    ends


ASM     segment resource
        assume cs:ASM

TransExport proc far
        uses    es,ds,si,di
        .enter
EC <      WARNING VCIMPEX_WARNING_TRANS_EXPORT_ENTERED			>
          push    ds
          push    si
          mov     ax,idata              ; DS=dgroup
          mov     ds,ax
          call    EXPORTPROCEDURE
EC <      WARNING VCIMPEX_WARNING_TRANS_EXPORT_RETURNED			>
          mov     bx,dx
        .leave
        ret
TransExport endp

TransImport proc far
        uses    es,ds,si,di
_vmc    local   dword
        .enter
          push    ds                    ; arg 1: pointer to impex data block
          push    si
          push    ss                    ; arg 2: pointer to vm chain return buf
          lea     ax,_vmc
          push    ax
          mov     ax,idata              ; DS=dgroup for high-level code
          mov     ds,ax
          mov     ax,25                 ; Allocate default float stack size
          mov     bl,FLOAT_STACK_GROW
          call    FloatInit
          call    IMPORTPROCEDURE       ; Call high-level procedure to do work
          call    FloatExit
          mov     bx,dx                 ; BX:AX returns error code or format ID
          movdw   dxcx,_vmc             ; VMChain of object returned in DX:CX
        .leave
        ret
TransImport endp

TransGetFormat proc far
        uses    es,ds,si,di,bx,dx
        .enter
          push    si                    ; handle of file to be tested
          mov     ax,idata              ; DS=dgroup for GOC code
          mov     ds,ax
          call    GETFORMAT             ; Call high-level procedure to do work
          mov     cx,ax                 ; return format number
          xor     ax,ax                 ; no error
        .leave
        retf
TransGetFormat endp

TransGetImportUI proc far
        mov     bp,00004h
        push    di
        push    ds
        mov     bx,handle InfoResource
        call    MemLock
        mov     ds,ax
        mov     ax,0000Eh
        mul     cx
        mov     di,00010h
        add     di,ax
        mov     cx,[ds:bp+di+002h]
        mov     dx,[ds:bp+di]
        call    MemUnlock
        xor     ax,ax
        mov     bx,ax
        pop     ds
        pop     di
        ret
TransGetImportUI endp

TransGetExportUI proc far
        xor     cx,cx
        ret
TransGetExportUI endp

TransGetImportOptions proc far
        push    ax
        push    cx
        push    bx
        push    bp
        push    si
        push    di
        push    ds

        cmp     dx,0
        jne     iopt_query_ui
        mov     ax,8001h                 ; SETTINGS_DOARCS | SETTINGS_DOTEXT defaults
        jmp     short iopt_have_options
iopt_query_ui:
        mov     ax,MSG_GEN_BOOLEAN_GROUP_GET_SELECTED_BOOLEANS
        mov     bx,dx
        mov     si,offset _booleanOptions
        mov     di,mask MF_CALL
        call    ObjMessage

iopt_have_options:
        push    ax
        mov     ax,00002h
        mov     cl,050h
        mov     ch,040h
        call    MemAlloc
        xor     dx,dx
        jc      iopt_discard_saved
        push    ax
        pop     ds
        pop     ax
        mov     [ds:00000h],ax          ; booleanOptions
        call    MemUnlock
        mov     dx,bx
        clc
        jmp     short iopt_exit
iopt_discard_saved:
        pop     ax
iopt_exit:
        pop     ds
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     cx
        pop     ax
        ret
TransGetImportOptions endp

TransGetExportOptions proc far
        xor     dx,dx
        ret
TransGetExportOptions endp

TransInitImportUI proc far
        ret
TransInitImportUI endp

TransInitExportUI proc far
        ret
TransInitExportUI endp

ASM     ends


InfoResource    segment lmem LMEM_TYPE_GENERAL,mask LMF_IN_RESOURCE

        dw      fmt_1_name,fmt_1_mask
          D_OPTR  _ImportSettings
          dw      0,0
          dw      08000h

        dw      fmt_2_name,fmt_2_mask
          D_OPTR  _ImportSettings
          dw      0,0
          dw      08000h

        dw      fmt_3_name,fmt_3_mask
          D_OPTR  0
          dw      0,0
          dw      0C000h

        dw      0

fmt_1_name      chunk   char
        char    "CGM",0
fmt_1_name      endc

fmt_1_mask      chunk   char
        char    "*.cgm",0
fmt_1_mask      endc

fmt_2_name      chunk   char
        char    "HPGL",0
fmt_2_name      endc

fmt_2_mask      chunk   char
        char    "*.plt",0
fmt_2_mask      endc

fmt_3_name      chunk   char
        char    "SVG",0
fmt_3_name      endc

fmt_3_mask      chunk   char
        char    "*.svg",0
fmt_3_mask      endc

InfoResource    ends
