COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        SoundCheck low-level hardware helpers.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include resource.def

SB_IO_RESET      equ     06h
SB_IO_STATUS     equ     0Eh
SB_IO_READ       equ     0Ah

global  SC_ASMDELAY:far
global  SC_ASMIN:far
global  SC_ASMOUT:far
global  SC_ASMRESET:far

.ioenable

SetGeosConvention

ASMTOOLS_TEXT segment resource


;***********************************************************************
;*      SC_Delay
;***********************************************************************
;* SYNOPSIS:        Provides a short, uncalibrated delay by repeatedly
;*                  reading from an I/O port.
;* PARAMETERS:      word ioAddr     = I/O address to read from.
;*                  word delayCount = Number of times to loop.
;* SIDE EFFECTS:
;* STRATEGY:
;*
;* REVISION HISTORY:
;*  Name    Date        Description
;*  ----    ----        -----------
;*  martin  2001/2/6    Initial version
;*
;***********************************************************************/
SC_ASMDELAY proc far ioAddr:word, delayCount:word
        uses    dx, cx
        .enter

        mov     dx, ioAddr
        mov     cx, delayCount

DelayLoop:
        in      al, dx
        loop    DelayLoop

        .leave
        ret
SC_ASMDELAY endp

;***********************************************************************
;*      SC_In
;***********************************************************************
;* SYNOPSIS:        Read a low-level Sound Card DMA hardware register.
;* PARAMETERS:      int  addr   = base address for card communication (0x220|0x240|0x388)
;*                  uint reg    = OPL3 register sub-address to call on card
;*                  return      = data to pass to OPL3 card function
;* SIDE EFFECTS:
;* STRATEGY:
;*
;* REVISION HISTORY:
;*  Name    Date        Description
;*  ----    ----        -----------
;*  martin  2001/2/6    Initial version
;*
;***********************************************************************/
SC_ASMIN proc far ioAddr:word
        uses    dx
        .enter

        mov     dx, ioAddr
        in      al, dx

        .leave
        ret
SC_ASMIN endp

;***********************************************************************
;*      SC_Out
;***********************************************************************
;* SYNOPSIS:        Write a low-level Sound Card DMA hardware register.
;* PARAMETERS:      int  addr   = base address for card communication (0x220|0x240|0x388)
;*                  uint reg    = OPL3 register sub-address to call on card
;*                  return      = data to pass to OPL3 card function
;* SIDE EFFECTS:
;* STRATEGY:
;*
;* REVISION HISTORY:
;*  Name    Date        Description
;*  ----    ----        -----------
;*  martin  2001/2/6    Initial version
;*
;***********************************************************************/
SC_ASMOUT proc far ioAddr:word, value:byte
        uses    dx
        .enter

        mov     dx, ioAddr
        mov     al, value
        out     dx, al

        .leave
        ret
SC_ASMOUT endp

;***********************************************************************
;*      SC_Reset
;***********************************************************************
;* SYNOPSIS:        Reset a SoundBlaster Card.
;* PARAMETERS:      int  addr   = base address for card communication (0x220|0x240|0x388)
;* SIDE EFFECTS:
;* STRATEGY:        1) Write "1" to SB_IO_RESET
;*                  2) Delay 100 ms
;*                  3) Write "0" to SB_IO_RESET
;*                  4) Wait for status bit
;*                  5) Read "AAh" from SB_IO_READ
;*
;* REVISION HISTORY:
;*  Name    Date        Description
;*  ----    ----        -----------
;*  martin  2001/2/7    Initial version
;*
;***********************************************************************/
SC_ASMRESET proc far ioAddr:word
        uses    ax, dx, cx
        .enter

        mov     dx, ioAddr
        add     dl, SB_IO_RESET
        mov     al, 1
        out     dx, al

        ; A short delay is required here (>= 3 microseconds). The original
        ; loop was too short on modern CPUs. This nested loop provides a
        ; more substantial, though still uncalibrated, delay.
        mov     cx, 1000  ; Outer loop
Delay:  nop
        loop    Delay

        mov     al, 0
        out     dx, al
        sub     cx, cx

Empty:
        mov     dx, ioAddr
        add     dl, SB_IO_STATUS
        in      al, dx
        or      al, al
        jns     Next
        sub     dl, 4
        in      al, dx
        cmp     al, 0AAh
        je      ResetDone

Next:
        loop    Empty
ResetDone:

        .leave
        ret
SC_ASMRESET endp

ASMTOOLS_TEXT ends

end
