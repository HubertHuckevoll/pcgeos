COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        SoundCheck low-level hardware helpers.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include geos.def
include resource.def

SB_IO_RESET      equ     06h
SB_IO_STATUS     equ     0Eh
SB_IO_READ       equ     0Ah

global  SCASMDELAY:far
global  SCASMIN:far
global  SCASMOUT:far
global  SCASMRESET:far

.ioenable

SetGeosConvention

ASMTOOLS_TEXT segment resource

;--------------------------------------------------------------------------
; SC_Delay
;--------------------------------------------------------------------------
SCASMDELAY proc far ioAddr:word, delayCount:word
        uses    dx, cx
        .enter

        mov     dx, ioAddr
        mov     cx, delayCount

DelayLoop:
        in      al, dx
        loop    DelayLoop

        .leave
        ret
SCASMDELAY endp

;--------------------------------------------------------------------------
; SC_In
;--------------------------------------------------------------------------
SCASMIN proc far ioAddr:word
        uses    dx
        .enter

        mov     dx, ioAddr
        in      al, dx

        .leave
        ret
SCASMIN endp

;--------------------------------------------------------------------------
; SC_Out
;--------------------------------------------------------------------------
SCASMOUT proc far ioAddr:word, value:byte
        uses    dx
        .enter

        mov     dx, ioAddr
        mov     al, value
        out     dx, al

        .leave
        ret
SCASMOUT endp

;--------------------------------------------------------------------------
; SC_Reset
;--------------------------------------------------------------------------
SCASMRESET proc far ioAddr:word
        uses    ax, dx, cx
        .enter

        mov     dx, ioAddr
        add     dl, SB_IO_RESET
        mov     al, 1
        out     dx, al
        sub     al, al

Delay:
        dec     al
        jnz     Delay
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
SCASMRESET endp

ASMTOOLS_TEXT ends

end
