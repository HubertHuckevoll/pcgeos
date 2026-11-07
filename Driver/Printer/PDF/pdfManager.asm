COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Printer Driver
FILE:       pdfManager.asm

AUTHOR:     Codex/MeyerK, Nov 2026

ROUTINES:
	DriverStrategy       - Standard printer driver dispatch
	PrintInit            - Initialize the printer driver
	PrintSwath           - Reject unsupported raster calls

REVISION HISTORY:
	Name            Date        Description
	----            ----        -----------
	Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
	Set up the PrintCom entry points and PDL escape dispatch.
	Include the PDF printer's job, page and device information modules.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

	; Native PDF PDL printer. The spooler owns the output stream; pdf.lib owns
	; the per-job translation context in PS_expansionInfo. No shared job globals.
include printcomInclude.def
UseLib pdf.def
include printcomConstant.def
include printcomMacro.def
DR_PRINT_LAST_RESIDENT = DR_PRINT_HOME_CURSOR

if ERROR_CHECK
PDF_CREATE_FAILED enum Warnings
PDF_FINISH_FAILED enum Warnings
PDF_START_PAGE_FAILED enum Warnings
PDF_END_PAGE_FAILED enum Warnings
PDF_PAGE_TRANSFORM_FAILED enum Warnings
PDF_GSTRING_FAILED enum Warnings
endif

Entry segment resource
Entry ends
CommonCode segment resource
CommonCode ends

	;
	; Standard PrintCom driver entry and device information
	;
idata segment
DriverTable DriverExtendedInfoStruct <<DriverStrategy, mask DA_HAS_EXTENDED_INFO, DRIVER_TYPE_PRINTER>, handle DriverInfo>
public DriverTable
idata ends

Entry segment resource
include printcomEntry.asm
include printcomTables.asm
include printcomInfo.asm
PrintInit proc near
PrintExit label near
PrintInitStream label near
		clc
		ret
PrintInit endp

	;
	; Native PDF escapes: page transform, GString and output format
	;
escCodes word DR_PRINT_ESC_SET_PAGE_TRANSFORM, DR_PRINT_ESC_PRINT_GSTRING, DR_PRINT_ESC_GET_OUTPUT_FORMAT
NUM_ESC_ENTRIES equ ($ - escCodes)/2
escHanJumpTable hptr handle CommonCode, handle CommonCode, handle CommonCode
escOffJumpTable nptr offset PrintSetPageTransform, offset PrintGString, offset PrintGetOutputFormat
Entry ends

CommonCode segment resource
	;
	; Shared PrintCom support stays separate from the PDF-specific handlers
	;
include printcomNoStyles.asm
include Color/colorGetFormat.asm
include Color/colorSetNone.asm
include pdfJob.asm
include pdfPDL.asm
include pdfInfo.asm

	; PDL jobs enter only via the two escapes. Reject raster/text/raw calls.
PrintSwath proc far
PrintText label far
PrintRaw label far
PrintStyleRun label far
PrintSetFont label far
PrintSetCursor label far
PrintGetCursor label far
PrintGetLineSpacing label far
PrintSetLineSpacing label far
		stc
		ret
PrintSwath endp
CommonCode ends
include pdfDriverInfo.asm
end
