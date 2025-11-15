COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	Copyright (c) GeoWorks 1992 -- All Rights Reserved

PROJECT:	PC GEOS
MODULE:
FILE:		msnetEntry.asm

AUTHOR:		Adam de Boor, Mar 29, 1992

ROUTINES:
	Name			Description
	----			-----------


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Adam	3/29/92		Initial revision


DESCRIPTION:
	Strategy routines and function tables for the NetWare IFS driver.


	$Id: msnetEntry.asm,v 1.1 97/04/10 11:55:24 newdeal Exp $

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

idata	segment



DriverTable	FSDriverInfoStruct <
	<			; FSDIS_common
	    <NetmStrategy>,		; DIS_strategy, all else default.
	    DriverExtendedInfo
	>,
	FSD_FLAGS,
	NetmSecondaryStrategy,	; FDIS_altStrategy
	<
	    DOS_SECONDARY_FS_PROTO_MAJOR,
	    DOS_SECONDARY_FS_PROTO_MINOR
	>			; FDIS_altProto
>
public	DriverTable		; looked at by Glue...

idata	ends

Resident	segment	resource

DefFSFunction	macro	routine, constant
.assert ($-fsFunctions) eq constant*2, <Routine for constant in the wrong slot>
.assert (type routine eq far)
		fptr.far	routine
		endm

fsFunctions	label	fptr.far
DefFSFunction NetmInit,		DR_INIT
DefFSFunction NetmExit,		DR_EXIT
DefFSFunction NetmDoNothing,		DR_SUSPEND
DefFSFunction NetmDoNothing,		DR_UNSUSPEND
DefFSFunction NetmDoNothing,		DRE_TEST_DEVICE
DefFSFunction NetmDoNothing,		DRE_SET_DEVICE
DefFSFunction NetmDiskID,		DR_FS_DISK_ID
DefFSFunction NetmHandOff,		DR_FS_DISK_INIT
DefFSFunction NetmDoNothing,		DR_FS_DISK_LOCK
DefFSFunction NetmDoNothing,		DR_FS_DISK_UNLOCK
DefFSFunction NetmError,		DR_FS_DISK_FORMAT
DefFSFunction NetmHandOff,		DR_FS_DISK_FIND_FREE
DefFSFunction NetmHandOff,		DR_FS_DISK_INFO
DefFSFunction NetmDiskRename,		DR_FS_DISK_RENAME
DefFSFunction NetmError,		DR_FS_DISK_COPY
DefFSFunction NetmDiskSave,		DR_FS_DISK_SAVE
DefFSFunction NetmDiskRestore,		DR_FS_DISK_RESTORE
DefFSFunction NetmCheckNetPath,	DR_FS_CHECK_NET_PATH
DefFSFunction NetmHandOff,		DR_FS_CUR_PATH_SET
DefFSFunction NetmHandOff,		DR_FS_CUR_PATH_GET_ID
DefFSFunction NetmHandOff,		DR_FS_CUR_PATH_DELETE
DefFSFunction NetmHandOff,		DR_FS_CUR_PATH_COPY
DefFSFunction NetmHandOff,		DR_FS_HANDLE_OP
DefFSFunction NetmHandOff,		DR_FS_ALLOC_OP
DefFSFunction NetmHandOff,		DR_FS_PATH_OP
DefFSFunction NetmCompareFiles,	DR_FS_COMPARE_FILES
DefFSFunction NetmHandOff,		DR_FS_FILE_ENUM
DefFSFunction NetmDoNothing,		DR_FS_DRIVE_LOCK
DefFSFunction NetmDoNothing,		DR_FS_DRIVE_UNLOCK
CheckHack <($-fsFunctions)/2 eq FSFunction>

DefSFSFunction	macro	routine, constant
.assert ($-dosSecondaryFunctions) eq constant*2, <Routine for constant in the wrong slot>
.assert (type routine eq far)
		fptr.far	routine
		endm

dosSecondaryFunctions	label	fptr.far
DefSFSFunction	NetmGetExtAttribute,	DR_DSFS_GET_EXT_ATTRIBUTE
DefSFSFunction	NetmSetExtAttribute,	DR_DSFS_SET_EXT_ATTRIBUTE
DefSFSFunction	NetmDoNothing,		DR_DSFS_GET_WRITABLE
CheckHack <($-dosSecondaryFunctions)/2 eq DOSSecondaryFSFunction>

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmEntryCallFunction
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Call the function whose fptr is pointed to by cs:di, dealing
		with movable/fixed state of the routine.

