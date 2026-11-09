COMMENT @/********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved


 THE MIXER FUNCTIONS ARE NOT PART OF THE LICENSING CONTRACT
 BETWEEN NEWDEAL INC. AND DIRK LAUSECKER !
 THE COMMENTS WILL BE FULLY TRANSLATED WHEN THE MIXER FEATURE
 WAS LICENSED BY NEWDEAL OR OTHER COMPANIES !


PROJECT:	BestSound

FILE:		bsmixer.asm

AUTHOR:		Dirk Lausecker

REVISION HISTORY:
	Name	Date		Description
	----	-----		------------
	DL	06.10.98	Init
        DL	20.02.2000	NewWave (bsRecordState -> bsStatus)

ROUTINES:
	Name			Description
	----			-----------
	BSMixerGetCap		Number of control channels
	BSMixerGetValue		Read a control value
        BSMixerSetValue		Set a control value
        BSMixerSetDefault	Set default values
        BSMixerReset		Reset the mixer chip

Description:
	Routines to control the mixer chip.

*****************************************************************/@

VAL_LEN		equ	12

idata           segment

	bsMixerValMax		word	1h	; Number of values
        valTabOffs		word	0	; Offset valueTable
	subTabOffs		word	0	; Offset subTokenTable

idata           ends

LoadableCode            segment resource


;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
;	GetOffToValTab
;
; Return the offset of the value table
;
;  IN:	[valTabOffs]	Offset valueTable
;  	[subTabOffs]	Offset subTokenTable
;
; OUT:	bx  Offset of the value table
;	cx  Offset of the subtoken table
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

GetOffToValTab	proc	far
	uses	ax,dx,di
        .enter
	mov	ax,segment dgroup
        mov	ds,ax

; Check the pointer

        mov	bx,ds:[valTabOffs]
        mov	cx,ds:[subTabOffs]
        tst	bx			; Is the value table set?
        jne	done			; Yes, finished

; Set the pointer again

;-------------------------
; Wait until the DSP is available
;-------------------------
teststream:
	tst	ds:[dacStatus]		; Is the DAC available?
        jz	testrecording		; Yes
; Wait
	mov	ax,10
        call	TimerSleep		; Wait
        jmp	teststream

;------------------
; Check recording and playback
;------------------
testrecording:
	tst	ds:[bsStatus]		; Recording or playback active?
        jz	getversion		; No, continue

; Wait
	mov	ax,10
        call	TimerSleep		; Wait
        jmp	testrecording

getversion:
	call	BSGetDSPVersion

        mov	di,offset mixerSuperTable
        mov	ax,ds:[DSPVersion]	; DSP Version

        cmp	ax,400h			; SB 16 ?
        jae	select			; Yes
        add	di,4			; Advance the pointer

        cmp	ax,201h			; SB Pro
        jae	select			; Yes
        add	di,4			; Advance the pointer

        cmp	ax,200h			; SB 2.0 CD
        jae	select			; Yes
        add	di,4			; Advance the pointer

; Get and save the pointer
select:
	mov	bx,cs:[di]		; valueTable
        inc	di
        inc	di
	mov	cx,cs:[di]		; SubtokenTable
        mov	ds:[valTabOffs],bx
        mov	ds:[subTabOffs],cx

; Return the pointer
done:
                .leave
                ret

GetOffToValTab	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerGetCap
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Get the control channels (values)

Called by:	Mixer library

IN:

OUT:            cx      Number of channels
		dx	DSP-Version
		CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	06.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerGetCap proc    far
	uses    ax,bx,ds		;PUSH ax, ...
	.enter

	mov	ax,segment dgroup
        mov	ds,ax

;	WARNING	MIXER_GET_CAP

        clr	ds:[valTabOffs]

; Force the pointer to be calculated again

	call	GetOffToValTab

; Count the value table entries
        clr	ds:[bsMixerValMax]
next:
		cmp	{word} cs:[bx],0		; End of the word table?
        jz	done			; Yes
        add	bx,VAL_LEN
        inc	ds:[bsMixerValMax]
        jmp	short next

