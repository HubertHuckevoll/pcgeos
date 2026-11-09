COMMENT @********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved

PROJECT:	BestSound Template

FILE:		bsstream.asm

AUTHOR:		Dirk Lausecker

REVISION HISTORY:
	Name	Date		Description
	----	-----		------------
	DL	08.08.98	Init

ROUTINES:
	Name			Description
	----			-----------
	SBDDACReadNotification	Notificationroutine
        BSDischargeStream	Read cx bytes from the stream


Description:
	Template for sound drivers.

*****************************************************************@


ResidentCode	segment	resource
COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		SBDDACReadNotification
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Notification reciepiant routine

CALLED BY:	Stream Driver
PASS:		cx	-> # of bytes to read
		dx	-> stream token (virtual segment)
		bx	-> stream segment

RETURN:		nothing

DESTROYED:	ax, cx (allowed ax, bx, si, di)

SIDE EFFECTS:
		Sets up parameters for next interrupt transfer

PSEUDO CODE/STRATEGY:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
        DL	09.08.98	Template

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
SBDDACReadNotification	proc	far
	pushf
	uses	cx, dx, ds, es			; LA 15.09.98
;	uses	ax, cx, dx, ds, es, si, di, bx
	.enter

	mov	ax, segment dgroup		; ax <- dgroup of driver
	mov	ds, ax				; ds <- dgroup of driver

;----------------------------
; Detect stream data (cx)
;----------------------------
	tst	cx				; cx=0: threshold change?
	jz	sendAck				; Yes

;----------------------------------------
;	The stream contains data to send
;----------------------------------------
streamsz:
	mov	ds:[dataOnStream], cx		; Save the byte count

	mov	ax, ds:[streamSize]		; ax <- upper limit on size

	cmp	ax, cx				; More data than the stream length?
						; (NOT ALLOWED!)
	jb	sendAck                 	; No

;==============================
;	Read from the stream
;
; At this point, the threshold values
; Data read from the stream
; must be updated.
;
;	cx = byte count
;==============================
	call	BSECTestStream		; Check the stream

	call	BSDischargeStream
        sub	ds:[dataOnStream],cx	; Update stream data
	mov	ax,ds:[dataOnStream]
        mov	cx,ax
        tst	ax			; Is there still data?
        jnz	streamsz		; Yes, wait until the stream is empty

;----------------------------
; 	Send ACK to the reader
;----------------------------
sendAck:
	mov	ds, bx				; ds <- stream segment

	;
	;  We want to be notified of every write done by the writer.
	;  But each time this routine gets called, the driver sets
	;  flags that prevent a notification from being sent until
	;  we act on the previous notification.  That is, until we
	;  read something.  To deal with this little problem
	;  we send our own "acknowledgment" by fiddling with the
	;  stream settings.
	;
	;  Send and "ack"
	;  Reset the reader state.

	clr	ds:[SD_reader.SSD_data].SN_ack
	and	ds:[SD_state], not mask SS_RDATA

done::
	.leave

        popf			; restore flags
	ret

SBDDACReadNotification	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSDischargeStream
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Read data from the stream

CALLED BY:
PASS:		cx	-> # of bytes to read
		bx	-> stream segment ??? La 28.08.98

RETURN:		cx	= Bytes read

DESTROYED:

SIDE EFFECTS:

PSEUDO CODE/STRATEGY:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
        DL	09.08.98	Template
        DL	30.09.98	Secondarybuffer
        DL	01.09.98	Wait until cx bytes have been read

ToDo-List:
----------
- Timeout

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSDischargeStream proc far
        uses    ax, bx, dx, ds, si, di, es
	.enter
;	INT_ON				; LA 10.09.98

ifdef	BS_SWAT_WARNING
	WARNING	BS_DISCHARGE
endif
	call	BSECTest

;-------------------------------
;	Check available data
;-------------------------------
        mov	ax,ds:[dataOnStream]	; Data in the stream
	cmp     cx, ax   		; Is enough data available?
	jnc	enoughSpace			; Yes
        mov	cx,ax			; No, use the available amount

