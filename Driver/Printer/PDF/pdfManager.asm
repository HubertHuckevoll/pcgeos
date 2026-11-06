; Native PDF PDL printer. The spooler owns the output stream; pdf.lib owns
; the per-job translation context in PS_expansionInfo. No shared job globals.
include printcomInclude.def
UseLib pdf.def
include printcomConstant.def
include printcomMacro.def
DR_PRINT_LAST_RESIDENT = DR_PRINT_HOME_CURSOR

Entry segment resource
Entry ends
CommonCode segment resource
CommonCode ends

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
escCodes word DR_PRINT_ESC_SET_PAGE_TRANSFORM, DR_PRINT_ESC_PRINT_GSTRING
NUM_ESC_ENTRIES equ ($ - escCodes)/2
escHanJumpTable hptr handle CommonCode, handle CommonCode
escOffJumpTable nptr offset PrintSetPageTransform, offset PrintGString
Entry ends

CommonCode segment resource
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