;-----------------
;     END
; bsMixerValMax
;-----------------
done:
        mov	cx,ds:[bsMixerValMax]	; Test
        mov	dx,ds:[DSPVersion]
	.leave
        ret

BSMixerGetCap	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerGetValue
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Read a channel

Called by:	Mixer library

IN:		dx	Token

OUT:            ax      Value
		CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	08.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerGetValue proc    far
	uses    bx,cx,dx,si,di		;PUSH ax, ...
	.enter

; Find the token in TokenRegTable

        mov     ax,0		; Default result on error
        mov	cx,dx		; Token
        call	TokenToIndex	; di = Index
	jc      error		; Error

        add	bx,4		; Typ
        mov	dh,cs:[bx]	; Value type

        add	bx,4		; Offset 1
        mov	di,bx

; Parameter Read

	mov	dl,cs:[di]
        inc	di
        mov	bl,cs:[di]		; Bitmask
        inc	di
        push	dx
        call	BSMixerGetRegister	; Left
	pop	dx			; dh = value type
	mov	bh,al			; Save the value

; Write the second parameter (right) if defined

	mov	dl,cs:[di]
        cmp	dl,0			; Empty?
        je	done			; Yes, abort
        inc	di
        mov	bl,cs:[di]		; Bitmask
        call	BSMixerGetRegister	; Right
	mov	ah,al			; ah = second value
        mov	al,bh			; al = first value

;-----------------
;	END
;-----------------
done:
        clc
error:
	.leave
        ret

BSMixerGetValue	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerSetValue
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Describe a mixer channel

Called by:	Mixer library

IN:		dx	Token	0 = Reset
		al	Left value
                ah	Right value

OUT:            CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	08.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerSetValue proc    far
	uses    ax,bx,cx,dx,di,si		;PUSH ax, ...
	.enter

;        call	SysEnterInterrupt	; LA 18.10.99 disabled

; Reset
; (Write any value to register 00)

        tst	dx		; Reset ?
        jnz	tsearch		; No
	mov	dh,2		; No adjustment
        mov	ah,1		; Bit mask
	call	BSMixerSetRegister
        jmp	done		; End

; Find the token in TokenRegTable
tsearch:
        mov	cx,dx		; Token
        call	TokenToIndex	; di = Index
	jc      error		; Error

        add	bx,4		; Pointer to the type
				; (Boolean values must not be adjusted)
        mov	dh,cs:[bx]	; Value type

        add	bx,4		; Pointer to offset1
        mov	cx,ax		; Left and right values

; Parameter Read

	mov	dl,cs:[bx]	; Register
        inc	bx
        mov	ah,cs:[bx]	; Bit mask
        inc	bx
        mov	al,cl		; Left value
        call	BSMixerSetRegister	; Output

; Write the second parameter (right) if defined

	mov	dl,cs:[bx]
        cmp	dl,0			; Empty?
        je	done			; Yes, abort
        inc	bx
        mov	ah,cs:[bx]
        mov	al,ch
        call	BSMixerSetRegister	; Right

;-----------------
;	END
;-----------------
done:
        clc
error:
;        call	SysExitInterrupt	; LA 18.10.99
	.leave
        ret

BSMixerSetValue	endp

;-----------------------
;
;	TokenToIndex
;
; 	Find the token
;
;  IN	cx	token
;  OUT	di	index (valNum)
;	bx	Pointer to the entry
;	CY=1	not found
;
;-----------------------
TokenToIndex proc    near
	uses	ax,cx,dx,ds,si
        .enter
	mov	ax,segment dgroup
        mov	ds,ax
        push	cx
	call	GetOffToValTab
        mov	si,bx			; si Valuetable
        pop	cx
        mov	dx,ds:[bsMixerValMax]

        mov	di,0
search:
	cmp     cs:[bx], cx
        je	found
        add	bx,VAL_LEN
        inc	di
        dec	dx
        jne	search
        mov	bx,si
        mov	di,0
        stc
        jmp	done
found:
	clc
done:
	.leave
        ret
TokenToIndex endp

