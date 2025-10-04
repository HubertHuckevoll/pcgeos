COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        BestSound Mixer assembly helpers -
        Assembly routines that talk to the mixer portion of the sound
        driver so we can keep inline assembly out of mixlib.goc.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include driver.def
include geode.def
include library.def
include ec.def

include dirk.def
include dirksnd.def

UseDriver Internal/soundDrv.def

DefLib  mixlib.def

        SetGeosConvention       ; set calling convention

; Extension of the soundcard driver
; Mixer
;DRE_SOUND_DAC_CHECK_SAMPLE_RATE_AND_FORMAT      equ     01Ch
DRE_BSMIXER_GET_CAP                             equ     022h
DRE_BSMIXER_GET_VALUE                           equ     024h
DRE_BSMIXER_SET_VALUE                           equ     026h
DRE_BSMIXER_SET_DEFAULT                         equ     028h
DRE_BSMIXER_TOKEN_TO_TEXT                       equ     02Ah
DRE_BSMIXER_SPEC_VALUE                          equ     02Ch
DRE_BSMIXER_GET_SUB_TOKEN                       equ     02Eh

global  MIXASMSETDRIVERINFO:far
global  MIXASMSETVALUE:far
global  MIXASMGETVALUE:far
global  MIXASMGETCAP:far
global  MIXASMTOKENTOTEXT:far
global  MIXASMGETSUBTOKEN:far
global  MIXASMSPECVALUE:far
global  MIXASMGETSTATE:far

udata segment
        driverInfo      fptr            ; far pointer to driver's DriverInfoStruct
udata ends

ASMTOOLS_TEXT   segment resource

;--------------------------------------------------------------------------
; MIXASMSETDRIVERINFO
;--------------------------------------------------------------------------
MIXASMSETDRIVERINFO proc far        driverHandle:word
        uses    bx, dx, si
        .enter

        push    ds
        mov     bx, driverHandle
        mov     dx, 0
        mov     ax, 0
        or      bx, bx
        jz      storePtr

        call    GeodeInfoDriver                 ; DS:SI -> DriverInfoStruct
        mov     dx, ds                          ; segment in DX
        mov     ax, si                          ; offset in AX

storePtr:
        pop     ds
        mov     ds:[driverInfo].segment, dx     ; store (segment, offset)
        mov     ds:[driverInfo].offset, ax

        .leave
        ret
MIXASMSETDRIVERINFO endp

;--------------------------------------------------------------------------
; MIXASMSETVALUE
;--------------------------------------------------------------------------
MIXASMSETVALUE proc far             token:word,
                                    valueLeft:word,
                                    valueRight:word
        uses    bx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_SET_VALUE
        mov     dx, token
        mov     al, byte ptr valueLeft
        mov     ah, byte ptr valueRight
        call    es:[si].DIS_strategy
        cld

        .leave
        ret
MIXASMSETVALUE endp

;--------------------------------------------------------------------------
; MIXASMGETVALUE
;--------------------------------------------------------------------------
MIXASMGETVALUE proc far             token:word
        uses    bx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_GET_VALUE
        mov     dx, token
        call    es:[si].DIS_strategy
        cld

        .leave
        ret
MIXASMGETVALUE endp

;--------------------------------------------------------------------------
; MIXASMGETCAP
;--------------------------------------------------------------------------
MIXASMGETCAP proc far               dspPtr:fptr
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_GET_CAP
        call    es:[si].DIS_strategy
        cld

        les     bx, dspPtr
        mov     es:[bx], dx
        mov     ax, cx

        .leave
        ret
MIXASMGETCAP endp

;--------------------------------------------------------------------------
; MIXASMTOKENTOTEXT
;--------------------------------------------------------------------------
MIXASMTOKENTOTEXT proc far          token:word,
                                    dest:fptr
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_TOKEN_TO_TEXT
        mov     cx, token
        mov     ax, dest.segment
        mov     bx, dest.offset
        call    es:[si].DIS_strategy
        cld

        .leave
        ret
MIXASMTOKENTOTEXT endp

;--------------------------------------------------------------------------
; MIXASMGETSUBTOKEN
;--------------------------------------------------------------------------
MIXASMGETSUBTOKEN proc far          token:word,
                                    identifier:word
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_GET_SUB_TOKEN
        mov     cx, token
        mov     dx, identifier
        call    es:[si].DIS_strategy
        cld

        .leave
        ret
MIXASMGETSUBTOKEN endp

;--------------------------------------------------------------------------
; MIXASMSPECVALUE
;--------------------------------------------------------------------------
MIXASMSPECVALUE proc far            valNum:word,
                                    rangePtr:fptr,
                                    tokenPtr:fptr,
                                    targetPtr:fptr,
                                    typePtr:fptr,
                                    sliderPtr:fptr,
                                    visiblePtr:fptr,
                                    stereoPtr:fptr
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_BSMIXER_SPEC_VALUE
        mov     dx, valNum
        call    es:[si].DIS_strategy
        cld

        ; store range (ax)
        les     di, rangePtr
        mov     es:[di], ax

        ; store token (bx)
        mov     ax, bx
        les     di, tokenPtr
        mov     es:[di], ax

        ; store target (dl)
        mov     al, dl
        les     di, targetPtr
        mov     es:[di], al

        ; store type (cl)
        mov     al, cl
        les     di, typePtr
        mov     es:[di], al

        ; store slider (ch)
        mov     al, ch
        les     di, sliderPtr
        mov     es:[di], al

        ; store visible flag (bit 7 of dh)
        mov     al, dh
        and     al, 080h
        les     di, visiblePtr
        mov     es:[di], al

        ; store stereo flag (bit 6 of dh)
        mov     al, dh
        and     al, 040h
        les     di, stereoPtr
        mov     es:[di], al

        .leave
        ret
MIXASMSPECVALUE endp

;--------------------------------------------------------------------------
; MIXASMGETSTATE
;--------------------------------------------------------------------------
MIXASMGETSTATE proc far
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]
        mov     di, DRE_SOUND_DAC_CHECK_SAMPLE_RATE_AND_FORMAT
        mov     cx, 0                           ; DAC to check
        mov     ax, MANUFACTURER_ID_BSW
        mov     bx, DACSF_MIXER_TEST
        mov     dx, 2                           ; sample rate (in Hz)
        call    es:[si].DIS_strategy
        cld
        mov     ax, dx

        .leave
        ret
MIXASMGETSTATE endp

ASMTOOLS_TEXT   ends

        SetDefaultConvention             ; restore calling convention

