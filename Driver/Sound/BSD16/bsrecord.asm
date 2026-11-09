COMMENT @********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved

PROJECT:	BestSound Driver

FILE:		bsrecord.asm

AUTHOR:		Dirk Lausecker

REVISION HISTORY:
	Name	Date		Description
	----	-----		------------
	DL	06.10.98	Init
        DL	08.10.99	Derived from Recording
        DL	20.02.2000	NewWave

ROUTINES:
	Name			Description
	----			-----------
	BSDRecGetMaxProperties	Maximum sample rate, bit depth and channels
	BSDRecGetData		Wait for sample data
	BSDStopRecOrPlay 	Stop recording
	BSDRecStartRecording 	Start recording
	BSDRecAllocateBuffer 	Allocate a buffer
	BSDRecFreeBuffer 	Free the allocated buffer
	BSDRecProgramDMA 	Program DMA
	BSRECISR		Recording ISR
        BSRecordGetRMSValue	ADC-RMS voltage measurement

Description:
	These routines add recording support to the driver.
        The ISR must check bsStatus
	(formerly bsRecordState) to determine whether
	to call the recording ISR instead of BSDACISR.

NewWave:
	Only one mode can be active at a time.
        The bsStatus variable (formerly bsRecordState)
        is shared by NewWave playback and recording.


*****************************************************************@

;
; Maximum sampling parameters
; Used by recording and NewWave playback
;
BSD_MAX_RATE		equ	44100
BSD_MAX_BITS		equ	16
BSD_MAX_CHANNELS        equ	2
BSD_STEREO_TOGGLE	equ	0	; Stereo channels are not swapped
BS_STATE_IDLE		equ	0	; States for bsStatus

BSREC_STATE_PREPARE	equ	1
BSREC_STATE_RUN		equ	2
; States 3 and 4 are defined in BSNWAV.ASM.
BSREC_STATE_GET_RMS	equ	5	; RMS measurement at the ADC input

BSREC_DATA_WAIT		equ	0	; States for bsRecDataFlag
BSREC_DATA_READY	equ	1

BSREC_HALF_LOW		equ	1	; States for bsRecDataHalf
BSREC_HALF_HIGH		equ	0

;/////////////////////////////////
;	Global variable
;/////////////////////////////////

idata           segment

	bsStatus		byte	0	; 0 = no recording
        					; 1 = preparation phase
                                                ; 2 = recording active

        bsRecSamplerate		word	22050	; Samplerate
	bsRecChannels		byte	1	; Channel count
        bsRecBits		byte	8	; Bit depth

        bsRecDataFlag		byte	0	;>0 = data available
						; 0 = wait for new data
	bsRecDataHalf		byte	0	; 1 = lower half ready
        					; 0 = upper half ready
idata           ends



;===========================================================

LoadableCode            segment resource

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecGetMaxProperties
;
; 	Maximum recording parameters
;       Return the value
;
;  IN:	-
;
; OUT:	cx	max. Samplerate
;	dl	Maximum channel count
;	dh	Maximum bit depth
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecGetMaxProperties	proc	far
	uses	ds,di
        .enter

;-----------------------------------------
; Return the maximum recording parameters
;-----------------------------------------
	mov	cx,BSD_MAX_RATE		; 44100
        mov	dh,BSD_MAX_BITS		; 16 Bit
        mov	dl,BSD_MAX_CHANNELS	; 2
        mov	ax,BSD_STEREO_TOGGLE	; 0

        .leave
	ret

BSDRecGetMaxProperties	endp

LoadableCode    ends


ResidentCode            segment resource

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecGetData
;
; 	Wait until data is available
;       and return its pointer and length.
;
;  IN:	-
;
; OUT:	dx	Pointer segment
;	ax	Pointer offset
;	bx	Length
;	cx	0 = OK
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecGetData	proc	far
	uses	ds,di
        .enter
	mov	ax,segment dgroup	; Set dgroup
        mov	ds,ax

;------------------------------
; Wait until the flag is set
; or the timeout expires
;------------------------------
	mov	cx,500			; 500 cycles until timeout
next:
	tst	ds:[bsRecDataFlag]	; Is data available?
        jz	waitforflag		; No, wait

;------------------------------
;    Check for buffer overrun
;------------------------------
	mov	al,ds:[bsRecDataFlag]	; Get the flag value
        cmp	al,1			; 1 --> no buffer overrun?
        jz	wakeup			; Yes, all OK: continue

