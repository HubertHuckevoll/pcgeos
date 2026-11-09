COMMENT @/********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved

PROJECT:	BestSound Driver

FILE:		bsrecord.asm

AUTHOR:		Dirk Lausecker


 THE RECORDING FUNCTIONS ARE NOT PART OF THE LICENSING CONTRACT
 BETWEEN NEWDEAL INC. AND DIRK LAUSECKER !
 THE COMMENTS WILL BE FULLY TRANSLATED WHEN THE RECORDING FEATURE
 WAS LICENSED BY NEWDEAL OR OTHER COMPANIES !


REVISION HISTORY:
	Name	Date		Description
	----	-----		------------
	DL	06.10.98	Init
        DL	08.10.99	Derived from Recording
        DL	20.02.2000	NewWave
        DL	06.04.2000	Optimization
        DL	16.08.2000	Translation

ROUTINES:
	Name			Description
	----			-----------
	BSDRecGetMaxProperties	Get max Samprate/Bits/Channels
	BSDRecGetData		Waiting for Samplingdata
	BSDStopRecOrPlay 	Stop Recording or Playing
	BSDRecStartRecording 	Start Recording
	BSDRecAllocateBuffer 	Allocate Buffer for Recording
	BSDRecProgramDMA 	Program DMA
	BSRECISR		ISR for Recording
        BSRecordGetRMSValue	ADC-RMS Levelmeter

Description:
	The following routines will improve the soundcard driver
        with recording capabilities.

Knowing problems:
	At this time a good PC is needed (>= P133) for recording.
        I believe the mechanism for saving the sampled data
        must be redesigned (Timeout problems)

*****************************************************************/@

;
; Max. Samplingparameter
; for Recording / NewWave-Play
;

BSD_MAX_RATE		equ	22050	; 22050 Hz
BSD_MAX_BITS		equ	8	; 8 Bit
BSD_MAX_CHANNELS        equ	2	; Stereo
BSD_STEREO_TOGGLE	equ	1	; channels must be toggled

BS_STATE_IDLE		equ	0	; states for bsStatus
BSREC_STATE_PREPARE	equ	1
BSREC_STATE_RUN		equ	2
; States 3, 4 and 6 are defined in BSNWAV.ASM.

BSREC_STATE_GET_RMS	equ	5	; RMS-measuring on ADC-input

BSREC_DATA_WAIT		equ	0	; states for bsRecDataFlag
BSREC_DATA_READY	equ	1

BSREC_HALF_LOW		equ	1	; states for bsRecDataHalf
BSREC_HALF_HIGH		equ	0

;/////////////////////////////////
;	    Globals
;/////////////////////////////////

idata           segment

	bsStatus		byte	0	; 0 = no Recording
        					; 1 = Preparation phase
                                                ; 2 = Recording !

        bsSampleRate		word	22050	; Samplerate
	bsChannels		byte	1	; channels
        bsRecBits		byte	8	; Bits

        bsRecDataFlag		byte	0	;>0 = sample data ready for saving
						; 0 = wait for new sample data
	bsRecDataHalf		byte	0	; 1 = lower bufferhalf ready
        					; 0 = higher bufferhalf ready
        filterState		byte	0	; temp buffer for Filterstatus

idata           ends



;===========================================================

LoadableCode            segment resource

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecGetMaxProperties
;
; 	Get max capabilities
;
;  IN:	-
;
; OUT:	cx	max. Samplerate
;	dl	max. channels
;	dh	max. Bits
;	al	0 = Stereo channel alignment OK
;		1 = channels must be swapped
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecGetMaxProperties	proc	far
	uses	ds,di
        .enter

	mov	cx,BSD_MAX_RATE		; 22050
        mov	dh,BSD_MAX_BITS		; 8 Bit
        mov	dl,BSD_MAX_CHANNELS	; 2
        mov	ax,BSD_STEREO_TOGGLE	; 1

        .leave
	ret

BSDRecGetMaxProperties	endp

LoadableCode    ends


ResidentCode            segment resource

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecGetData
;
; 	Wait for data
;       return pointer and len of data
;
;  IN:	-
;
; OUT:	dx	Segment
;	ax	Offset
;	bx	Len
;	cx	0 = OK
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecGetData	proc	far
	uses	ds,di
        .enter
	mov	ax,segment dgroup
        mov	ds,ax