;--------------------------------
;
;	BSMixerGetRegister
;
; IN	dl	Register number
;	dh	Value type
;		1 = slider (adjust)
;	bl	Bitmask
; OUT	al	Value
;	dx	Data port address
;--------------------------------

BSMixerGetRegister proc    near
	uses	bx,cx
        .enter
        mov	ch,dh		; dh = saved type
        mov	al,dl
	mov	dx,ds:[basePortAddress]
        add	dx,4		; Mixer Address Port
        out	dx,al
        inc	dx
        in	al,dx		; Read
	and	al,bl		; Mask bits
        tst	bl		; Is at least one bit set?
	je	done		; No
        cmp	ch,1		; Slider ?
        je	slider		; Yes
        cmp	ch,2		; Itemgroup ?
        jne	done		; No

itemgroup:
        sar	bl		; Is bit 0 set?
        jc	done		; Yes
        shr	al		; No, adjust the value
        jmp short itemgroup	; next

slider:
        sal	bl		; Is bit 7 set?
        jc	done		; Yes
        shl	al		; Adjust the value
        jmp short slider
done:
	.leave
        ret             	; dx = Data Port

BSMixerGetRegister endp

;--------------------------------
;
;	BSMixerSetRegister
;
; IN    dl	Register
;	dh	Value type
;		1 = slider (adjust)
;		2 = Itemgroup
;	al	Value
;	ah	Bit mask
;--------------------------------

BSMixerSetRegister proc    near

	uses	ax,bx,cx,dx
        .enter

; Adjust the value for slider and item-group types
        mov	cl,ah		; Bit mask
        tst	cl		; Is the bit mask valid?
        jz	getreg		; No

	cmp	dh,1		; Slider ?
        jz	slider		; Yes
        cmp	dh,3		; Boolean ?
        jz	getreg		; Yes, no adjustment

itemgroup:
        sar	cl		; Is bit 0 set?
        jc	getreg		; Yes
        shl	al		; Adjust the value
        jmp short itemgroup

; Adjustment
slider:
        sal	cl		; Is bit 7 set?
        jc	getreg		; Yes
        shr	al		; Adjust the value
        jmp short slider

; Read the register
getreg:
        mov	cx,ax		; Save the value and bit mask
        mov	bl,0ffh		; Bit mask = 0FFh: no adjustment
        call	BSMixerGetRegister

        mov	ah,0ffh
        xor	ah,ch		; Inverted bit mask
        and	al,ah		; al = masked-out bits

        and	cl,ch		; Mask the value bits
        or	al,cl		; Calculate the control value
        out	dx,al
	.leave
        ret             	; dx = Data Port

BSMixerSetRegister endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerSetDefault
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Initialize the mixer chip

Called by:	Mixer library

IN:		-

OUT:            CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	08.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerSetDefault proc    far
	uses    ax,bx,cx,dx		;PUSH ax, ...
	.enter

;-----------------
;	END
;-----------------
;done:
        clc
	.leave
        ret

BSMixerSetDefault	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerGetSubToken
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Return the text assigned to a token

Called by:	Mixer library

IN:             dx	identifier
		cx	Token

OUT:            ax	SubToken

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	10.10.98	Init

 ATTENTION: Although identifier is a word, the table supports
 	  only eight selectors (0x01 .. 0x80). Extend the table to add more.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerGetSubToken proc    far
	uses    bx,cx,dx,di		;PUSH ax, ...
	.enter

;-----------------------
; Find the token
;-----------------------
        mov	di,dx			; identifier for later
        push	cx
        call	GetOffToValTab
        mov	bx,cx
        pop	cx			; Restore the token
        mov	ax,0			; not found Token
search:
        mov	dx,cs:[bx]
        cmp	dx,0			; End marker?
        je	done			; Yes!
        cmp	dx,cx			; Token found?
        je	found			; Yes!
        add	bx,18			; Next position
        jmp	search

;-----------------------
; Get the subtoken
;-----------------------
found:
        inc	bx
        inc	bx
	mov	dx,di			; identifier
        tst	dl			; Is identifier valid (0x01 to 0x80)?
        je	done
