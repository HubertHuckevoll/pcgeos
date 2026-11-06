; No device UI, host integration or printer-specific commands.
;
; Identify the bytes written by this driver for the print-to-file dialog.
;
PrintGetOutputFormat proc far
		mov	ax, POF_PDF
		clc
		ret
PrintGetOutputFormat endp

PrintGetMainUI proc far
PrintGetOptionsUI label far
        clr cx, dx
        ret
PrintGetMainUI endp
PrintEvalUI proc far
        mov es:[si].JP_printerData.PUID_paperInput, ASF_TRAY1 shl offset PIO_ASF
        clr es:[si].JP_printerData.PUID_paperOutput
        clc
        ret
PrintEvalUI endp
PrintStuffUI proc far
        clc
        ret
PrintStuffUI endp

PrintGetMargins proc far
        clr ax, si, cx, dx
        ret
PrintGetMargins endp
PrintGetPrintArea proc far
        uses ds
        .enter
        mov ds, bp
        mov cx, ds:[PS_customWidth]
        mov dx, ds:[PS_customHeight]
        clr ax, si
        .leave
        ret
PrintGetPrintArea endp
PrintGetPaperPath proc far
        uses ds
        .enter
        mov ds, bp
        mov al, ds:[PS_paperInput]
        mov ah, ds:[PS_paperOutput]
        clc
        .leave
        ret
PrintGetPaperPath endp
PrintSetPaperPath proc far
        uses ds, ax
        .enter
        mov ds, bp
        mov ds:[PS_paperInput], ASF_TRAY1 shl offset PIO_ASF
        clr ax
        mov ds:[PS_paperOutput], al
        mov ds:[PS_currentMargins].PM_left, ax
        mov ds:[PS_currentMargins].PM_top, ax
        mov ds:[PS_currentMargins].PM_right, ax
        mov ds:[PS_currentMargins].PM_bottom, ax
        clc
        .leave
        ret
PrintSetPaperPath endp