;------------------------------
; Wait until the flag is set
; or the timeout expires
;------------------------------
	mov	cx,200			; 200 cycles until timeout
next:
	tst	ds:[bsRecDataFlag]	; Is data available?
        jz	waitforflag		; No, wait

;------------------------------
;    Check for buffer overrun
;------------------------------
	mov	al,ds:[bsRecDataFlag]	; Get the flag value
        cmp	al,1			; 1 --> no buffer overrun?
        jz	wakeup			; Yes, all OK: continue

        mov	cl,al			; Return the flag value as an error code
        mov	ch,0
        jmp	done			; Return with an error

;-----------------------------------
; Space for a possible level calculation
;-----------------------------------

;-----------------------------------
waitforflag:

        mov	ax,1
	call	TimerSleep		; Wait 1/60 second
	loop	next			; (dec cx, jnz next)
        mov	cx,1			; Error indicator

;	WARNING	BS_REC_GET_DATA_TIMEOUT

        jmp	short done

;---------------------------
; Calculate return values
;---------------------------
wakeup:
	clr	ds:[bsRecDataFlag]	; Clear the flag
        mov     ax,0			; First half
        mov	dx,ds:[bufferSegment]	; Segmentadresse
        mov     bx,ds:[bufferO2]	; Length
        tst	ds:[bsRecDataHalf]	; Lower half?
        jnz	lower			; Yes
	mov	ax,bx			; No, upper half
lower:
	mov	cx,0			; Error indicator
done:
        .leave
        ret
BSDRecGetData	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSRECISR
;
; 	Recording ISR
;       Called when half of the buffer
;	is full and can be read.
;
;  IN:	-
;
; OUT:	-
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSRECISR	proc	far
	uses    ax,ds
        .enter

;------------------------
; 	Set flags
;------------------------
; The interrupt increments bsRecDataFlag.
; The reader must decrement the value.
; A value greater than, for example, 2 indicates
; that data was not read quickly enough.
; Set the error flag to report the error.
;

        inc	ds:[bsRecDataFlag]

	mov	al,ds:[bsRecDataHalf]
        xor	al,01h			; Swap halves
	mov	ds:[bsRecDataHalf],al

        .leave
        ret

BSRECISR	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDStopRecOrPlay
;
; 	Stop recording or playback
;
;       Calls BSSecondUnlock
;
;
;  IN:	(glob)	bsStatus
;
; OUT:	cx      0 = OK
;		1 = command could not
;		    be executed.
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDStopRecOrPlay	proc	far

	uses	ax,bx,dx,di
        .enter
	mov	ax,segment dgroup	; Set dgroup
        mov	ds,ax

;------------------
; Free the buffer
;------------------
	call	BSSecondUnlock		; Delegate the operation

; Reset the status

	mov	ds:[bsStatus],BS_STATE_IDLE

        .leave
        ret

BSDStopRecOrPlay	endp

ResidentCode    ends

LoadableCode            segment resource

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecStartRecording
;
; 	Start recording
;       Top-level routine calls other routines.
;
;
;
;  IN:	-
;
; OUT:	cx      0 = OK
;		1 = command could not
;		    be executed.
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecStartRecording	proc	far
	uses	ax,bx,dx,di,ds
        .enter
	mov	ax,segment dgroup	; Set dgroup
        mov	ds,ax

;-------------------
; dacStatus = idle?
;-------------------
	tst	ds:[dacStatus]		; Is DAC output active?
        LONG jnz	error			; Yes

	mov	ds:[bsStatus],BSREC_STATE_PREPARE
	clr	ds:[bsRecDataFlag]	; Clear the data flag
        clr	ds:[bsRecDataHalf]	; Initial completed buffer half

;-------------------
;  Allocate a buffer
;-------------------
        mov	cx,4000h		; 16 KB leaves at least
        				; 8 KB after a page boundary split,
                                        ; giving an interrupt interval of
                                        ; 22 ms at 44 kHz / 16 bits / stereo.
	call	BSDRecAllocateBuffer	; OUT: ax = buffer address

        jc	error			; Error!

;-------------------
;  Mono/Stereo
;-------------------
        push	ax				; (1)

        mov	cl,DSP_RECORD_PCM_INPUT_AI
        mov	ch,0				; Highspeed-Flag = OFF

	mov	al,ds:[bsChannels]		; Channel count
        cmp	al,2				; Stereo ?
        jnz	mono				; No
