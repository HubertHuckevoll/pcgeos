; Pascal adapter to the spooler's stream strategy (including its file driver).
include geos.def
include resource.def
include graphics.def
include ec.def
if ERROR_CHECK
PDF_TRANSLATION_FAILED enum Warnings, 5044h
endif
UseDriver Internal/streamDr.def

SetGeosConvention
global PDFSTREAMWRITE:far
global PDFTEXTWIDTHFIXED:far
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
PdfCode ends
end
