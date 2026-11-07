COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:	PC/GEOS
MODULE:		Native PDF printer
FILE:		pdfInfo.asm
AUTHOR:		Codex/MeyerK

ROUTINES:
	PrintGetOutputFormat - advertise native PDF
	PrintGetPrintArea   - return the selected paper size
	PrintSetPaperPath   - initialize paper options

DESCRIPTION:
	Expose the PDF file format and file-only paper capabilities.
	The print spooler owns the destination stream and PState.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

	; No device UI, host integration or printer-specific commands.
	;
	; Identify the bytes written by this driver for the print-to-file dialog.
	;
PrintGetOutputFormat proc far
		mov	ax, POF_PDF
		clc
		ret
PrintGetOutputFormat endp

	;
	; This file-only driver has no custom UI object trees.
	;
PrintGetMainUI proc far
PrintGetOptionsUI label far
		clr	cx, dx
		ret
PrintGetMainUI endp

PrintEvalUI proc far
		mov	es:[si].JP_printerData.PUID_paperInput, ASF_TRAY1 shl offset PIO_ASF
		clr	es:[si].JP_printerData.PUID_paperOutput
		clc
		ret
PrintEvalUI endp

PrintStuffUI proc far
		clc
		ret
PrintStuffUI endp

PrintGetMargins proc far
		clr	ax, si, cx, dx
		ret
PrintGetMargins endp
	;
	; PState stores the physical page size selected by DR_PRINT_SET_MODE.
	;
PrintGetPrintArea proc far
	uses	ds
	.enter
		mov	ds, bp
		mov	cx, ds:[PS_customWidth]
		mov	dx, ds:[PS_customHeight]
		clr	ax, si
	.leave
		ret
PrintGetPrintArea endp

PrintGetPaperPath proc far
	uses	ds
	.enter
		mov	ds, bp
		mov	al, ds:[PS_paperInput]
		mov	ah, ds:[PS_paperOutput]
		clc
	.leave
		ret
PrintGetPaperPath endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		PrintSetPaperPath
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set default paper settings.

CALLED BY:	Printer driver interface

PASS:		BP = locked PState

RETURN:		carry clear

DESTROYED:	See saved registers

PSEUDO CODE/STRATEGY:
		Select the default paper path and clear margins.

KNOWN BUGS/SIDE EFFECTS/IDEAS:
		None documented here.

REVISION HISTORY:
	Name		Date		Description
	----		----		-----------
	Codex/MeyerK	11/07/26	Document interface

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

PrintSetPaperPath proc far
	uses	ds, ax
	.enter
		mov	ds, bp
		mov	ds:[PS_paperInput], ASF_TRAY1 shl offset PIO_ASF
		clr	ax
		mov	ds:[PS_paperOutput], al
		mov	ds:[PS_currentMargins].PM_left, ax
		mov	ds:[PS_currentMargins].PM_top, ax
		mov	ds:[PS_currentMargins].PM_right, ax
		mov	ds:[PS_currentMargins].PM_bottom, ax
		clc
	.leave
		ret
PrintSetPaperPath endp