; Stereo
	SBDDACWriteDSP  DSP_STEREO_INPUT, 0	; Program the mixer

        mov	ch,1				; Highspeed-Flag = ON
        mov	cl,DSP_DMA_PCM_AI_INPUT_HIGH	; DSP command
mono:
        mov	ds:[hsFlag],ch			; Highspeedflag
	mov	ds:[DSPFormatCommand],cl	; DSP command for later use

;-------------------
;  Program DMA
;-------------------
        pop	ax				; (1)
	call	BSDRecProgramDMA		; IN ax = buffer segment address

;-------------------
;  DSP time constant
;-------------------
	call	BSDRecSetTimeConst

;-------------------
;  Mono/Stereo
;-------------------
	mov	al,ds:[bsChannels]	; Channel count
        cmp	al,2			; Stereo ?
        jnz	prog_size		; No
;
; Save the input filter state
; and turn it off
;
        mov	al,MIXER_FILTER		; Inputfilter
	mov	dx,ds:[basePortAddress]
        add	dx,4			; Mixer Address Port
        out	dx,al
        inc	dx
        in	al,dx			; Read
        mov	ds:[filterState],al	; Save
        or	al,00100000b		; Disable the input filter
        out	dx,al

;------------------------
;  DSP Blocktransfersize
;------------------------
prog_size:
	call	BSDRecSetTransferSize

;------------------------
; Start AutoInit Transfer
;------------------------
	call	BSDRecStartAI
	mov	ds:[bsStatus],BSREC_STATE_RUN
	mov	cx,0			; No error
        jmp	done			; --> End

;------------------------
;   	E N D E
;------------------------
error:
        mov	ds:[bsStatus],BS_STATE_IDLE
	mov	cx,1			; Error indicator
        clc				; CY = 1

done:
        .leave
        ret

BSDRecStartRecording	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecAllocateBuffer
;
; 	Allocate a buffer
;
;
;  IN:	cx	Buffer length
;
; OUT:  ax	Buffersegment
;	CY	TRUE = error
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecAllocateBuffer	proc	near
	uses	bx,dx,di
        .enter

; EC<	WARNING	BS_REC_ALLOCATE_BUFFER	>

;----------------------
; 	Allocate a buffer
;----------------------
	mov	ax,cx			; Length
        mov	ds:[bufferLen],ax	; Store
        mov	cl,mask HF_FIXED	; HeapFlags
        mov	ch,mask HAF_ZERO_INIT
					; HeapAllocFlags
                                        ; LA 18.10.99: HAF_LOCK avoids ILLEGAL_SEGMENT
	call	MemAlloc
	jc	done			; Error!

	mov	ds:[bufferHandle],bx	; Handle to block allocated
	mov	ds:[bufferSegment],ax	; Address of block allocated

        call	BSCreateStack		; Create the ISR stack

	clc

done:
        .leave
        ret

BSDRecAllocateBuffer	endp





;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecProgramDMA
;
; 	Program DMA
;
;
;  IN:	ax	Buffer segment address
;
; OUT:	-
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecProgramDMA	proc	near
	uses	ax,bx,dx,di
        .enter

;-----------------------
;	Prepare DMA
;-----------------------
	mov	bx,ax			; Buffer address
	mov	dx,ds:[bufferLen]	; Length

        call	BSDMACheckBoundaries		; Check segment boundaries
	mov	ds:[bufferSegment],bx	; Adjusted segment address
	call	RecProgramDMADriver	; Prepare DMA

;-----------------------
; Calculate buffer values
;-----------------------
        mov	ax,ds:[bufferLen]	; Length
        mov	ds:[bufferFree],ax	; Free space
        mov	ds:[bufferMax],ax	; End-of-buffer offset
        clr	ds:[dacStatus]		; dacStatus = waiting
        clr	ds:[bufferP2]		; Start Buffer
        shr	ax			; /2
	mov	ds:[bufferO2],ax	; Buffer half

	clc

        .leave
        ret

BSDRecProgramDMA	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecSetTimeConst
;
; 	DSP time constant
;
;
;  IN:	ds	dgroup
;
; OUT:	-
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecSetTimeConst	proc	near
	uses	ax,bx,dx,di
        .enter

