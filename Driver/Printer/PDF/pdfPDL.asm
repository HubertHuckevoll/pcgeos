	; Escape ABI: BX=PState handle, DX:SI=matrix or SI=GString, CX=GSControl.
	; DriverStrategy already locks the PState, but the escape ABI is handle based.
COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintSetPageTransform
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Forward the page matrix.

CALLED BY:	Printer driver interface

PASS:		BX = PState handle; DX:SI = matrix

RETURN:		carry set on error

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Pass the matrix to the PDF library.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintSetPageTransform proc far
	uses	bx, ds
	.enter
		call	MemLock
		mov	ds, ax
		push	bx
		push	ds:[PS_expansionInfo]
		push	dx, si
		call	PDFSETTRANSFORM
		pop	bx
		call	MemUnlock
		tst	ax
		EC <		WARNING_NZ PDF_PAGE_TRANSFORM_FAILED	>
		jz	ok
		stc
		jmp	done
ok:
		clc
done:
	.leave
		ret
PrintSetPageTransform endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintGString
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Translate a page GString.

CALLED BY:	Printer driver interface

PASS:		BX = PState handle; SI = GString; CX = control

RETURN:		AX = translation status; carry clear

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Keep the normal spooler cleanup path.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintGString proc far
	uses	bx, cx, ds
	.enter
		call	MemLock
		mov	ds, ax
		push	bx
		push	ds:[PS_expansionInfo]
		push	si, cx
		call	PDFGSTRING
		pop	bx
		call	MemUnlock
		EC <		cmp	ax, GSRT_FAULT			>
		EC <		WARNING_Z PDF_GSTRING_FAILED		>
	; The spooler follows GSRT_FAULT's normal conversion error path.
	; Keep carry clear so it also destroys the loaded GString handle.
		clc
	.leave
		ret
PrintGString endp
