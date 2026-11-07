COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfStream.asm

AUTHOR:     Codex/MeyerK, Nov 2026

ROUTINES:
	PDFSTREAMWRITE       - Write bytes through the spooler stream
	PDFTEXTWIDTHFIXED    - Fetch fractional GEOS text width
	PDFGETDASH          - Return effective line dash factors
	PDFGENCHAR          - Generate a native glyph outline
	PDFSCRIPTY          - Fetch native script baseline displacement

REVISION HISTORY:
	Name            Date        Description
	----            ----        -----------
	Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
	Bridge Pascal-style calls between Watcom C and GEOS assembly.
	Access the spooler's stream strategy and graphics state.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

	; Pascal adapter to the spooler's stream strategy (including its file driver).
include geos.def
include resource.def
include heap.def
include graphics.def
include Internal/gstate.def
include Internal/fontDr.def
include ec.def
if ERROR_CHECK
PDF_TRANSLATION_FAILED enum Warnings, 5044h
PDF_TRANSLATION_STARTED enum Warnings, 5045h
PDF_TRANSLATION_FINISHED enum Warnings, 5046h
PDF_TEXT_PATH_REQUIRED enum Warnings, 5047h
PDF_PATH_TRANSLATION_FAILED enum Warnings, 5048h
PDF_DRAW_MODE_UNSUPPORTED enum Warnings, 5049h
endif
UseDriver Internal/streamDr.def

SetGeosConvention
global PDFSTREAMWRITE:far
global PDFTEXTWIDTHFIXED:far
global PDFGETDASH:far
global PDFGENCHAR:far
global PDFSCRIPTY:far
PdfCode segment public 'CODE'

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PDFSTREAMWRITE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Write bytes to the spooler stream.

CALLED BY:	Printer driver interface

PASS:		token, strategy, buffer, count on stack

RETURN:		AX = zero on success

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Check for stream error and short writes.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PDFSTREAMWRITE proc far token:word, strategy:fptr.far, buffer:fptr.byte, count:word
	uses	bx, cx, dx, si, di, ds, es
	.enter
		mov	bx, token
		mov	cx, count
		lds	si, buffer
		mov	ax, STREAM_BLOCK
		mov	di, DR_STREAM_WRITE
	; The stream driver can also report a short write without carry.
		call	strategy
		jc	failed
		cmp	cx, count
		jne	failed
		clr	ax
		jmp	done
failed:
		mov	ax, 1
done:
	.leave
		ret
PDFSTREAMWRITE endp

	;
	; C bridge to the native fractional string-width API. Return DX:AX as 16.16.
	;
COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PDFTEXTWIDTHFIXED
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Read native text width.

CALLED BY:	Printer driver interface

PASS:		gstate, text, count on stack

RETURN:		DX:AX = fractional width

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Use kernel text metrics.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PDFTEXTWIDTHFIXED proc far gstate:hptr, text:fptr.byte, count:word
	uses	bx, cx, si, di, ds
	.enter
		mov	di, gstate
		lds	si, text
		mov	cx, count
		call	GrTextWidthWBFixed
		clr	al			; DX:AH is the native 16.8 result
	.leave
		ret
PDFTEXTWIDTHFIXED endp

	;
	; GrGetLineStyle returns only the enum. Copy the effective native byte dash
	; factors so saved states, built-in patterns and custom patterns agree.
	;
COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PDFGETDASH
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Read native dash factors.

CALLED BY:	Printer driver interface

PASS:		gstate, buffer on stack

RETURN:		buffer receives dash data

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Copy factors from the locked graphics state.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PDFGETDASH proc far gstate:hptr, buffer:fptr.byte
	uses	ax, bx, cx, si, di, ds, es
	.enter
		mov	bx, gstate
		call	MemLock
		mov	ds, ax
		mov	si, offset GS_numOfDashPairs
		les	di, buffer
		mov	cx, 2 + MAX_DASH_ARRAY_PAIRS * 2
		rep	movsb			; count, skip, then byte factors
		call	MemUnlock
	.leave
		ret
