COMMENT @********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved

PROJECT:	BestSound Driver

FILE:		bswav.asm

AUTHOR:		Dirk Lausecker

REVISION HISTORY:
	Name	Date		Description
	----	-----		------------
	DL	29.08.98	Init
        DL	02.03.2000	Removed speaker output routines
	DL	02.03.2000	Derived from SB16
	DL	25.10.2000	Translations for ND

ROUTINES:
	Name			Description
	----			-----------
	BSSecondAlloc		Allocate Secondarybuffer
	BSSecondUnlock		Unlock Secondarybuffer
	BSSecondWrite		Fill Secondarybuffer
	BSDMACheckBoundaries		check DMA-Segment

*****************************************************************@

idata           segment

	bufferHandle		word	0h	; Handle to internal Streambuffer
	bufferSegment		word	0h	; Address Secondarybuffer
	bufferLen		word	2h	; Buffersize
	bufferO2		word	0h	; Bufferhalf
	bufferP2		word	0h	; Copypointer
	bufferFree		word	0h	; free Buffer
	bufferMax		word	1h	; Endoffset Buffer
	dacStatus		byte	0h	; 0 = ready
						; 1 = AI fill lower half
						; 2 = fill upper half
						; 3 = Single cycle (End)
	playEndFlag		byte	0h	; 1 Ending PLAY

	blockISR		byte	0h	; for Debugging
	stackHandle		word	0	; MemHandle for ISR-Stack
	DSPVersion		word	0h	; DSP Version
	hsFlag			byte	0h	; 1 = Highspeedmode
	bsInterleave		byte	1h	; every X. Byte will be copied
	singleCommand		byte	14h	; DSP command for a single-cycle transfer
	stopCommand		byte	0dah	; Stop AI
	tempDMAChannel		word	0h
	highDMAChannel		word	5h

idata           ends

LoadableCode    segment resource


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSPrepareMode
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Interprete DSP Helpcode

called by:	SBDDACSetSample

IN:		[sampleRate]
		[DSPFormatCommand]

OUT:		CF=1 error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	22.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSPrepareMode proc    far
	uses    ax,bx,cx,dx		;PUSH ax, ...
	.enter

	clr	ds:[hsFlag]
	mov	ds:[bsInterleave],1

;-----------------------
; detect Helpcode
;-----------------------
	mov	al,ds:[DSPFormatCommand]
	cmp	al,7fh			; Bit 7 ?
	LONG jbe	done

	mov	bx,ds:[DSPVersion]	; Version for later
;
; In this version only SB mono capabilities
;
	mov	bx,200h
	mov	dx,ds:[sampleRate]	; Rate for later
	cmp	al,81h			; 8 Bit mono ?
	LONG jne	done			; no

;-----------------------
;	8 Bit MONO
;-----------------------
	mov	ah,DSP_DMA_PCM_AI_MONO_LOW	; (1ch)
	mov	cl,DSP_DMA_PCM_MODE	; Singlecycle
	mov	ch,DSP_EXIT_AUTOINIT	; Exit
	cmp	dx,23000		; Highspeed ?
	jb	setDSPCommand		; no

	; Highspeed mono

	cmp	bx,200h			; Version < 2.01 ?
	ja	mv201			; no
	;
	; DSP 2.00
	;
	shr	dx,1			; yes, Samprate/2
	mov	ds:[sampleRate],dx	; store rate
	mov	al,2
        mov	ds:[bsInterleave],al	; Interleave = 2
	jmp	setDSPCommand		; End

mv201:
	mov	cl,DSP_DMA_HIGH_SPEED	; Singlecycle
	mov	ch,0			; Stop = Reset

	cmp	bh,3			; Version > 3.xx ?
	ja	progRate		; yes, programming Samplerate

	;
	; DSP 2.00...3.XX
	;
	mov	ds:[hsFlag],1
	mov	ah,DSP_DMA_PCM_AI_MONO_HIGH
	mov	cl,DSP_DMA_HIGH_SPEED	; Singlecycle
	mov	ch,0			; Stop = Reset
	jmp	setDSPCommand		; End

