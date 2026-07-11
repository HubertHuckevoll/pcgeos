COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	PC/GEOS Markdown export entry point

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

ExportCode segment resource

TransExport proc far uses cx, dx, si, di, ds, es
		.enter
		push	ds
		push	si
		call	MDEXPORT
		.leave
		ret
TransExport endp

ExportCode ends
