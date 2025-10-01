COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        BestSound NewWave assembly helpers

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include driver.def
include geode.def
include library.def
include ec.def

include dirk.def
include dirksnd.def

UseDriver Internal/soundDrv.def

DefLib  bsnwav.def

;-----------------------------------------------------------------------
; Driver request identifiers shared with BestSound drivers
;-----------------------------------------------------------------------

DRE_BSNWAV_SET_SAMPLING       equ     032h
DRE_STOP_REC_OR_PLAY          equ     036h
DRE_BSNWAV_GET_MAX_PROPERTIES equ     03Ah
DRE_BSNWAV_SECOND_ALLOC       equ     03Ch
DRE_BSNWAV_GET_STATUS         equ     03Eh
DRE_BSNWAV_START_PLAY         equ     040h
DRE_BSNWAV_GET_AI_STATE       equ     042h
DRE_BSNWAV_SET_PAUSE          equ     044h

global  BSNWASMGETMAXPROPERTIES:far
global  BSNWASMSTOPRECORPLAY:far
global  BSNWASMSETPAUSE:far
global  BSNWASMQUERYDEVICECAPABILITY:far
global  BSNWASMCHECKSAMPLERATE:far
global  BSNWASMGETSTATUS:far
global  BSNWASMSECONDALLOC:far
global  BSNWASMSTARTPLAY:far
global  BSNWASMGETAISTATE:far
global  BSNWASMSETSAMPLING:far
global  BSNWASMGETDRIVERINFO:far


        SetGeosConvention       ; set calling convention


udata segment

        driverInfo fptr          ; far ptr to DriverInfoStruct

udata ends



ASMTOOLS_TEXT   segment resource

;--------------------------------------------------------------------------
; BSNWASMGETDRIVERINFO
;--------------------------------------------------------------------------
BSNWASMGETDRIVERINFO proc far        driverHandle:word
        uses    bx, dx, si
        .enter

        push    ds
        mov     bx, driverHandle
        call    GeodeInfoDriver                 ; DS:SI -> DriverInfoStruct
        mov     dx, ds                          ; put segment in DX
        mov     ax, si                          ; put offset in AX
        pop     ds                              ; restore DS to point to udata

        mov     ds:[driverInfo].segment, dx     ; store segment and offset in driverInfo
        mov     ds:[driverInfo].offset, ax

        .leave
        ret
BSNWASMGETDRIVERINFO endp


;--------------------------------------------------------------------------
; BSNWASMGETMAXPROPERTIES
;--------------------------------------------------------------------------
BSNWASMGETMAXPROPERTIES proc far    ratePtr:fptr,
                                    channelsPtr:fptr,
                                    bitsPtr:fptr,
                                    reversePtr:fptr
        uses    bx, cx, dx, si, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     di, DRE_BSNWAV_GET_MAX_PROPERTIES
        call    es:[bx].DIS_strategy
        cld

        les     bx, reversePtr
        mov     es:[bx], al

        les     bx, ratePtr
        mov     es:[bx], cx

        les     bx, channelsPtr
        mov     es:[bx], dl

        les     bx, bitsPtr
        mov     es:[bx], dh

        .leave
        ret
BSNWASMGETMAXPROPERTIES endp

;--------------------------------------------------------------------------
; BSNWASMSTOPRECORPLAY
;--------------------------------------------------------------------------
BSNWASMSTOPRECORPLAY proc far
        uses    bx, cx, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     di, DRE_STOP_REC_OR_PLAY
        call    es:[bx].DIS_strategy
        cld
        mov     ax, cx

        .leave
        ret
BSNWASMSTOPRECORPLAY endp

;--------------------------------------------------------------------------
; BSNWASMSETPAUSE
;--------------------------------------------------------------------------
BSNWASMSETPAUSE proc far            mode:word
        uses    bx, cx, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     cx, mode
        mov     ch, 0
        mov     di, DRE_BSNWAV_SET_PAUSE
        call    es:[bx].DIS_strategy
        cld
        mov     al, ch
        xor     ah, ah

        .leave
        ret