;-----------------------
; Samplerate for 4.XX
;-----------------------
progRate:
	SBDDACWriteDSP	DSP_SET_SAMPLE_RATE,0
	mov	cx,dx
	SBDDACWriteDSP	ch,0
	SBDDACWriteDSP	cl,0
	mov	cl,DSP_EXIT_AUTOINIT
	mov	ch,ah
	jmp	setDSPCommand		; End

;-----------------------
;  Store DSPCommand
;-----------------------
setDSPCommand:
	mov	ds:[singleCommand],cl
	mov	ds:[stopCommand],ch
	mov	ds:[DSPFormatCommand],ah
	jmp	done

;-----------------
;	END
;-----------------
done:
	.leave
	ret

BSPrepareMode	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSSecondAlloc
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Allocate a secondary buffer

called by:	AttachToStream

IN:		cx = length

OUT:		CF=1 error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	29.08.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSSecondAlloc proc    far
	uses    ax,cx		;PUSH ax, ...
	.enter
;	WARNING	BS_SECOND_LOCK
;--------------------
;	START
;--------------------

	call	BSECInit

;----------------------------
; Buffer already allocated ?
;----------------------------
	tst	ds:[bufferHandle]	; Handle to block allocated
					; Handle = 0 ?
	jne	done			; no, End

;----------------------
; 	Allocate Buffer
;----------------------
	mov	ax,cx			; size
	mov	ds:[bufferLen],ax	; store
	mov	cl,mask HF_FIXED	; HeapFlags
	mov	ch,mask HAF_ZERO_INIT	; HeapAllocFlags
	call	MemAlloc
	jc	error			; Error!

	mov	ds:[bufferHandle],bx	; Handle to block allocated
	mov	ds:[bufferSegment],ax	; Address of block allocated

	call	BSFillRest		; Clear buffer
	call	BSCreateStack		; Allocate Stack for ISR

;-----------------------
;   Prepare DMA
;-----------------------
	mov	bx,ax			; Bufferaddress
	mov	dx,ds:[bufferLen]	; size

	call	BSDMACheckBoundaries		; check DMA-Segment
	mov	ds:[bufferSegment],bx	; corrected segment address

        mov	cx,0			; Mode = Play
	call	ProgramDMADriver	; prepare DMA

;-----------------------
; Calculate Buffervalues
;-----------------------
	mov	ax,ds:[bufferLen]	; size
	mov	ds:[bufferFree],ax
	mov	ds:[bufferMax],ax
	clr	ds:[dacStatus]
	clr	ds:[bufferP2]		; Start Buffer
	shr	ax			; /2
	mov	ds:[bufferO2],ax	; Bufferhalf

;--------------------
;	OK-End
;--------------------
done:
	clc                             ; CF=0 OK
	jmp     short exit

;--------------------
;    Error END
;--------------------
error:
	stc				; CF=1 Error !

exit:
	.leave				; POP ax, ...
	ret

BSSecondAlloc endp



COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSDMACheckBoundaries
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Check segment boundaries and adjust settings if needed

called by:	BSSecondAlloc

IN:		bx = Segment
		dx = length

OUT:		bx = New segment
		dx = new length

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	29.08.98	Init

- If the buffer crosses a 64K boundary, use the larger part
  as the buffer.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSDMACheckBoundaries proc    near
	uses    ax,cx			;PUSH ax, ...
	.enter

;--------------------
;	START
;--------------------
        mov	ax,bx			; Segmentadresse
	and	ax,0fffh		; Mask out the 64K region
        mov	cl,4
	shl	ax,cl			; Offset within the 64K region
        add	ax,dx			; Check for a boundary crossing
	jnc	noproblem		; Passed!

;--------------------
;   Handle a boundary crossing
;--------------------
	mov	cx,ax			; Length beyond 64K (remaining length)
        mov	ax,dx			; ax = requested length
        shr	ax			; ax = half the length
        cmp	ax,cx			; Is the remaining length greater than half?
        jb	useTrailingSegment			; Yes
        sub	dx,cx
	jmp short noproblem1		; No, the remaining length is sufficient

