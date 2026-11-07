	; Regular functions receive the locked PState segment in BP.
COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintStartJob
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Initialize the PDF print job.

CALLED BY:	Printer driver interface

PASS:		BP = locked PState

RETURN:		carry set on error

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Allocate the PDF context.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintStartJob proc far
	uses	ax, bx, cx, dx, si, di, ds, es
	.enter
		mov	ds, bp
		clr	ds:[PS_expansionInfo]
	; Only a normal spooler file stream is advertised by this device.
		cmp	ds:[PS_jobParams].JP_portInfo.PPI_type, PPT_FILE
		jne	failed
		mov	bx, ds:[PS_deviceInfo]
		call	MemLock
		mov	es, ax
		mov	al, es:[PI_type]
		mov	ah, es:[PI_smarts]
		mov	{word}ds:[PS_printerType], ax
		call	MemUnlock
		mov	al, ds:[PS_jobParams].JP_printerData.PUID_paperInput
		mov	ah, ds:[PS_jobParams].JP_printerData.PUID_paperOutput
		call	PrintSetPaperPath
		push	ds:[PS_streamToken]
		pushdw	ds:[PS_streamStrategy]
		push	ds:[PS_customWidth]
		push	ds:[PS_customHeight]
		call	PDFCREATE
		tst	ax
		EC <		WARNING_Z PDF_CREATE_FAILED	>
		jz	failed
		mov	ds:[PS_expansionInfo], ax
		clc
		jmp	done
failed:
		stc
done:
	.leave
		ret
PrintStartJob endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintEndJob
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Finish the PDF print job.

CALLED BY:	Printer driver interface

PASS:		BP = locked PState

RETURN:		carry set on error

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Finalize and free the PDF context.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintEndJob proc far
	uses	ax, ds
	.enter
		mov	ds, bp
		push	ds:[PS_expansionInfo]
		clr	ds:[PS_expansionInfo]
		call	PDFDESTROY
		tst	ax
		EC <		WARNING_NZ PDF_FINISH_FAILED	>
		jz	ok
		stc
		jmp	done
ok:
		clc
done:
	.leave
		ret
PrintEndJob endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintStartPage
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Start a PDF page.

CALLED BY:	Printer driver interface

PASS:		BP = locked PState

RETURN:		carry set on error

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Begin one output page.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintStartPage proc far
	uses	ax, ds
	.enter
		mov	ds, bp
		push	ds:[PS_expansionInfo]
		call	PDFSTARTPAGE
		tst	ax
		EC <		WARNING_NZ PDF_START_PAGE_FAILED	>
		jz	ok
		stc
		jmp	done
ok:
		clc
done:
	.leave
		ret
PrintStartPage endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintEndPage
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Finish a PDF page.

CALLED BY:	Printer driver interface

PASS:		BP = locked PState

RETURN:		carry set on error

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Close the current output page.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintEndPage proc far
	uses	ax, ds
	.enter
		mov	ds, bp
		push	ds:[PS_expansionInfo]
		call	PDFENDPAGE
		tst	ax
		EC <		WARNING_NZ PDF_END_PAGE_FAILED	>
		jz	ok
		stc
		jmp	done
ok:
		clc
done:
	.leave
		ret
PrintEndPage endp
