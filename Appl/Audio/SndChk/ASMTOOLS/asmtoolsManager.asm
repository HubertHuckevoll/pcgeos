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

;--------------------------------------------------------------------------
; SC_Delay
;--------------------------------------------------------------------------
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

;--------------------------------------------------------------------------
; SC_In
;--------------------------------------------------------------------------
SC_ASMIN proc far ioAddr:word
        uses    dx
        .enter

        mov     dx, ioAddr
        in      al, dx

        .leave
        ret
SC_ASMIN endp

;--------------------------------------------------------------------------
; SC_Out
;--------------------------------------------------------------------------
SC_ASMOUT proc far ioAddr:word, value:byte
        uses    dx
        .enter

        mov     dx, ioAddr
        mov     al, value
        out     dx, al

        .leave
        ret
SC_ASMOUT endp

;--------------------------------------------------------------------------
; SC_Reset
;--------------------------------------------------------------------------
SC_ASMRESET proc far ioAddr:word
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
SC_ASMRESET endp

ASMTOOLS_TEXT ends

end
