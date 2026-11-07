COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfStream.asm

AUTHOR:     Codex/MeyerK, Nov 2026

ROUTINES:
	PDFSTREAMWRITE       - Write bytes through the spooler stream
	PDFTEXTWIDTHFIXED    - Fetch fractional GEOS text width
	PDFGETDASH          - Return effective line dash factors

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
include ec.def
if ERROR_CHECK
PDF_TRANSLATION_FAILED enum Warnings, 5044h
PDF_TRANSLATION_STARTED enum Warnings, 5045h
PDF_TRANSLATION_FINISHED enum Warnings, 5046h
endif
UseDriver Internal/streamDr.def

SetGeosConvention
global PDFSTREAMWRITE:far
global PDFTEXTWIDTHFIXED:far
global PDFGETDASH:far
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

PdfCode ends
end