; LA 05.11.2000
; resetting Overflow-counter
	clr	ds:[bsRecDataFlag]
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

	WARNING	BS_REC_GET_DATA_TIMEOUT

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
;
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
;  IN:	-
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
; 	Start Recording
;       Top-Level subroutine will call
;	other subroutines.
;
;  IN:	dx	buffersize
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
        jnz	error			; Yes

	mov	ds:[bsStatus],BSREC_STATE_PREPARE
	clr	ds:[bsRecDataFlag]	; Clear the data flag
        clr	ds:[bsRecDataHalf]	; Initial completed buffer half

;-------------------
;  Allocate a buffer
;-------------------
	mov	cx,dx
;        mov	cx,4000h		; 16 KB leaves at least
        				; 8 KB after a page boundary split,
                                        ; giving an interrupt interval of
                                        ; 22 ms at 44 kHz / 16 bits / stereo.
	call	BSDRecAllocateBuffer	; ax = buffer address

        jc	error			; Error!

;-------------------
;  Program DMA
;-------------------
	call	BSDRecProgramDMA
        jc	error1			; Error! Free the buffer

;-------------------
;  DSP Samplerate
;-------------------
        SBDDACWriteDSP  DSP_SET_INPUT_RATE, 0	; DSP-Command
	mov	cx,ds:[bsRecSamplerate]
        SBDDACWriteDSP  ch, 0		; Samplerate
        SBDDACWriteDSP  cl, 0

;------------------------
; Start AutoInit Transfer
;------------------------
	call	BSDRecStartAI
        jc	error			; Error!
	mov	ds:[bsStatus],BSREC_STATE_RUN
	mov	cx,0			; No error
        jmp	done			; --> End

;------------------------
;    Error handling
;------------------------
error1:
	call	BSDRecFreeBuffer	; Free the buffer

;------------------------
;   	E N D E
;------------------------
error:
        mov	ds:[bsStatus],BS_STATE_IDLE
	mov	cx,1		; Error indicator
        clc			; CY = 1

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

EC<	WARNING	BS_REC_ALLOCATE_BUFFER	>

;----------------------
; 	Allocate a buffer
;----------------------
	mov	ax,cx			; Length
        mov	ds:[bufferLen],ax	; Store
        mov	cl,mask HF_FIXED	; HeapFlags
;        mov	ch,mask HAF_ZERO_INIT
        mov	ch,0
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
;	BSDRecFreeBuffer
;
; 	Free the allocated buffer
;
;
;  IN:	bufferHandle
;
; OUT:	CY	TRUE = error
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecFreeBuffer	proc	near
        .enter
	call	BSSecondUnlock	; Delegate the operation
        clc

        .leave
        ret

BSDRecFreeBuffer	endp


;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecStartAI
;
; 	Start AutoInit Transfer
;
;
;  IN:	ds	dgroup
;
; OUT:	CY	TRUE = error
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

BSDRecStartAI	proc	near
	uses	ax,bx,dx,di
        .enter

;------------------------
; DSP Transfercommand
;------------------------
	mov	al,ds:[bsRecBits]
	cmp	al,16				; 16 Bit ?
        jnz	bit8				; No

        SBDDACWriteDSP  DSP_16BIT_INPUT, 0	; Command

        mov	bh,DSP_MODE_16BIT_MONO
	mov	al,ds:[bsRecChannels]
	cmp	al,1				; Mono ?
        jz	mono
        mov	bh,DSP_MODE_16BIT_STEREO

        jmp     mono

bit8:
        SBDDACWriteDSP  DSP_8BIT_INPUT, 0	; Command

        mov	bh,DSP_MODE_8BIT_MONO
	mov	al,ds:[bsRecChannels]
	cmp	al,1			; Mono ?
        jz	mono
        mov	bh,DSP_MODE_8BIT_STEREO
mono:
        SBDDACWriteDSP  bh, 0		; Mode (Mono/Stereo)

        mov	cx,ds:[bufferO2]	; Half the secondary buffer length
        mov	al,ds:[bsRecBits]
	cmp	al,16			; 16 Bit ?
	jnz	set_size		; No
	shr	cx			; Yes, block size in words
set_size:
        dec	cx
	SBDDACWriteDSP  cl, 0			; L Byte
	SBDDACWriteDSP  ch, 0			; H Byte

        clc
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
	mov	ds:[bsRecSamplerate],bx
	mov	ds:[bsRecChannels],cl
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

;/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	BSDRecProgramDMA
;
; 	Program DMA
;
;
;  IN:	ax	Buffer segment address
;
; OUT:	CY	TRUE = error
;
; DL	04.11.2000	RecProgramDMADriver replaced by
;			ProgramDMADriver for 16 Bit Recording
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

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

        mov	cx,2			; Playmode = Recording
	call	ProgramDMADriver	; Prepare DMA

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

LoadableCode            ends
