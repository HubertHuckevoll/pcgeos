COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        BestSound NewWave assembly helpers

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include driver.def
include geode.def
include library.def

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

SetGeosConvention

ASMTOOLS_TEXT   segment resource

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

FETCH_STRATEGY macro handle, infoOff, infoSeg
    local   havePointer, loadStrategy
    mov     bx, infoOff
    mov     ax, infoSeg
    mov     es, ax
    mov     si, es:[bx]
    mov     dx, es:[bx+2]
    or      si, dx
    jnz     havePointer

    push    ds
    mov     bx, handle
    call    GeodeInfoDriver
    mov     es, infoSeg
    mov     bx, infoOff
    mov     es:[bx], si
    mov     es:[bx+2], ds
    mov     dx, ds
    pop     ds
    jmp     short loadStrategy

havePointer:
loadStrategy:
    push    ds
    mov     ds, dx
    mov     bx, [si]
    mov     cx, [si+2]
    pop     ds
    mov     si, bx
    mov     es, cx
endm

;--------------------------------------------------------------------------
BSNWAsmGetMaxProperties          equ     BSNWASMGETMAXPROPERTIES
BSNWAsmStopRecOrPlay             equ     BSNWASMSTOPRECORPLAY
BSNWAsmSetPause                  equ     BSNWASMSETPAUSE
BSNWAsmQueryDeviceCapability     equ     BSNWASMQUERYDEVICECAPABILITY
BSNWAsmCheckSampleRate           equ     BSNWASMCHECKSAMPLERATE
BSNWAsmGetStatus                 equ     BSNWASMGETSTATUS
BSNWAsmSecondAlloc               equ     BSNWASMSECONDALLOC
BSNWAsmStartPlay                 equ     BSNWASMSTARTPLAY
BSNWAsmGetAIState                equ     BSNWASMGETAISTATE
BSNWAsmSetSampling               equ     BSNWASMSETSAMPLING

; BSNWASMGETMAXPROPERTIES
;--------------------------------------------------------------------------
BSNWASMGETMAXPROPERTIES proc far    driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    rateOff:word,
                                    rateSeg:word,
                                    channelsOff:word,
                                    channelsSeg:word,
                                    bitsOff:word,
                                    bitsSeg:word,
                                    reverseOff:word,
                                    reverseSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     di, DRE_BSNWAV_GET_MAX_PROPERTIES
        call    es:[si]

        mov     bx, reverseOff
        mov     ax, reverseSeg
        mov     es, ax
        mov     es:[bx], al

        mov     bx, rateOff
        mov     ax, rateSeg
        mov     es, ax
        mov     es:[bx], cx

        mov     bx, channelsOff
        mov     ax, channelsSeg
        mov     es, ax
        mov     es:[bx], dl

        mov     bx, bitsOff
        mov     ax, bitsSeg
        mov     es, ax
        mov     es:[bx], dh

        .leave
        ret
BSNWASMGETMAXPROPERTIES endp

;--------------------------------------------------------------------------
; BSNWASMSTOPRECORPLAY
;--------------------------------------------------------------------------
BSNWASMSTOPRECORPLAY proc far       driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     di, DRE_STOP_REC_OR_PLAY
        call    es:[si]
        mov     ax, cx

        .leave
        ret
BSNWASMSTOPRECORPLAY endp

;--------------------------------------------------------------------------
; BSNWASMSETPAUSE
;--------------------------------------------------------------------------
BSNWASMSETPAUSE proc far            driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    mode:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     cx, mode
        mov     ch, 0
        mov     di, DRE_BSNWAV_SET_PAUSE
        call    es:[si]
        mov     al, ch
        xor     ah, ah

        .leave
        ret
BSNWASMSETPAUSE endp

;--------------------------------------------------------------------------
; BSNWASMQUERYDEVICECAPABILITY
;--------------------------------------------------------------------------
BSNWASMQUERYDEVICECAPABILITY proc far       driverHandle:word,
                                            driverInfoPtrOff:word,
                                            driverInfoPtrSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     di, DRE_SOUND_QUERY_DEVICE_CAPABILITY
        call    es:[si]
        mov     ax, dx

        .leave
        ret
BSNWASMQUERYDEVICECAPABILITY endp

;--------------------------------------------------------------------------
; BSNWASMCHECKSAMPLERATE
;--------------------------------------------------------------------------
BSNWASMCHECKSAMPLERATE proc far     driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    testValue:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     cx, 0
        mov     ax, MANUFACTURER_ID_BSW
        mov     bx, DACSF_MIXER_TEST
        mov     dx, testValue
        mov     di, DRE_SOUND_DAC_CHECK_SAMPLE_RATE_AND_FORMAT
        call    es:[si]
        mov     ax, dx

        .leave
        ret
BSNWASMCHECKSAMPLERATE endp

;--------------------------------------------------------------------------
; BSNWASMGETSTATUS
;--------------------------------------------------------------------------
BSNWASMGETSTATUS proc far           driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     di, DRE_BSNWAV_GET_STATUS
        call    es:[si]
        mov     ax, cx

        .leave
        ret
BSNWASMGETSTATUS endp

;--------------------------------------------------------------------------
; BSNWASMSECONDALLOC
;--------------------------------------------------------------------------
BSNWASMSECONDALLOC proc far         driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    bufLength:word,
                                    offsetPtrOff:word,
                                    offsetPtrSeg:word,
                                    segmentPtrOff:word,
                                    segmentPtrSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     cx, bufLength
        mov     di, DRE_BSNWAV_SECOND_ALLOC
        call    es:[si]

        mov     si, ax                        ; save segment

        mov     bx, offsetPtrOff
        mov     ax, offsetPtrSeg
        mov     es, ax
        mov     word ptr es:[bx], dx

        mov     bx, segmentPtrOff
        mov     ax, segmentPtrSeg
        mov     es, ax
        mov     word ptr es:[bx], si

        mov     ax, cx

        .leave
        ret
BSNWASMSECONDALLOC endp

;--------------------------------------------------------------------------
; BSNWASMSTARTPLAY
;--------------------------------------------------------------------------
BSNWASMSTARTPLAY proc far           driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     di, DRE_BSNWAV_START_PLAY
        call    es:[si]
        mov     ax, cx

        .leave
        ret
BSNWASMSTARTPLAY endp

;--------------------------------------------------------------------------
; BSNWASMGETAISTATE
;--------------------------------------------------------------------------
BSNWASMGETAISTATE proc far          driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    options:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     cx, options
        mov     di, DRE_BSNWAV_GET_AI_STATE
        call    es:[si]
        mov     ax, cx

        .leave
        ret
BSNWASMGETAISTATE endp

;--------------------------------------------------------------------------
; BSNWASMSETSAMPLING
;--------------------------------------------------------------------------
BSNWASMSETSAMPLING proc far         driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    rate:word,
                                    bits:word,
                                    channels:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     bx, rate
        mov     cx, channels
        mov     dx, bits
        mov     ch, 0
        mov     dh, 0
        mov     di, DRE_BSNWAV_SET_SAMPLING
        call    es:[si]
        mov     ax, cx

        .leave
        ret
BSNWASMSETSAMPLING endp

ASMTOOLS_TEXT   ends

end