;--------------------
; Region beyond
; the segment boundary
; as the secondary buffer.
;--------------------
useTrailingSegment:
        mov	ax,dx			; Old length
	sub	ax,cx			; Unused region
        mov	cl,4
        shr	ax,cl			; Offset-->Segment
        inc	ax			; Safety margin
        add	bx,ax			; New segment address
        shl	ax,cl			; Segment --> offset (bytes lost)
        sub	dx,ax			; Subtract

noproblem1:
;--------------------
;	END
;--------------------
noproblem:
	.leave				; POP ax, ...
	ret

BSDMACheckBoundaries endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSSetSamplerate
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Prepare calculations

called by:	SBDDACSetSample

IN:		dx	Samplerate

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	03.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSSetSamplerate proc    far
	uses    ax,cx,dx		;PUSH ax, ...
	.enter

;--------------------
;	INT
;--------------------
	call	BSGetDSPVersion		; Get the DSP version

;--------------------
;	END
;--------------------
	clc
	.leave				; POP ax, ...
	ret

BSSetSamplerate endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSGetDSPVersion
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Get the DSP version

called by:	?

IN:		ds	dgroup

OUT:		[DSPVersion]

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	22.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSGetDSPVersion proc    far
	uses    ax,bx,dx		; PUSH ax, ...
	.enter

;	WARNING	GET_DSP_VERSION

	SBDDACWriteDSP	DSP_GET_VERSION,0
        SBDDACReadDSP	0		; al = DSP return value
        mov	bh,al
        SBDDACReadDSP	0		; al = DSP return value
        mov	bl,al
	mov	ds:[DSPVersion],bx	; Store the version

;--------------------
;	END
;--------------------

	.leave				; POP ax, ...
	ret

BSGetDSPVersion endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSSingletransfer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Start a single-cycle transfer

called by:	DettachFromStream

IN:		cx	Byte count

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	02.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSSingletransfer proc    near
	uses    ax,bx,cx,dx		;PUSH ax, ...
	.enter
;	WARNING	BS_SINGLE_START
	clr	ds:[hsFlag]

;-----------------------------
; DSP command for single-cycle mode
; Calculate
;-----------------------------
        mov	bl,DSP_DMA_PCM_MODE	; Single mono
	mov	al,ds:[DSPFormatCommand]; Get the auto-init command
	cmp	al,1ch			; AI mono ?
	jz	single			; Yes
        ;
        ; Prepared single-cycle command
        ; Read
        ;
        mov	bl,ds:[singleCommand]	; Valid command?
        jz	done			; No, unknown

;--------------------
; Take the DSP out of auto-init
;--------------------
;	SBDDACWriteDSP	DSP_EXIT_AUTOINIT,0
        tst	cx			; Is there more to play?
        jz	setstate		; No

;--------------------
; Program the DSP
;--------------------
single:
	SBDDACWriteDSP  bl, 0
        dec	cx			; Length - 1
	SBDDACWriteDSP  cl, 0
	SBDDACWriteDSP  ch, 0

	mov	cl,3			; Status
setstate:
        mov	ds:[dacStatus],cl	; Set the end state

;--------------------
;	END
;--------------------
done:
	.leave				; POP ax, ...
	ret

BSSingletransfer endp

LoadableCode            ends

ResidentCode            segment resource

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSSecondWrite
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Write stream data to the secondary buffer
		Start auto-init when the buffer is full

called by:	Notificationroutine

IN:		cx	Bytes to write
		si	Offset Stream

OUT:		cx	Bytes written

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	29.08.98	Init
        DL	22.09.98	Handle interleaving

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSSecondWrite proc    far
	uses    ax,bx,dx,es,di,ds
	.enter
        call    SysEnterInterrupt		; LA 15.09.98

;--------------------
; Secondbuffer OK ?
;--------------------
        tst	ds:[bufferHandle]		; Is the secondary buffer allocated?
	jz	exitProc				; No, do nothing
	push	ds				; Stack [1]