;--------------------------------
; Calculate the 16-bit time constant
;--------------------------------
	mov	cx,ds:[bsSampleRate]	; cx <- sampling rate

        mov	al,ds:[bsChannels]	; Channel count
        cmp	al,1			; Mono ?
        jz	mono
        shl	cx			; Byte rate * 2 for stereo
mono:
	movdw   dxax, 256000000         ; dxax <- 256000000
	div     cx                      ; ax <- 65536 - divisor

	neg     ax                      ; ax <- divisor

	mov     bx, ax                  ; bx <- divisor for rate

	;
	;  Set up the DAC to operate at the given rate

        mov	dx,cx			; dx = Samplerate

	SBDDACWriteDSP  DSP_SET_RATE_DIVISOR, 0
	SBDDACWriteDSP  bh, 0

        .leave
        clc
        ret

BSDRecSetTimeConst	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecSetTransferSize
;
; 	Set the DSP block transfer size
;       _
;
;
;  IN:	ds	dgroup
;
; OUT:	-
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecSetTransferSize	proc	near
	uses	ax,bx,dx,di
        .enter

        mov	cx,ds:[bufferO2]	; Half the secondary buffer length
        dec	cx
	SBDDACWriteDSP  DSP_SET_BLOCK_SIZE, 0	; Block length (48h)
	SBDDACWriteDSP  cl, 0			; L Byte
	SBDDACWriteDSP  ch, 0			; H Byte
        clc

        .leave
        ret

BSDRecSetTransferSize	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecStartAI
;
; 	Start AutoInit Transfer
;
;
;  IN:	ds	dgroup
;
; OUT:	-
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecStartAI	proc	near
	uses	ax,bx,dx,di
        .enter

        mov	bl,ds:[DSPFormatCommand]
	SBDDACWriteDSP  bl,0 ; AutoInit Recording
        .leave
        ret

BSDRecStartAI	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecSetSampling
;
; 	Set recording parameters
;
;
;  IN:	bx	Samplerate
;	cx	channels
;	dx	bits
;
; OUT:	cx      0 = OK
;		1 = command could not
;		    be executed.
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecSetSampling	proc	far
	uses	ax,bx,dx,di
        .enter
	mov	ax,segment dgroup	; Set dgroup
        mov	ds,ax
;
; Store values
;
	mov	ds:[bsSampleRate],bx
	mov	ds:[bsChannels],cl
	mov	ds:[bsRecBits],dl
        mov	cx,0			; Return value

;----------------------------
;   Check the sample data
;----------------------------

        .leave
        ret

BSDRecSetSampling	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSRecordGetRMSValue
;
; Measure the RMS voltage
;
; Read ax samples from the DSP in direct mode.
; Use the minimum and maximum values to estimate the RMS voltage.
;
;  IN:	ax	Number of iterations
;
; OUT:	bx  	Value (0...255)
;	cx      0 = OK
;		1 = command could not
;		    be executed.
;
; 19.10.99	Abort if playback is active
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSREC_RMS_OK	equ	0	; Result error code
BSREC_RMS_ERROR	equ	1


BSRecordGetRMSValue	proc	far
	uses	ax,dx,di
        .enter
        mov	cx,ax			; Number of iterations
	mov	ax,segment dgroup
        mov	ds,ax

;------------------------
; Check whether the DSP is in use
;------------------------
        mov	bx,0			; Return value on error
	tst	ds:[dacStatus]		; Is the DAC available? (old routines)
        jnz	notfree

	tst	ds:[bsStatus]		; Recording / NewWave ?
        jz	free			; Yes
notfree:
        mov	cx,BSREC_RMS_ERROR	; Error code
        jmp	done

;------------------------
; Measure the RMS level
;------------------------
free:
        mov	ds:[bsStatus],BSREC_STATE_GET_RMS
        mov	bx,8080h		; BL = MIN / BH = MAX
next:
	SBDDACWriteDSP  DSP_RECORD_DIRECT, 0
	SBDDACReadDSP 0			; Read the value

;------------------------
; 	MIN / MAX values
;------------------------
	cmp	al,bl
	jnc	not_under
	mov	bl,al			; New MIN value
not_under:
	cmp	al,bh
	jc	not_over
        mov	bh,al			; New MAX value