subsearch:
        shr	dl			; Is the LSB set?
        jc	found2			; Yes
        inc	bx			; No, try the next position
        inc	bx
        jmp	subsearch
found2:
	mov	ax,cs:[bx]		; SubToken

;-----------------
;	END
;-----------------
done:
	.leave
        ret

BSMixerGetSubToken	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerTokenToText
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Return the text assigned to a token

Called by:	Mixer library

IN:		ax:bx	Destination text buffer
		cx	Token

OUT:            CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	09.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerTokenToText proc    far
	uses    ax,bx,cx,dx,es,si,di		;PUSH ax, ...
	.enter

        mov	es,ax		; Destination
        mov	si,bx

;-----------------------
; Find the token
;-----------------------
        mov	bx,0
search:
        mov	ax,cs:tokenToTextList[bx]
        tst	ax
        jz	notfound

	cmp     ax , cx
        je	found
        add	bx,2
        jmp	short search

notfound:
	; Index the fallback pointer rather than its text address.
		mov	bx, offset TTLnotFound - offset tokenTextList

;-----------------------
; Pointer to source text
;-----------------------
found:
	mov	di,cs:tokenTextList[bx]

;-----------------------
; Copy source text to the destination
;-----------------------

	mov	cx,31		; max. Count
loop1:
	mov	al,cs:[di]
	mov	es:[si],al
	tst	al		; End?
	je	done		; Yes
        inc	si
        inc	di
	dec	cx
	jne	loop1		; next

;-----------------
;	END
;-----------------
done:
        clc
	.leave
        ret

BSMixerTokenToText	endp

tokenToTextList	word	50
		word	51
                word	52
		word	0		; End the token search.

tokenTextList	word	offset	tokenText50
		word	offset	tokenText51
TTLnotFound	word	offset	notfoundText

tokenText50	char	'Input Source',0
tokenText51	char	'token51',0
notfoundText	char	'unknown',0

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BSMixerSpecValue
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Function:       Describe a control value

Called by:	Mixer library

IN:		dx	valNum

OUT:            ax	Range
		bx	Token
                cl	Type
                ch	sliderNum
                dl	target
                dh	visible,stereo
		CF=1 	Error

REVISION HISTORY:
	Name    Date            Description
	----    ----            -----------
	DL	10.10.98	Init

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BSMixerSpecValue proc    far
	uses    di		;PUSH ax, ...
	.enter

; Calculate the pointer
	call	GetOffToValTab	; bx = pointer to valueTab

	mov	ax,VAL_LEN    	; Length of one entry
        mul	dx
        add	ax,bx
        mov	di,ax

; Read the token table

	mov     bx,cs:[di]	; Token
        inc	di
        inc	di
	mov     ax,cs:[di]	; Range
        inc	di
        inc	di
	mov     cx,cs:[di]	; Typ, Slidernum
        inc	di
        inc	di
	mov     dx,cs:[di]	; target, visible

;-----------------
;	END
;-----------------
;done:
        clc
	.leave
        ret

BSMixerSpecValue	endp

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mixerSuperTable	label	word
	word	offset	valTab1745	; valueTable CT1745
        word	offset  subTab1745	; subTokenTable

	word	offset	valTab1345
	word	offset	subTab1345

	word	offset	valTab1335
	word	offset	subTab1335

	word	offset	valTabDum	; For an unknown DSP version
	word	offset	subTabDum

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;		CT 1745
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
valTab1745	label	word
	word	1		; BSMX_TOKEN_MASTER
	word	255		; Range
        byte	1,0,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    030h,0f8h	; Offset, bit mask 1
        byte	031h,0f8h	; Offset, bit mask 2
; MIDI (FM)
	word	2		; BSMX_TOKEN_MIDI
	word	255		; Range
        byte	1,1,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    034h,0f8h	; Offset, bit mask 1
        byte	035h,0f8h	; Offset, bit mask 2
; VOICE (WAV)
	word	4		; BSMX_TOKEN_VOICE
	word	255
        byte	1,2,1
	byte	0C0h
	byte    032h,0f8h	; Offset, bit mask 1
        byte	033h,0f8h	; Offset, bit mask 2