BSNWASMSETPAUSE endp

;--------------------------------------------------------------------------
; BSNWASMQUERYDEVICECAPABILITY
;--------------------------------------------------------------------------
BSNWASMQUERYDEVICECAPABILITY proc far
        uses    bx, dx, di, es, bp ; ...why is bp getting trashed if we don't save it here?
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     di, DRE_SOUND_QUERY_DEVICE_CAPABILITY
        call    es:[bx].DIS_strategy      ; jump via first field of struct
        cld
        mov     ax, dx                    ; return dx in ax

        .leave
        ret
BSNWASMQUERYDEVICECAPABILITY endp

;--------------------------------------------------------------------------
; BSNWASMCHECKSAMPLERATE
;--------------------------------------------------------------------------
BSNWASMCHECKSAMPLERATE proc far     testValue:word
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]         ; ES:SI -> DriverInfoStruct
        mov     cx, 0
        mov     ax, MANUFACTURER_ID_BSW
        mov     bx, DACSF_MIXER_TEST
        mov     dx, testValue
        mov     di, DRE_SOUND_DAC_CHECK_SAMPLE_RATE_AND_FORMAT
        call    es:[si].DIS_strategy
        cld
        mov     ax, dx

        .leave
        retf
BSNWASMCHECKSAMPLERATE endp

;--------------------------------------------------------------------------
; BSNWASMGETSTATUS
;--------------------------------------------------------------------------
BSNWASMGETSTATUS proc far
        uses    bx, cx, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     di, DRE_BSNWAV_GET_STATUS
        call    es:[bx].DIS_strategy
        cld
        mov     ax, cx

        .leave
        ret
BSNWASMGETSTATUS endp

;--------------------------------------------------------------------------
; BSNWASMSECONDALLOC
;--------------------------------------------------------------------------
BSNWASMSECONDALLOC proc far         bufLength:word,
                                    offsetPtr:fptr,
                                    segmentPtr:fptr
        uses    bx, cx, dx, si, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     cx, bufLength
        mov     di, DRE_BSNWAV_SECOND_ALLOC
        call    es:[bx].DIS_strategy
        cld

        mov     si, ax                        ; save segment

        les     bx, offsetPtr
        mov     es:[bx], dx

        les     bx, segmentPtr
        mov     es:[bx], si

        mov     ax, cx

        .leave
        ret
BSNWASMSECONDALLOC endp

;--------------------------------------------------------------------------
; BSNWASMSTARTPLAY
;--------------------------------------------------------------------------
BSNWASMSTARTPLAY proc far
        uses    bx, cx, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     di, DRE_BSNWAV_START_PLAY
        call    es:[bx].DIS_strategy
        cld
        mov     ax, cx

        .leave
        ret
BSNWASMSTARTPLAY endp

;--------------------------------------------------------------------------
; BSNWASMGETAISTATE
;--------------------------------------------------------------------------
BSNWASMGETAISTATE proc far          options:word
        uses    bx, cx, di, es
        .enter

        les     bx, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     cx, options
        mov     di, DRE_BSNWAV_GET_AI_STATE
        call    es:[bx].DIS_strategy
        cld
        mov     ax, cx

        .leave
        ret
BSNWASMGETAISTATE endp

;--------------------------------------------------------------------------
; BSNWASMSETSAMPLING
;--------------------------------------------------------------------------
BSNWASMSETSAMPLING proc far         rate:word,
                                    bits:word,
                                    channels:word
        uses    bx, cx, dx, si, di, es
        .enter

        les     si, ds:[driverInfo]         ; ES:BX -> DriverInfoStruct
        mov     bx, rate
        mov     cx, channels
        mov     dx, bits
        mov     ch, 0
        mov     dh, 0
        mov     di, DRE_BSNWAV_SET_SAMPLING
        call    es:[si].DIS_strategy
        cld
        mov     ax, cx

        .leave
        ret
BSNWASMSETSAMPLING endp

ASMTOOLS_TEXT   ends

        SetDefaultConvention             ;restores calling conventions