PDFGETDASH endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                PDFSCRIPTY
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:       Read the native script baseline displacement.
PASS:           gstate on stack
RETURN:         DX:AX = signed 16.16 displacement from the normal baseline
DESTROYED:      See saved registers

STRATEGY:       Match Nimbus/Bitstream AddStyleTransforms and TrueType
                CalcTransform. FontBuf metrics stay in document coordinates.
                TrueType truncates scriptY. Nimbus rounds ties upward;
                Bitstream rounds ties away from zero.
                Both script bits together select subscript, as in the drivers.

REVISION HISTORY:
        Codex/MeyerK    11/07/26    Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
PDFSCRIPTY proc far gstate:hptr
	uses	bx, cx, si, di, ds, es
	.enter
		mov	bx, gstate
		call	MemLock
		mov	ds, ax
		clr	ax
		mov	al, ds:[GS_fontAttr].FCA_textStyle
		mov	si, ax
		call	FontDrLockFont
		mov	es, ax
		push	bx			; retain the returned font handle
		clr	cx
		movwbf	dxch, es:FB_height
		addwbf	dxch, es:FB_heightAdjust
		mov	ax, 1a00h		; native subscript fraction
		test	si, mask TS_SUBSCRIPT
		jnz	multiply
		mov	ax, 6000h		; native superscript fraction
multiply:
		clr	bx
		call	GrMulWWFixed
		test	si, mask TS_SUBSCRIPT
		jnz	roundOffset
		subwbf	dxch, es:FB_baselinePos
		subwbf	dxch, es:FB_baseAdjust
roundOffset:
		cmp	es:FB_maker, FM_TRUETYPE
		je	offsetReady		; TrueType uses arithmetic truncation
		cmp	es:FB_maker, FM_BITSTREAM
		je	signedRound
		rnduwbf	dxch			; Nimbus rounds negative ties upward
		jmp	offsetReady
signedRound:
		rndwbf	dxch
offsetReady:
		pop	bx
		call	FontDrUnlockFont
		mov	bx, gstate
		call	MemUnlock
		clr	ax			; native scriptY is an integer
	.leave
		ret
PDFSCRIPTY endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PDFGENCHAR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Append a native glyph outline to a recording GState.

PASS:		gstate = recording GState; character = GEOS character
RETURN:		AX = zero on success, PDF_UNSUPPORTED (4) for a non-outline font
DESTROYED:	See saved registers

STRATEGY:	Use the actual FontInfo maker, even when the current font buffer
		is a cached bitmap. PostScript mode leaves baseline and Y flip
		to the caller. No saved state is needed for this temporary stream.

REVISION HISTORY:
	Codex/MeyerK	11/07/26	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
PDFGENCHAR proc far gstate:hptr, character:word
	uses	bx, cx, dx, si, di, ds, es
	.enter
		mov	bx, gstate
		call	MemLock
		mov	ds, ax
		mov	cx, ds:[GS_fontAttr].FCA_fontID
		call	MemUnlock
		call	FontDrLockInfoBlock
		call	FontDrFindFontInfo
		jnc	noFont
		test	ds:[di].FI_family, mask FA_OUTLINE
		jz	noFont
		mov	ax, ds:[di].FI_maker
		push	ax
		call	FontDrUnlockInfoBlock
		pop	ax
		mov	bx, gstate
		mov	dx, character
		mov	cx, mask FGPF_POSTSCRIPT
		mov	di, DR_FONT_GEN_PATH
		call	GrCallFontDriverID
	; DR_FONT_GEN_PATH has no status result, as in the EPS exporter.
		clr	ax
		jmp	done
noFont:
		call	FontDrUnlockInfoBlock
		mov	ax, 4
done:
	.leave
		ret
PDFGENCHAR endp

PdfCode ends
end
