COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        BestSound NewWave assembly helpers

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include driver.def
include geode.def
include library.def

include bsnwav.def
include dirksnd.def

SetGeosConvention

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
; BSNWAsmGetMaxProperties
;--------------------------------------------------------------------------
public  BSNWAsmGetMaxProperties
BSNWAsmGetMaxProperties proc far    driverHandle:word,
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
BSNWAsmGetMaxProperties endp

;--------------------------------------------------------------------------
; BSNWAsmStopRecOrPlay
;--------------------------------------------------------------------------
public  BSNWAsmStopRecOrPlay
BSNWAsmStopRecOrPlay proc far       driverHandle:word,
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
BSNWAsmStopRecOrPlay endp

;--------------------------------------------------------------------------
; BSNWAsmSetPause
;--------------------------------------------------------------------------
public  BSNWAsmSetPause
BSNWAsmSetPause proc far            driverHandle:word,
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
BSNWAsmSetPause endp

;--------------------------------------------------------------------------
; BSNWAsmQueryDeviceCapability
;--------------------------------------------------------------------------
public  BSNWAsmQueryDeviceCapability
BSNWAsmQueryDeviceCapability proc far       driverHandle:word,
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
BSNWAsmQueryDeviceCapability endp

;--------------------------------------------------------------------------
; BSNWAsmCheckSampleRate
;--------------------------------------------------------------------------
public  BSNWAsmCheckSampleRate
BSNWAsmCheckSampleRate proc far     driverHandle:word,
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
BSNWAsmCheckSampleRate endp

;--------------------------------------------------------------------------
; BSNWAsmGetStatus
;--------------------------------------------------------------------------
public  BSNWAsmGetStatus
BSNWAsmGetStatus proc far           driverHandle:word,
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
BSNWAsmGetStatus endp

;--------------------------------------------------------------------------
; BSNWAsmSecondAlloc
;--------------------------------------------------------------------------
public  BSNWAsmSecondAlloc
BSNWAsmSecondAlloc proc far         driverHandle:word,
                                    driverInfoPtrOff:word,
                                    driverInfoPtrSeg:word,
                                    length:word,
                                    offsetOff:word,
                                    offsetSeg:word,
                                    segmentOff:word,
                                    segmentSeg:word
        uses    bx, cx, dx, si, di, es
        .enter
        FETCH_STRATEGY driverHandle, driverInfoPtrOff, driverInfoPtrSeg

        mov     cx, length
        mov     di, DRE_BSNWAV_SECOND_ALLOC
        call    es:[si]

        mov     si, ax                        ; save segment

        mov     bx, offsetOff
        mov     ax, offsetSeg
        mov     es, ax
        mov     es:[bx], dx

        mov     bx, segmentOff
        mov     ax, segmentSeg
        mov     es, ax
        mov     es:[bx], si

        mov     ax, cx

        .leave
        ret
BSNWAsmSecondAlloc endp

;--------------------------------------------------------------------------
; BSNWAsmStartPlay
;--------------------------------------------------------------------------
public  BSNWAsmStartPlay
BSNWAsmStartPlay proc far           driverHandle:word,
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
BSNWAsmStartPlay endp

;--------------------------------------------------------------------------
; BSNWAsmGetAIState
;--------------------------------------------------------------------------
public  BSNWAsmGetAIState
BSNWAsmGetAIState proc far          driverHandle:word,
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
BSNWAsmGetAIState endp

;--------------------------------------------------------------------------
; BSNWAsmSetSampling
;--------------------------------------------------------------------------
public  BSNWAsmSetSampling
BSNWAsmSetSampling proc far         driverHandle:word,
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
BSNWAsmSetSampling endp

end