CALLED BY:	NetmStrategy, NetmSecondaryStrategy
PASS:		cs:di	= fptr.fptr.far
RETURN:		whatever
DESTROYED:	bp destroyed by this function before target function called

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmEntryCallFunction proc ecnear
		.enter
		push	ss:[TPD_callVector].offset, ss:[TPD_dataAX], ss:[TPD_dataBX]
		pushdw	cs:[di]
		call	PROCCALLFIXEDORMOVABLE_PASCAL
		pop	ss:[TPD_callVector].offset, ss:[TPD_dataAX], ss:[TPD_dataBX]
		.leave
		ret
NetmEntryCallFunction endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmStrategy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Main entry point for this here driver.

CALLED BY:	kernel
PASS:		di	= FSFunction to perform.
RETURN:		?
DESTROYED:	?

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmStrategy	proc	far
EC <		cmp	di, FSFunction					>
EC <		ERROR_AE	INVALID_FS_FUNCTION			>
EC <		test	di, 1						>
EC <		ERROR_NZ	INVALID_FS_FUNCTION			>
		shl	di
		add	di, offset fsFunctions
		GOTO_ECN	NetmEntryCallFunction
NetmStrategy	endp



COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmSecondaryStrategy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Grudgingly perform some menial task for the primary driver

CALLED BY:	Primary IFS driver
PASS:		di	= DOSSecondaryFSFunction
RETURN:		?
DESTROYED:	?

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmSecondaryStrategy proc	far
EC <		cmp	di, DOSSecondaryFSFunction			>
EC <		ERROR_AE	INVALID_SECONDARY_FUNCTION		>
EC <		test	di, 1						>
EC <		ERROR_NZ	INVALID_SECONDARY_FUNCTION		>
		shl	di
		add	di, offset dosSecondaryFunctions
		GOTO_ECN	NetmEntryCallFunction
NetmSecondaryStrategy endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmError
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Handler for a function that should never be called.

CALLED BY:	DR_FS_DISK_FORMAT, DR_FS_DISK_COPY
PASS:		nothing
RETURN:		carry set (NEC version) & ax = ERROR_UNSUPPORTED_FUNCTION
		death (EC version)
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmError		proc	far
EC <		ERROR	GASP_CHOKE_WHEEZE				>
NEC <		mov	ax, ERROR_UNSUPPORTED_FUNCTION			>
NEC <		stc							>
NEC <		ret							>
NetmError		endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmDoNothing
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Just what the name implies

CALLED BY:	DRE_TEST_DEVICE, DRE_SET_DEVICE, DR_FS_DRIVE_LOCK,
      		DR_FS_DRIVE_UNLOCK, DR_FS_DISK_LOCK, DR_FS_DISK_UNLOCK,
		DR_SUSPEND, DR_UNSUSPEND
PASS:		nothing
RETURN:		carry clear
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmDoNothing	proc	far
		.enter
		clc
		.leave
		ret
NetmDoNothing	endp



COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmHandOff
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Hand off a function to the primary IFS driver

CALLED BY:	DR_FS_DISK_FIND_FREE, DR_FS_DISK_INFO, DR_FS_CUR_PATH_SET,
       		DR_FS_CUR_PATH_DELETE, DR_FS_HANDLE_OP, DR_FS_ALLOC_OP,
		DR_FS_PATH_OP, DR_FS_FILE_ENUM
PASS:		cs:di	= fptr.fptr.self
RETURN:		?
DESTROYED:	?

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmHandOff	proc	far
	;
	; Convert DI back into its FSFunction enum
	;
		sub	di, offset fsFunctions
		shr	di
	;
	; Call the primary to perform the function.
	;
		GOTO	NetmCallPrimary
NetmHandOff	endp



COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		NetmCompareFiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	compare two open files (given their SFNs) to see if they
		refer to the same disk file. Note: one or both SFN may actually
		be invalid, owing to the lack of synchronization during
		the closing of a file. The driver must check for this and
		return that the two are unequal.

CALLED BY:	DR_FS_COMPARE_FILES
PASS:		al	= SFN of first file
		cl	= SFN of second file
RETURN:		ah	= flags byte (for sahf) that will allow je if the
			  two files refer to the same disk file (carry will be
			  clear after sahf).
DESTROYED:	al, di

PSEUDO CODE/STRATEGY:
		Can't do this for LANtastic

KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/29/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
NetmCompareFiles	proc	far
		.enter
		or	al, 1	; flag not-equal
		lahf
		.leave
		ret
NetmCompareFiles	endp

Resident	ends