;---------------------------------
; Copy data to the secondary buffer
; and wait until all data
; has been consumed.
;---------------------------------
enoughSpace:
        mov	bx,60			; At most 60 attempts
        push	es
        mov	ax,ds:[streamSegment]	; Offset Stream
        mov	es,ax
	mov     si,es:[SD_reader].SSD_ptr
        pop	es

	mov	dx,cx			; dx = count
        mov	ax,cx			; ax = initial count
retryWrite:
        tst	ds:[bufferFree]		; Is the buffer still empty?
        jz	waitForData			; Yes, wait

        mov	cx,ax
        call	BSSecondWrite		; Data --> secondary buffer
	call	BSECTest
        				; cx = bytes read
        sub	ax,cx			; All data read?
        jz	finished			; Yes
waitForData:
        push	ax
        mov	ax,1
	call	TimerSleep		; LA 17.09.98
        pop	ax

ifdef	BS_NO_INT
	call	BSDACISR
        mov	ax,2
	call	TimerSleep		; LA 17.09.98
endif
	dec	bx			; No attempts left
        jnz 	retryWrite			; No, retry

;---------------------------------
; 60 attempts did not
; finish reading the stream.
; Playback was probably interrupted
; and BSDACISR set
; dacStatus to zero.
;---------------------------------
        tst	ds:[dacStatus]		; Is the DSP idle?

        jnz	finished			; No, ignore the problem

        				; LA: NEEDS REVIEW !!!

	call	BSAutoInitStart		; Restart the transfer
        jmp	short enoughSpace

;--------------------------------
;     Copy complete
;--------------------------------
finished:
        mov	cx,dx			; Return the count
        mov	bx,ds:[streamSegment]	; bx points to the stream structure

	push	cx			; Stack [1] cx

;--------------------------------
;	Update the stream
;--------------------------------

; updateStream label near
        push    es                      ; Stack [2] es

        mov     es, ds:[streamSegment]

        ;
        ;  Update semaphores for reader and writer
        ;
;---------------------------
; Update semaphores
;---------------------------

        sub     es:[SD_reader.SSD_sem].Sem_value, cx	; Bytes that must be read
        add     es:[SD_writer.SSD_sem].Sem_value, cx	; Free bytes in the stream

;-----------------------------
;  Update the reader pointer
;-----------------------------
	add     cx, es:[SD_reader].SSD_ptr
	cmp     cx, es:[SD_max]

;	jbe	writeReaderPtr			; LA 04.09.98
	jb	writeReaderPtr			; LA 04.09.98

        ;
        ;  We wrapped the pointer.  Subtract the max value
        ;       and add to starting value.
        ;
        sub     cx, es:[SD_max]                 ; cx <- # past end
        add     cx, offset SD_data              ; cx <- # past beginning

;---------------------------
; Set the reader pointer (cx)
;---------------------------

writeReaderPtr:
	mov     es:[SD_reader].SSD_ptr, cx

	mov     cx, di                                  ; save trashed reg.

        ;
        ;  We are now going to call the stream driver to
        ;       handle updating the stream.  This can
        ;       and does enable interrupts, so we need to
        ;       make sure we don't context switch.
        ;  Call SysEnterInterrupt to deal with this.

;-------------------------------------------
; Allow new data to be written to the stream
;
;- Prevent context switches
;- Release the writer
;- Disable interrupts
;- Allow context switches
;-------------------------------------------

        call    SysEnterInterrupt

        call    StreamWriteDataNotify   		; destroys ax, di

        mov     di, cx                                  ; restore trashed reg.

        tst     es:[SD_reader.SSD_sem].Sem_queue
        jz      sendACK

;-------------------------------
; Unblock the writer semaphore
;-------------------------------

        ;
        ;  Since there is a writer blocked on writing,
        ;       we need to free it up so it can write.
        mov     cx, bx                                  ; save trashed reg.

        mov     ax, es                                  ; ax:bx <- queue
        mov     bx, offset SD_reader.SSD_sem.Sem_queue
        call    ThreadWakeUpQueue

        INT_OFF			; LA 17.09.98

        mov     bx, cx                                  ; restore trashed reg.

sendACK:
        pop     es                              ; Stack [2]

        call    SysExitInterrupt

        pop	cx				; Stack [1] cx

        .leave
	ret

BSDischargeStream endp


ResidentCode		ends

