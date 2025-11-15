COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	Copyright (c) GeoWorks 1992 -- All Rights Reserved

PROJECT:	PC GEOS
MODULE:
FILE:		msnetUtils.asm

AUTHOR:		Adam de Boor, Mar 29, 1992

ROUTINES:
	Name			Description
	----			-----------


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Adam	3/29/92		Initial revision


DESCRIPTION:
	NetWare-specific utilities


	$Id: msnetUtils.asm,v 1.1 97/04/10 11:55:26 newdeal Exp $

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

Resident	segment	resource


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmCallPrimary
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Call the primary FSD to do something for us.

CALLED BY:	INTERNAL
PASS:		di	= DOSPrimaryFSFunction to call
		etc.
RETURN:		whatever
DESTROYED:	bp before the call is made

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmCPFrame	struct
    NetmCPF_ds	sptr
    NetmCPF_vector fptr.far
NetmCPFrame	ends

NetmCallPrimary	proc	far
		.enter
		push	bx, ax, ds
		mov	bp, sp
		segmov	ds, dgroup, ax
		mov	bx, ds:[msnetPrimaryStrat].segment
		mov	ax, ds:[msnetPrimaryStrat].offset
		xchg	ax, ss:[bp].NetmCPF_vector.offset
		xchg	bx, ss:[bp].NetmCPF_vector.segment
		mov	ds, ss:[bp].NetmCPF_ds
		call	ss:[bp].NetmCPF_vector
		mov	bp, sp
		lea	sp, ss:[bp+size NetmCPFrame]
		.leave
		ret
NetmCallPrimary	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		LoadVarSegDS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Load dgroup into DS

CALLED BY:	INTERNAL
PASS:		nothing
RETURN:		ds	= dgroup
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	11/18/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
dgroupSeg	sptr	dgroup
LoadVarSegDS	proc	near
		.enter
		mov	ds, cs:[dgroupSeg]
		.leave
		ret
LoadVarSegDS	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmPassOnInterrupt
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Pass on an interrupt we've decided not to handle

CALLED BY:	(EXTERNAL) NetmIdleHook, NetmCriticalError
PASS:		ds:bx	= place where old handler is stored
		on stack (pushed in this order): bx, ax, ds
RETURN:		never
DESTROYED:

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/10/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
DPOIStack       struct
    DPOIS_bp            word
    DPOIS_ax            word
    DPOIS_bx            word
    DPOIS_retAddr       fptr.far
    DPOIS_flags         word
DPOIStack       ends

NetmPassOnInterrupt proc	far jmp
                on_stack        ds ax bx retf
        ;
        ; Fetch the old vector into ax and bx
        ;
        	mov     ax, ds:[bx].offset
        	mov     bx, ds:[bx].segment
        	pop     ds

                on_stack        ax bx retf
        ;
        ; Now replace the saved ax and bx with the old vector, so we can
        ; just perform a far return to get to the old handler.
        ;
        	push    bp
                on_stack        bp ax bx retf
        	mov     bp, sp
        	xchg    ax, ss:[bp].DPOIS_ax
        	xchg    bx, ss:[bp].DPOIS_bx
        	pop     bp
                on_stack        retf
        	ret
NetmPassOnInterrupt endp


Resident	ends