; CD
	word	3		; BSMX_TOKEN_CD
	word	255
        byte	1,3,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    036h,0f8h	; Offset, bit mask 1
        byte	037h,0f8h	; Offset, bit mask 2
; LINE
	word	5		; BSMX_TOKEN_LINE
	word	255		; Range
        byte	1,4,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    038h,0f8h	; Offset, bit mask 1
        byte	039h,0f8h	; Offset, bit mask 2
; Microphone
	word	6		; BSMX_TOKEN_MIC
	word	255		; Range
        byte	1,5,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    03ah,0f8h
        byte	00h,00h

; Speaker
	word	7		; BSMX_TOKEN_SPEAKER
	word	255		; Range
        byte	1,6,1		; Type,sliderNum,target
	byte	00h		; visible,stereo
	byte    03bh,0c0h
        byte	00h,00h
; Bass
	word	9		; BSMX_TOKEN_BASS
	word	255		; Range
        byte	1,7,1		; Type,sliderNum,target
	byte	0c0h		; visible,stereo
	byte    046h,0f0h
        byte	047h,0f0h
; Treble
	word	8		; BSMX_TOKEN_TREBLE
	word	255		; Range
        byte	1,8,1		; Type,sliderNum,target
	byte	0c0h		; visible,stereo
	byte    044h,0f0h
        byte	045h,0f0h

; Output mixer switches (playback sources)
	word	15		; BSMX_TOKEN_OUT_MX_SW
	word	5		; Range
        byte	3,9,3		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    03ch,01fh
        byte	00h,00h
; Left input mixer switches (recording sources)
	word	16		; BSMX_TOKEN_IN_MX_SW_L
	word	7		; Range
        byte	3,10,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    03dh,07fh
        byte	00h,00h
; Right input mixer switches (recording sources)
	word	17		; BSMX_TOKEN_IN_MX_SW_R
	word	7		; Range
        byte	3,11,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    03eh,07fh
        byte	00h,00h
; Left input gain
	word	18		; BSMX_TOKEN_IN_GAIN_L
	word	4		; Range
        byte	2,12,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    03fh,0c0h
        byte	00h,00h
; Right input gain
	word	19		; BSMX_TOKEN_IN_GAIN_R
	word	4		; Range
        byte	2,13,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    040h,0c0h
        byte	00h,00h
; Left output gain
	word	20		; BSMX_TOKEN_OUT_GAIN_L
	word	4		; Range
        byte	2,14,3		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    041h,0c0h
        byte	00h,00h
; Right output gain
	word	21		; BSMX_TOKEN_OUT_GAIN_R
	word	4		; Range
        byte	2,15,3		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    042h,0c0h
        byte	00h,00h
; AGC
	word	22		; BSMX_TOKEN_AGC
	word	2		; Range
        byte	2,16,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    043h,01h
        byte	00h,00h

subTab1745	label	word
	word	BSMX_TOKEN_OUT_MX_SW
        word	6 ,28,27,26,25, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_IN_MX_SW_L
        word	6 ,28,27,26,25,24,23, 0	; subTokens

	word	BSMX_TOKEN_IN_MX_SW_R
        word	6 ,28,27,26,25,24,23, 0	; subTokens

	word	BSMX_TOKEN_IN_GAIN_L
        word	29,30,31,32, 0, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_IN_GAIN_R
        word	29,30,31,32, 0, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_OUT_GAIN_L
        word	29,30,31,32, 0, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_OUT_GAIN_R
        word	29,30,31,32, 0, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_AGC,		; mainToken
		BSMX_TOKEN_ON,
        	BSMX_TOKEN_OFF,
        	 0, 0, 0, 0, 0, 0	; subTokens LSB..MSB

	word	BSMX_TOKEN_LOWPASS,	; Low-pass
		BSMX_TOKEN_ON,
        	BSMX_TOKEN_OFF,
		 0, 0, 0, 0, 0, 0	; subTokens

        word	0			; End marker

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;		CT 1345
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
valTab1345	label	word
	word	1		; BSMX_TOKEN_MASTER
	word	255		; Range
        byte	1,0,1		; Type,sliderNum,target
	byte	0c0h		; visible,stereo
	byte    022h,0e0h	; Offset, bit mask 1
        byte	022h,00eh	; Offset, bit mask 2