;-------------------
; Get interleave
;-------------------
        mov	bx,cx				; bx = Bytes
        mov	ax,cx				; ax = Bytes
	mov	cl,ds:[bsInterleave]		; cl
        dec	cl
	mov	dl,cl				; dl = interleave
	shr	ax,cl				; Adjust available data
        mov	cx,ax				; cx = Bytes to copy

;--------------------
; Adjust length if needed
;--------------------
	mov	ax,ds:[bufferFree]
        cmp	ax,cx				; Less space than requested?
        jnc	enoughSpace				; No, length is OK
	mov	cx,ax				; Maximum length
enoughSpace:
	sub	ds:[bufferFree],cx		; Free space - length
        mov	ax,cx
        mov	cl,dl				; Interleave
        shl	ax,cl				; Calculate source bytes
        mov	cx,ax				; cx = Bytes to copy
	push	cx				; Stack [2]: length

;-------------------------
; Pointer to the secondary buffer
;-------------------------
        mov	di,ds:[bufferP2]		; Startoffset
	mov	ax,ds:[bufferSegment]
        mov	es,ax
        mov	bx,ds:[bufferLen]		; max Offset

;------------------------
; Pointer to stream data
;------------------------
        mov	ax, ds:[streamSegment]		; Pointer to the stream
        mov	ds,ax				; Source segment
        mov	al,dl				; al = Interleave
        inc	al				; Adjust back
	mov     dx, ds:[SD_max]			; dx = ptr-Max

;-------------------
; Counter = 0?
;-------------------
	tst	cx				; Is the buffer full?
        jz	done				; Yes, do not copy

;----------------
; Check offsets
;----------------
testoffs:
	cmp	di, bx				; Is the destination offset too large?
        jb	copybyte2			; No
        sub	di, bx				; Return to the start

copybyte2:
        cmp     si,dx				; End of stream?
	jb	copybyte			; No
        ;
        ;  We wrapped the pointer.  Subtract the max value
        ;       and add to starting value.
        ;
        sub     si, dx				; cx <- # past end
        add     si, offset SD_data              ; cx <- # past beginning

;-------------------
;	Transfer
;-------------------
copybyte:
	mov	ah,ds:[si]
	mov	es:[di],ah			; es:[di] := ds:[si]

        inc	di

        clr	ah
        add	si,ax				; SI + Interleave

	sub	cx,ax
        ja	testoffs			; Next byte

;--------------------
;   End of copy
;--------------------
done:
        pop	cx			; Stack [2]
        pop	ds			; Stack [1]
        mov	ds:[bufferP2],di	; Store the buffer pointer

;--------------------
; Start auto-init
;--------------------
	tst	ds:[dacStatus]		; Is the DAC still waiting?
        jne	finished			; No, end

        mov	ax,ds:[bufferFree]
        tst	ax			; Is the buffer full?
        jne	finished			; No

;-----------------------
;	AI
; Start auto-init here
; Do not change cx!
;-----------------------
	call	BSAutoInitStart
	jmp 	short exitProc

;-------------------------------
; NO_INT: empty the secondary buffer
;-------------------------------
finished:

ifdef BS_NO_INT
	call	BSDACISR
endif

;-----------------
;	END
;-----------------
exitProc:
        call    SysExitInterrupt	; LA 15.09.98
	.leave				; POP ax, ...

;	clr	ds:[blockISR]		; LA 10.09.98
	ret

BSSecondWrite endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSAutoInitStart
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Start auto-init or process data in the secondary buffer

called by:	BSSecondWrite

IN:		-

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	30.08.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSAutoInitStart proc    near
	uses    ax,cx,dx		;PUSH ax, ...

;	WARNING	BS_AI_START

	.enter

;--------------------
;   Set the status
;--------------------
        mov	al,1
        mov	ds:[dacStatus],al	; Startstatus

	clr	ds:[bufferP2]		; LA 15.09.98
        mov	ax,ds:[bufferLen]
        clr	ds:[bufferFree]

;--------------------
;	NO_INT
;--------------------
ifdef BS_NO_INT

;	call	BSDACISR			; Simulate an interrupt
        				; was triggered.
endif

