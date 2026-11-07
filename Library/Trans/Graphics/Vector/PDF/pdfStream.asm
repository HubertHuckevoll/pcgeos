; Pascal adapter to the spooler's stream strategy (including its file driver).
include geos.def
include resource.def
include heap.def
include graphics.def
include Internal/gstate.def
include ec.def
if ERROR_CHECK
PDF_TRANSLATION_FAILED enum Warnings, 5044h
endif
UseDriver Internal/streamDr.def

SetGeosConvention
global PDFSTREAMWRITE:far
global PDFTEXTWIDTHFIXED:far
global PDFGETDASH:far
PdfCode segment public 'CODE'
PDFSTREAMWRITE proc far token:word, strategy:fptr.far, buffer:fptr.byte, count:word
        uses bx, cx, dx, si, di, ds, es
        .enter
        mov bx, token
        mov cx, count
        lds si, buffer
        mov ax, STREAM_BLOCK
        mov di, DR_STREAM_WRITE
        call strategy
        jc failed
        cmp cx, count
        jne failed
        clr ax
        jmp done
failed:
        mov ax, 1
done:
        .leave
        ret
PDFSTREAMWRITE endp
;
; C bridge to the native fractional string-width API. Return DX:AX as 16.16.
;
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