not_over:
	loop	next			; cx-1 != 0 --> next

;------------------------
;	RMS calculation
; Subtract the silence level (80h)
;------------------------
	mov	al,80h
        sub	al,bl			; al = absolute MIN value
        mov	bl,al			; bl = absolute MIN value

        mov	al,bh			; MIN
        sub	al,80h			; Subtract the silence level
        mov	ah,0

        mov	bh,0			; bx = MIN

        add	ax,bx			; ax = peak-to-peak value
        mov	bx,ax			; Return value

        mov	cx,BSREC_RMS_OK		; Error code
        mov	ds:[bsStatus],BS_STATE_IDLE

; Return the value
done:
        .leave
        ret

BSRecordGetRMSValue	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RecProgramDMADriver
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Program the DMA driver for output

CALLED BY:      BSDRecProgramDMA
PASS:           bx      -> stream segment
		dx      -> buffer size
		INT_ON

RETURN:         bufferLen -> DMA length

DESTROYED:      nothing
SIDE EFFECTS:

PSEUDO CODE/STRATEGY:


REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	09.11.97	Initial
				(Extracted from SBDDACAttachToStream)
        DL	29.09.98	BestSound Template
        DL	14.10.99	Derived for recording

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
RecProgramDMADriver    proc    far
	.enter
	;
	push	dx			; stream size [1]
;---------------------------------
;	Allocate the DMA channel
;---------------------------------
	;
	;  Try to request the DMA channel
        ;
        ;DL:	The valid DMA channel is stored in
        ;	[baseDMAChannel].
        ;
        mov	cx,ds:[baseDMAChannel]	; Current DMA channel
	mov     dl, 1
	shl     dl, cl                  ; dl <- mask of request channel
	mov     dh, dl                  ; dh <- mask of request channel
	mov     di, DR_REQUEST_CHANNEL

	INT_OFF
	call   ds:[DMADriver]           ; call DMA driver

	INT_ON

;-------------------------
;	Error?
;-------------------------

	tst     dl                      ; did we get it?
	jnz     error

;-------------------------
;	DMA Halt
;-------------------------

	mov     dl, dh                  ; dl <- channel of transfer
	mov     di, DR_DISABLE_DMA_REQUESTS
	INT_OFF
	call   ds:[DMADriver]           ; turn off requests to chip

	INT_ON

;--------------------------------------
;	Initialize auto-init DMA
;--------------------------------------
	;
	;  Try to set up an auto-init transfer of the
	;       entire buffer.  If it fails, we
	;       just return carry set.
	pop     ax                      ; restore size of stream [1]

	mov     si, 0      		; bx:si <- buffer to DMA

;-----------------------
; Address and length --> DMA
;-----------------------
	dec     ax                      ; transfer size -1
	push	ax			; Save for the check
	mov     cx, ax                  ; cx <- size of buffer
	mov     dx, ds:[baseDMAChannel]  ; dl <- channel #
	mov     dh, ModeRegisterMask <DMATM_SINGLE_TRANSFER,0,1,DMATD_WRITE>
	mov     di, DR_START_DMA_TRANSFER

	INT_OFF

	call   ds:[DMADriver]           ; set up transfer

        INT_ON
;-----------------------
;	Check
;-----------------------
	pop	ax			; Requested length
        cmp	ax,cx			; Actual length = requested length?
	jnz	lengthReady		; Different length: skip adjustment
                                        ; If the requested length cannot be used,
                                        ; the DMA driver returns L instead of L-1.
                                        ; Adjust L only if the requested length
                                        ; was returned.
        inc	cx			; DMA uses length - 1
lengthReady:
	mov	ds:[bufferLen],cx	; Save the new length

;-----------------------
; 	Enable DMA
;-----------------------

	mov     cx, ds:[baseDMAChannel]
	mov     dl, 1
	shl     dl, cl
	mov     di, DR_ENABLE_DMA_REQUESTS

	INT_OFF

	call   ds:[DMADriver]

	INT_ON                          ; turn off request to chip

	clc                             ; clear carry flag
done:
	.leave
	ret

;----------------------
;	ERROR
;----------------------
error:
	pop     dx                      ; clean up stack [1]
	stc
	jmp     short done
RecProgramDMADriver	endp



LoadableCode            ends