;--------------------
;	INT
;--------------------
        mov	cx,ds:[bufferO2]	; Half the secondary buffer length
        dec	cx
	SBDDACWriteDSP  DSP_SET_BLOCK_SIZE, 0	; Block length
	SBDDACWriteDSP  cl, 0			; L Byte
	SBDDACWriteDSP  ch, 0			; H Byte

;--------------------
;  Start the transfer
;--------------------
	mov	cl,ds:[DSPFormatCommand]	; Get the auto-init command
	SBDDACWriteDSP  cl, 0		; Send

;--------------------
;	END
;--------------------

	.leave				; POP ax, ...
	ret

BSAutoInitStart endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSDACISR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Additional interrupt service code

called by:	ISR

IN:		-

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	30.08.98	Init
        DL	02.09.98	playEndFlag

- bufferFree + bufferO2
- bufferFree=bufferLen  --> dacStatus = 3
- dacStatus = 1 	--> (DSP is playing the second half)
		    	    bufferP2  = 0
                    	    dacStatus = 2
- dacStatus = 2 	--> (DSP is playing the first half)
		    	    bufferP2  = bufferO2
                    	    dacStatus = 1
- dacStatus = 3		--> program a single-cycle transfer

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSDACISR proc    far
	uses    ax,bx,cx,dx,es,ds,si,di	;PUSH ax, ... LA 15.09.98
	.enter
ifdef	BS_SWAT_WARNING

	WARNING	BS_ISR
endif

;------------------------
; blockISR (for debugging)
;------------------------
	tst	ds:[blockISR]		; Is the ISR blocked?
;       jnz     finished			; Yes
        mov	al,1
        mov	ds:[blockISR],al	; Block

;------------------------
; Emergency handling if
; streamStatus = 0
;------------------------
	tst	ds:[streamState]	; Is the status set?
        jnz	testdac			; Yes, OK

        call	MyBreak
	SBDDACWriteDSP	DSP_DMA_HALT,0	; Stop the DSP
	jmp     finished			; finished

;------------------------
; 	Check dacStatus
;------------------------
testdac:
        mov	al,ds:[dacStatus]
        cmp	al,0			; Idle?
        LONG jz	     finished			; Yes, do nothing
	cmp	al,3			; dacStatus = Singletransfer ?
        jnz	secondbuftest		; No

;------------------------
; dacStatus was a single-cycle transfer
;
; Stream was emptied (last transfer was single-cycle)
; While playEndFlag is clear, output can be restarted
; by filling the stream again.
;------------------------
	call	MyBreak
	clr	ds:[dacStatus]		; Status = 0
;	clr	ds:[bufferP2]		; LA 10.08.98

        jmp	finished

;------------------------
; Is the secondary buffer empty?
;------------------------
secondbuftest:
	mov	cx,ds:[bufferO2]	; Buffer half
	mov	ax,ds:[bufferFree]	; Free buffer space
	add	ax,cx			; One half is available again
        mov	ds:[bufferFree],ax	; Release a buffer half
        mov	dx,ds:[bufferLen]
        mov	bx,dx			; bx = length (for later use)

        sub	ax,cx			; Is the buffer empty?
        jbe	swapdacstate		; No

;--------------------
;  End output
;
; Fill the rest of the buffer half
; with the silence value (80h).
; Fill
;--------------------
        mov	ds:[bufferFree],dx	; The full length is available
        mov	cx,ax			; Remaining length
	mov	al,3			; Status = 3
        mov	ds:[dacStatus],al	; Store

        call	BSFillRest		; Fill the rest with silence

;------------------
;   Halt the DSP
;------------------

	tst	ds:[hsFlag]		; Highspeed ?
        jz	exitlow			; No
        call    SBDInitChipDSP		; RESET ends high-speed auto-init
	clr	ds:[hsFlag]		; Reset the high-speed flag
        clr	ds:[dacStatus]
        call	MyBreak
        jmp	deblock			; finished
        ;
	; Normal transfer
        ;
exitlow:
	SBDDACWriteDSP	DSP_EXIT_AUTOINIT,0
        ;
deblock:
	clr	ds:[blockISR]		; Unblock the next ISR
        jmp	finished