; MIDI (FM)
	word	2		; BSMX_TOKEN_MIDI
	word	255		; Range
        byte	1,1,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    026h,0e0h	; Offset, bit mask 1
        byte	026h,00eh	; Offset, bit mask 2
; VOICE (WAV)
	word	4		; BSMX_TOKEN_VOICE
	word	255
        byte	1,2,1
	byte	0C0h
	byte    004h,0e0h
        byte	004h,00eh
; CD
	word	3		; BSMX_TOKEN_CD
	word	255
        byte	1,3,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    028h,0e0h
        byte	028h,00eh
; LINE
	word	5		; BSMX_TOKEN_LINE
	word	255		; Range
        byte	1,4,1		; Type,sliderNum,target
	byte	0C0h		; visible,stereo
	byte    02eh,0e0h
        byte	02eh,00eh
; Microphone
	word	6		; BSMX_TOKEN_MIC
	word	255		; Range
        byte	1,5,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    0ah,06h
        byte	00h,00h

; Inputfilter
	word	10		; BSMX_TOKEN_IN_FLT
	word	2		; Range
        byte	2,6,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    0ch,020h
        byte	00h,00h
; Low-pass filter
	word	11		; BSMX_TOKEN_LOWPASS
	word	2		; Range
        byte	2,7,3		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    0ch,08h
        byte	00h,00h
; Input Source
	word	12		; BSMX_TOKEN_INP_SRC
	word	4		; Range
        byte	2,8,2		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    0Ch,06h
        byte	00h,00h

	word	0

subTab1345	label	word
	word	BSMX_TOKEN_IN_FLT,	; mainToken
		BSMX_TOKEN_ON,
        	BSMX_TOKEN_OFF,
        	 0, 0, 0, 0, 0, 0	; subTokens LSB..MSB

	word	BSMX_TOKEN_LOWPASS,	; Low-pass
		BSMX_TOKEN_ON,
        	BSMX_TOKEN_OFF,
		 0, 0, 0, 0, 0, 0	; subTokens

	word	BSMX_TOKEN_INP_SRC
        word	0 , 3, 6, 5, 0, 0, 0, 0	; subTokens

        word	0			; End marker

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;		CT 1335
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
valTab1335	label	word
	word	1		; BSMX_TOKEN_MASTER
	word	255		; Range
        byte	1,0,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    02h,0e0h	; Offset, bit mask 1
        byte	0h,00h		; Offset, bit mask 2
; MIDI (FM)
	word	2		; BSMX_TOKEN_MIDI
	word	255		; Range
        byte	1,1,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    06h,0e0h	; Offset, bit mask 1
        byte	0h,00h		; Offset, bit mask 2
; VOICE (WAV)
	word	4		; BSMX_TOKEN_VOICE
	word	255
        byte	1,2,1
	byte	080h
	byte    0ah,060h
        byte	00h,00h
; CD
	word	3		; BSMX_TOKEN_CD
	word	255
        byte	1,3,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    08h,0eh
        byte	0h,0h

subTab1335	label	word
	word	0		; End

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;		Unknown DSP version
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
valTabDum	label	word
	word	1		; BSMX_TOKEN_MASTER
	word	255		; Range
        byte	1,0,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    02h,0h
        byte	0h,0h
; MIDI (FM)
	word	2		; BSMX_TOKEN_MIDI
	word	255		; Range
        byte	1,1,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    02h,0h
        byte	0h,0h
; VOICE (WAV)
	word	4		; BSMX_TOKEN_VOICE
	word	255
        byte	1,2,1
	byte	080h
	byte    02h,0h
        byte	0h,0h
; CD
	word	3		; BSMX_TOKEN_CD
	word	255
        byte	1,3,1		; Type,sliderNum,target
	byte	080h		; visible,stereo
	byte    02h,0h
        byte	0h,0h

subTabDum	label	word
	word	0		; End

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

LoadableCode		ends