;--------------------
; Swap dacStatus
;--------------------
swapdacstate:
	mov	dx,0			; bufferP2 when status = 1
        mov	al,ds:[dacStatus]
        xor	al,3			; Swap status 1-->2 or 2-->1
        mov	ds:[dacStatus],al	; Store
        cmp	al,1			; Old status = 2?
        jne	stateold2		; No
        mov	dx,cx			; bufferP2 = 0 when status = 2

stateold2:

	mov	ds:[bufferP2],dx	; Start pointer for the next transfer
	mov	ax,ds:[bufferP2]	; Start pointer for the next transfer
        sub	ax,bx
        jb	finished			; Pointer at the end?

	mov	ds:[bufferP2],ax	; Adjusted pointer

;----------------
; 	END
;----------------
finished:

	.leave				; POP ax, ...
	ret

BSDACISR endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSFillRest
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Clear the rest

called by:	?

IN:		cx	Byte count
		(glob)	bsRecBits

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	08.09.98	Init
        DL	04.01.2000	Value for fill depends from bsRecBits

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSFillRest	proc far
	uses    ax,cx,dx,es,si		;PUSH ax, ...
	.enter

EC<	WARNING	BS_FILL_REST>

;-------------------
; define fill value
;-------------------

        mov	al,80h			; fillvalue 8 Bit
	mov	ah,ds:[bsRecBits]
        cmp	ah,16			; 16 Bit ?
        jnz	fill			; no
        mov	al,0			; yes

	;
        ; cx = byte count
        ;
fill:
        mov	es,ds:[bufferSegment]
        mov	si,ds:[bufferP2]
        mov	dx,ds:[bufferLen]	; Boundary
        tst	cx			; Length = 0?
        jz	finished			; Yes, finished
silence:
	cmp	si,dx			; si < bufferLen ?
        jae	finished			; No, finished
        mov	es:[si],al
        inc	si
        dec	cx
        jnz	silence
finished:
        .leave
        ret

BSFillRest	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSSecondUnlock
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Free the secondary buffer memory
		Stop DMA if needed

called by:	Routine that ends the transfer

IN:		-

OUT:
		bufferHandle = 0
                bufferSegment= 0
                bufferLen    = 0


REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	29.08.98	Init
        DL	07.09.98	Do not reset bufferSegment or bufferLen

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSSecondUnlock proc    far
	uses    ax,cx			;PUSH ax, ...
	.enter

;	WARNING	BS_SECOND_UNLOCK

;--------------------
;	Active?
;--------------------
	mov	ax,ds:[bufferHandle]	; Handle to block allocated
        mov	bx,ax
        tst	ax			; Handle = 0 ?
        jz	done			; Yes, end

;----------------------------
;	DMA Stop
;----------------------------
	push	bx			; Stack[1] = bx

;-----------------
; DSP DMA Stop
;-----------------
        mov	bh,DSP_EXIT_AI8
	mov	al,ds:[bsRecBits]
	cmp	al,16				; 16 Bit
	jnz	exitdsp			; No
        mov	bh,DSP_EXIT_AI16
exitdsp:
	SBDDACWriteDSP	bh,0	; The actual stop command

        mov	ax,30
        call	TimerSleep

;---------------------
;	Disable DMA
;---------------------
	mov     cx, ds:[baseDMAChannel]  ; cx <- channel for transfer
	mov     dl, 1
	shl     dl, cl                  ; dl <- mask for channel

	mov     di, DR_DISABLE_DMA_REQUESTS

	INT_OFF
	call    ds:[DMADriver]                  ; mask out the channel
        INT_ON

	;
	;  Also, we tell the DMA chip to
	;       stop the transfer and finally
	;       we release the channel

;-------------------
;	Stop DMA
;-------------------

	mov     dx, ds:[baseDMAChannel]         ; dl <- channel
	mov     di, DR_STOP_DMA_TRANSFER
	INT_OFF
	call    ds:[DMADriver]                  ; stop the DMA transfer
        INT_ON
	mov     cx, ds:[baseDMAChannel]
	mov     dl, 1
	shl     dl, cl
	mov     di, DR_RELEASE_CHANNEL
	INT_OFF
	call    ds:[DMADriver]
        INT_ON

	pop	bx			; bx = Stack[1]

;----------------------------
; Free the secondary buffer
;----------------------------
	call	MemFree			; Free memory
        clr	ds:[bufferHandle]

;--------------------
; Free the ISR stack
;--------------------
	call	BSFreeStack

;--------------------
;	END
;--------------------
done:
        mov	ds:[bsRecBits],8	; Clear the 16-bit flag
        mov	ax,ds:[tempDMAChannel]
        mov	ds:[baseDMAChannel],ax	; Current DMA channel
					; restored
	.leave				; POP ax, ...
	ret

BSSecondUnlock endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSECInit
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Prepare the EC check

called by:       ?

IN:             -

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	17.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSECInit proc    far

	.enter

;-----------------------
;	Save DS
;-----------------------
	mov     cs:[BS_ECListDS],ds	; Save the data segment

        .leave
	ret

BSECInit endp

BS_ECListDS	word	0			; DS

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSECTest
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       EC check

called by:       ?

IN:             -

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	17.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSECTest proc    far
	uses	ax
	.enter

;-----------------------
;	Check DS
;-----------------------
	mov     ax,ds			; Get the data segment
	cmp	ax,cs:[BS_ECListDS]	; Compare
        jnz	error			; Error!

;-----------------------
;	Check SS
;-----------------------
	mov	ax,ss
        cmp	ax,00ffh		; Invalid stack segment?
        jbe	error			; Yes
        cmp	ax,09f00h		; Above 640K?
        jb	done			; No
error:
;EC<	ERROR	BS_EC_TEST_ERROR_DS	>
done:
        .leave
	ret

BSECTest endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSECTestStream
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       EC check

called by:      ?

IN:             ds	dgroup
		bx	Streamsegment

OUT:		-

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	22.09.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSECTestStream proc    far
	uses	ax
	.enter

;-----------------------
;	Check the stream
;-----------------------
	mov	ax,ds:[streamSegment]
        cmp	ax,bx			; Segment unchanged?
        jz	done			; Yes

	ERROR	BS_EC_TEST_ERROR_STREAM
done:
        .leave
	ret

BSECTestStream endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		ProgramDMADriver
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Program the DMA driver

CALLED BY:      BSSecondAlloc

PASS:           bx      -> stream segment
		dx      -> buffer size
                cx	-> Modeflag	(2 -> Recording, else Playing)
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
        DL	23.03.2000	16 Bit
        DL	04.11.2000	Recording/Playing (cx)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
ProgramDMADriver    proc    far
        uses	ax			; 23.03.2000

	.enter
	;
        push	cx			; mode (2 = Record) [2]
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
        mov	ds:[tempDMAChannel],cx
	mov	al,ds:[bsRecBits]
        cmp	al,16			; 16 Bit ?
        jnz	prep
        mov	cx,ds:[highDMAChannel]	; High DMA channel
        mov	ds:[baseDMAChannel],cx	; Current DMA channel
prep:
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
	mov     dx, ds:[baseDMAChannel] ; dl <- channel #
        cmp	dl,4			; High-DMA ?
	jb	setsize			; No
        shr	ax			; High DMA: convert the byte count
        				; to a word count
setsize:
	mov     dh, ModeRegisterMask <DMATM_SINGLE_TRANSFER,0,1,DMATD_READ>
        pop	cx			; [2]
        cmp	cx,2			; Recording ?
        jnz	norec			; No
	mov     dh, ModeRegisterMask <DMATM_SINGLE_TRANSFER,0,1,DMATD_WRITE>
norec:
	dec     ax                      ; transfer size -1
	push	ax			; Save for the check
	mov     cx, ax                  ; cx <- size of buffer
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
	cmp	dl,4			; High-DMA ? (Word)
        jb	setlen			; No, cx contains the size in bytes
	shl	cx			; High DMA: convert words to bytes
        				; In bytes
setlen:
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
	pop	cx			; clean up stack [2] [1]
	pop     dx
	stc
	jmp     short done
ProgramDMADriver	endp

ResidentCode            ends

