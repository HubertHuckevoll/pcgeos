COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	Copyright (c) GeoWorks 1992 -- All Rights Reserved

PROJECT:	PC/GEOS
MODULE:		album
FILE:		album.asm

AUTHOR:		Gene Anderson, Mar 31, 1992

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Gene	3/31/92		Initial revision

DESCRIPTION:
	code for Album specific screen-saver library

	$Id: album.asm,v 1.1 97/04/04 16:44:07 newdeal Exp $

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include	stdapp.def
include timer.def
include initfile.def
include Internal/heapInt.def

include vm.def
include	fileEnum.def
include backgrnd.def

UseLib	ui.def
UseLib	saver.def

;==============================================================================
;
;		  PUBLIC DECLARATION OF ENTRY POINTS
;
;==============================================================================

global	AlbumStart:far
global	AlbumStop:far
global	AlbumFetchUI:far
global	AlbumFetchHelp:far
global	AlbumSaveState:far
global	AlbumRestoreState:far
global	AlbumSaveOptions:far

global	AlbumSetPause:far
global	AlbumSetDuration:far
global	AlbumSetDrawMode:far
global	AlbumSetColor:far
global	AlbumEraseAndWait:far
global	AlbumDrawAndWait:far

;
; If you add options, update these
;
FIRST_OPTION_ENTRY	equ	enum AlbumSetPause
LAST_OPTION_ENTRY	equ	enum AlbumSetColor

;==============================================================================
;
;		       CONSTANTS AND DATA TYPES
;
;==============================================================================

ALBUM_PAUSE_MIN	equ	1
ALBUM_PAUSE_MAX	equ	60
ALBUM_PAUSE_DEFAULT	equ	10
ALBUM_PAUSE_STEP	equ	1

ALBUM_DURATION_MIN	equ	1
ALBUM_DURATION_MAX	equ	60
ALBUM_DURATION_DEFAULT	equ	10
ALBUM_DURATION_STEP	equ	1

ALBUM_TICKS_PER_SECOND	equ	60

ALBUM_MAX_BACKGROUNDS	equ	255	;must be < 256

ALBUM_ACTION_DRAW	equ	0
ALBUM_ACTION_ERASE	equ	1

ALBUM_TRACE_WARNINGS	equ	0

ALBUM_WARN_STAGE_DRAW_ENTER		enum	Warnings
ALBUM_WARN_STAGE_OPEN_RANDOM		enum	Warnings
ALBUM_WARN_FAIL_OPEN_RANDOM		enum	Warnings
ALBUM_WARN_FAIL_NO_FILES		enum	Warnings
ALBUM_WARN_FAIL_GOTO_BG_DIR		enum	Warnings
ALBUM_WARN_FAIL_MEMLOCK_FILE_LIST	enum	Warnings
ALBUM_WARN_FAIL_VMOPEN_BG		enum	Warnings
ALBUM_WARN_FAIL_DRAW_BG_BITMAP		enum	Warnings
ALBUM_WARN_FAIL_BG_TOKEN_ATTR		enum	Warnings
ALBUM_WARN_FAIL_BG_TOKEN_CHARS		enum	Warnings
ALBUM_WARN_FAIL_BG_PROTOCOL_ATTR	enum	Warnings
ALBUM_WARN_FAIL_BG_PROTOCOL_VERSION	enum	Warnings
ALBUM_WARN_FAIL_NO_VALID_BG_FILES	enum	Warnings

;
; The state we save to our parent's state file on shutdown.
;
AlbumState	struc
    AS_pause		word			;pause between background
    AS_duration		word			;duration of each background
    AS_mode		SaverBitmapMode		;drawing mode
    AS_color		byte			;background color
AlbumState	ends

AlbumApplicationClass	class	SaverApplicationClass

MSG_ALBUM_APP_DRAW				message

    AAI_pause		word	ALBUM_PAUSE_DEFAULT
    AAI_duration	word	ALBUM_DURATION_DEFAULT
    AAI_mode		SaverBitmapMode	SAVER_BITMAP_APPROPRIATE
    AAI_color		byte	-1
    AAI_nextAction	byte	ALBUM_ACTION_DRAW

    AAI_timerHandle	hptr	0
	noreloc	AAI_timerHandle
    AAI_timerID		word

AlbumApplicationClass	endc

AlbumProcessClass	class	GenProcessClass
AlbumProcessClass	endc

;==============================================================================
;
;			      VARIABLES
;
;==============================================================================

include	album.rdef
ForceRef	AlbumApp

udata	segment

;
; Current window and gstate to use for drawing.
;
curWindow	hptr.Window
curGState	hptr.GState
winHeight	word
winWidth	word
curRandom	hptr				;random number generator

;
; Buffer of background bitmap filenames
;
fileBuffer	hptr				;handle of buffer
fileCount	word				;# of files in buffer
filePath	word				;StandardPath for selected BG files

udata	ends

idata	segment

AlbumProcessClass	mask CLASSF_NEVER_SAVED
AlbumApplicationClass

;
; Parameters for the Album, saved and restored to and from our parent's state
; file.
;
astate	AlbumState	<
    ALBUM_PAUSE_DEFAULT*ALBUM_TICKS_PER_SECOND,
    ALBUM_DURATION_DEFAULT*ALBUM_TICKS_PER_SECOND,
    SAVER_BITMAP_APPROPRIATE,
    -1
>

idata	ends

;==============================================================================
;
;		   EXTERNAL WELL-DEFINED INTERFACE
;
;==============================================================================
AlbumCode	segment resource

.warn -private
albumOptionTable	SAOptionTable	<
	albumCategory, length albumOptions
>
albumOptions	SAOptionDesc	<
	albumPauseKey, size AAI_pause, offset AAI_pause
>, <
	albumDurationKey, size AAI_duration, offset AAI_duration
>, <
	albumModeKey, size AAI_mode, offset AAI_mode
>, <
	albumColorKey, size AAI_color, offset AAI_color
>
.warn @private
albumCategory		char	'album', 0
albumPauseKey		char	'pause', 0
albumDurationKey	char	'duration', 0
albumModeKey		char	'mode', 0
albumColorKey		char	'color', 0

albumEnumParams		FileEnumParams <
	mask FESF_GEOS_NON_EXECS,
	FESRT_NAME,
	size FileLongName,
	albumMatchAttrs,
	ALBUM_MAX_BACKGROUNDS
>
albumMatchAttrs		FileExtAttrDesc \
	<FEA_TOKEN, albumToken, size GeodeToken>,
	<FEA_END_OF_LIST>
albumToken		GeodeToken <"BKGD", MANUFACTURER_ID_GEOWORKS>

albumLegacyEnumParams	FileEnumParams <
	mask FESF_GEOS_NON_EXECS,
	FESRT_NAME,
	size FileLongName,
	albumLegacyMatchAttrs,
	ALBUM_MAX_BACKGROUNDS
>
albumLegacyMatchAttrs	FileExtAttrDesc \
	<FEA_TOKEN, albumLegacyToken, size GeodeToken>,
	<FEA_END_OF_LIST>
albumLegacyToken	GeodeToken <"BKGD", 0>

albumAnyEnumParams	FileEnumParams <
	mask FESF_GEOS_NON_EXECS,
	FESRT_NAME,
	size FileLongName,
	albumAnyMatchAttrs,
	ALBUM_MAX_BACKGROUNDS
>
albumAnyMatchAttrs	FileExtAttrDesc \
	<FEA_END_OF_LIST>


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSyncStateFromInstance
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Copy options from object instance into the old dgroup state.

CALLED BY:	AlbumLoadOptions, AlbumAppSetWin
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
RETURN:		nothing
DESTROYED:	nothing

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumSyncStateFromInstance	proc	near
	class	AlbumApplicationClass
	uses	ax, cx, es
	.enter

	mov	es, ss:[TPD_dgroup]

	mov	ax, ALBUM_TICKS_PER_SECOND
	mov	cx, ds:[di].AAI_pause
	mul	cx
	mov	es:[astate].AS_pause, ax

	mov	ax, ALBUM_TICKS_PER_SECOND
	mov	cx, ds:[di].AAI_duration
	mul	cx
	mov	es:[astate].AS_duration, ax

	mov	ax, ds:[di].AAI_mode
	mov	es:[astate].AS_mode, ax
	mov	al, ds:[di].AAI_color
	mov	es:[astate].AS_color, al

	.leave
	ret
AlbumSyncStateFromInstance	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumLoadOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Load options from the ini file.

CALLED BY:	MSG_META_LOAD_OPTIONS
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
RETURN:		nothing
DESTROYED:	ax, cx, dx, bp

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumLoadOptions	method dynamic AlbumApplicationClass, MSG_META_LOAD_OPTIONS
	uses	bx, es
	.enter

	segmov	es, cs
	mov	bx, offset albumOptionTable
	call	SaverApplicationGetOptions

	call	AlbumSyncStateFromInstance

	.leave
	mov	di, offset AlbumApplicationClass
	call	ObjCallSuperNoLock
	ret
AlbumLoadOptions	endm


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumAppSetWin
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Initialize saver state and start drawing.

CALLED BY:	MSG_SAVER_APP_SET_WIN
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
RETURN:		nothing
DESTROYED:	ax, cx, dx, bp

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumAppSetWin	method dynamic AlbumApplicationClass, MSG_SAVER_APP_SET_WIN
	uses	es, bx
	.enter

	mov	di, offset AlbumApplicationClass
	call	ObjCallSuperNoLock

	mov	di, ds:[si]
	add	di, ds:[di].AlbumApplication_offset

	;
	; Create/reset RNG for random color/file selection.
	;
	mov	es, ss:[TPD_dgroup]
	call	TimerGetCount
	mov	dx, bx			; dxax <- seed
	clr	bx			; bx <- allocate new RNG
	call	SaverSeedRandom
	mov	es:[curRandom], bx

	call	AlbumSyncStateFromInstance
	call	AlbumStart

	.leave
	ret
AlbumAppSetWin	endm


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumAppUnsetWin
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Stop drawing and release runtime resources.

CALLED BY:	MSG_SAVER_APP_UNSET_WIN
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
RETURN:		dx	= old window
		bp	= old gstate
DESTROYED:	ax, cx

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumAppUnsetWin	method dynamic AlbumApplicationClass, MSG_SAVER_APP_UNSET_WIN
	call	AlbumStop

	mov	ax, MSG_SAVER_APP_UNSET_WIN
	mov	di, offset AlbumApplicationClass
	call	ObjCallSuperNoLock
	ret
AlbumAppUnsetWin	endm


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumStart
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Start saving the screen in our own little way

CALLED BY:	Generic screen saver library
PASS:		cx	= window handle
		dx	= window height
		si	= window width
		di	= gstate handle
RETURN:		nothing
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:

KNOWN BUGS/SIDE EFFECTS/IDEAS:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	jcw	 3/24/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumStart	proc	far
	class	AlbumApplicationClass
	uses	ax, ds, es
	.enter

	mov	es, ss:[TPD_dgroup]
	;
	; Save the window and gstate from the saver app instance.
	;
	mov	ax, ds:[di].SAI_curWindow
	mov	es:[curWindow], ax
	mov	ax, ds:[di].SAI_curGState
	mov	es:[curGState], ax
	mov	ax, ds:[di].SAI_bounds.R_right
	sub	ax, ds:[di].SAI_bounds.R_left
	mov	es:[winWidth], ax
	mov	ax, ds:[di].SAI_bounds.R_bottom
	sub	ax, ds:[di].SAI_bounds.R_top
	mov	es:[winHeight], ax
	;
	; Build a list of the currently available backgrounds
	;
	push	ds
	segmov	ds, es
	call	BuildFileList
	pop	ds
	jc	done				;branch if error
	;
	; Draw first background
	;
	call	AlbumDrawAndWait		;draw a background and wait
done:

	.leave
	ret
AlbumStart	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		BuildFileList
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Build a list of background bitmap file names
CALLED BY:	AlbumStart()

PASS:		ds - seg addr of dgroup
RETURN:		ds:fileCount - # of files found
		ds:fileBuffer - handle of filename buffer
		carry - set if error
DESTROYED:

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/30/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

BuildFileList	proc	near
	uses	bx, cx
	.enter

	mov	ds:fileCount, 0
	mov	ds:fileBuffer, 0
	mov	ds:filePath, 0
	;
	; Try user-local backgrounds first.
	;
	mov	bx, SP_USER_DATA
	call	GotoBGDirectory
	jc	tryPublic

	call	EnumBGFiles
	jc	tryPublic
	tst	cx
	jnz	gotUserFiles
	tst	bx
	jz	tryUserLegacy
	call	MemFree

tryUserLegacy:
	call	EnumBGFilesLegacy
	jc	tryPublic
	tst	cx
	jnz	gotUserFiles
	tst	bx
	jz	tryUserAny
	call	MemFree

tryUserAny:
	call	EnumBGFilesAny
	jc	tryPublic
	tst	cx
	jnz	gotUserFiles
	tst	bx
	jz	tryPublic
	call	MemFree

tryPublic:
	mov	bx, SP_PUBLIC_DATA
	call	GotoBGDirectory
	jc	done

	call	EnumBGFiles
	jc	done
	tst	cx
	jnz	gotPublicFiles
	tst	bx
	jz	tryPublicLegacy
	call	MemFree

tryPublicLegacy:
	call	EnumBGFilesLegacy
	jc	done
	tst	cx
	jnz	gotPublicFiles
	tst	bx
	jz	tryPublicAny
	call	MemFree

tryPublicAny:
	call	EnumBGFilesAny
	jc	done
	tst	cx
	jnz	gotPublicFiles
	tst	bx
	jz	done
	call	MemFree
	jmp	done

gotUserFiles:
	mov	ds:fileCount, cx		;save count of files
	mov	ds:fileBuffer, bx		;save buffer handle
	mov	ds:filePath, SP_USER_DATA
	jmp	done

gotPublicFiles:
	mov	ds:fileCount, cx		;save count of files
	mov	ds:fileBuffer, bx		;save buffer handle
	mov	ds:filePath, SP_PUBLIC_DATA
done:

	.leave
	ret
BuildFileList	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		EnumBGFiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Enumerate background files in the current directory.

CALLED BY:	BuildFileList
PASS:		nothing
RETURN:		bx	= handle of returned filename buffer
		cx	= number of files in buffer
		carry	= set on error
DESTROYED:	ds, si

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
EnumBGFiles	proc	near
	.enter

	push	ds
	segmov	ds, cs
	mov	si, offset albumEnumParams
	call	FileEnumPtr
	pop	ds

	.leave
	ret
EnumBGFiles	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		EnumBGFilesLegacy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Enumerate background files using legacy BKGD token manuf.

CALLED BY:	BuildFileList
PASS:		nothing
RETURN:		bx	= handle of returned filename buffer
		cx	= number of files in buffer
		carry	= set on error
DESTROYED:	ds, si

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
EnumBGFilesLegacy	proc	near
	.enter

	push	ds
	segmov	ds, cs
	mov	si, offset albumLegacyEnumParams
	call	FileEnumPtr
	pop	ds

	.leave
	ret
EnumBGFilesLegacy	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		EnumBGFilesAny
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Enumerate any non-executable GEOS files in current dir.

CALLED BY:	BuildFileList
PASS:		nothing
RETURN:		bx	= handle of returned filename buffer
		cx	= number of files in buffer
		carry	= set on error
DESTROYED:	ds, si

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
EnumBGFilesAny	proc	near
	.enter

	push	ds
	segmov	ds, cs
	mov	si, offset albumAnyEnumParams
	call	FileEnumPtr
	pop	ds

	.leave
	ret
EnumBGFilesAny	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		GotoBGDirectory
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Go to the background bitmap directory
CALLED BY:	BuildFileList(), OpenRandomBGFile()

PASS:		bx	= StandardPath to use as base path
RETURN:		carry - set if error
DESTROYED:	none

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/30/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

backgroundDir	char BACKGROUND_DIR, 0

GotoBGDirectory	proc	near
	uses	dx, ds
	.enter

	segmov	ds, cs
	mov	dx, offset backgroundDir
	call	FileSetCurrentPath

	.leave
	ret
GotoBGDirectory	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumStop
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Stop drawing a Album

CALLED BY:	Parent library
PASS:		nothing
RETURN:		nothing
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:

KNOWN BUGS/SIDE EFFECTS/IDEAS:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	jcw	 3/24/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumStop	proc	far
	class	AlbumApplicationClass
	uses	ax, bx, es
	.enter

	;
	; Stop any timer we might have going
	;
	clr	bx
	xchg	bx, ds:[di].AAI_timerHandle
	mov	ax, ds:[di].AAI_timerID
	call	TimerStop
	mov	ds:[di].AAI_nextAction, ALBUM_ACTION_DRAW

	mov	es, ss:[TPD_dgroup]
	;
	; And mark the window and gstate as no longer existing.
	;
	clr	ax
	mov	es:[curWindow], ax
	mov	es:[curGState], ax
	mov	es:[winHeight], ax
	mov	es:[winWidth], ax
	mov	es:[fileCount], ax
	mov	es:[filePath], ax
	;
	; Destroy RNG, if created.
	;
	clr	bx
	xchg	bx, es:[curRandom]
	tst	bx
	jz	freeNames
	call	SaverEndRandom
freeNames:
	;
	; Free the buffer of filenames, if it exists
	;
	clr	bx
	xchg	bx, es:[fileBuffer]
	tst	bx				;any buffer?
	jz	done				;branch if no buffer
	call	MemFree
done:

	.leave
	ret
AlbumStop	endp

AlbumCode		ends

AlbumInitExit	segment	resource

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumFetchUI
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Fetch the tree of options that affect how this thing
		performs.

CALLED BY:	Saver library
PASS:		nothing
RETURN:		^lcx:dx	= root of option tree to add
		ax	= first entry point stored in OD's in the tree
		bx	= last entry point stored in OD's in the tree
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:

KNOWN BUGS/SIDE EFFECTS/IDEAS:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	jcw	 3/24/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumFetchUI	proc	far
	.enter

	clr	cx				; no legacy options tree
	clr	dx
	clr	ax
	clr	bx
	.leave
	ret
AlbumFetchUI	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumFetchHelp
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Fetch the help tree

CALLED BY:	Saver library
PASS:		nothing
RETURN:		^lcx:dx	= root of help tree (cx == 0 for none)
DESTROYED:

PSEUDO CODE/STRATEGY:

KNOWN BUGS/SIDE EFFECTS/IDEAS:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	gene	3/20/92		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumFetchHelp	proc	far
	.enter

	clr	cx				; no legacy help tree
	clr	dx

	.leave
	ret
AlbumFetchHelp	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSaveState
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Add our little state block to that saved by the generic
		saver library.

CALLED BY:	SF_SAVE_STATE
PASS:		cx	= handle of block to which to append our state
		dx	= first available byte in the block
RETURN:		nothing
DESTROYED:	ax, bx

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/25/91		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumSaveState	proc	far
		.enter
		; Legacy entry point retained for compatibility with old saver API.
		.leave
		ret
AlbumSaveState	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumRestoreState
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Restore our little state block from that saved by the generic
		saver library.

CALLED BY:	SF_RESTORE_STATE
PASS:		cx	= handle of block from which to retrieve our state
		dx	= start of our data in the block
RETURN:		nothing
DESTROYED:	ax, bx

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	3/25/91		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumRestoreState	proc	far
		.enter
		; Legacy entry point retained for compatibility with old saver API.
		.leave
		ret
AlbumRestoreState	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSaveOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Save any extra options that need saving.

CALLED BY:	Generic saver library
PASS:		nothing
RETURN:		nothing
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	4/12/91		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumSaveOptions	proc	far
		.enter
		clc
		.leave
		ret
AlbumSaveOptions	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumEntry
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Do-nothing entry point for the kernel's benefit

CALLED BY:	kernel
PASS:		di	= LibraryCallTypes
		cx	= handle of client, if LCT_NEW_CLIENT or LCT_CLIENT_EXIT
RETURN:		carry set on error
DESTROYED:	nothing

PSEUDO CODE/STRATEGY:

KNOWN BUGS/SIDE EFFECTS/IDEAS:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	jcw	 3/24/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumEntry	proc	far
	clc		; no errors
	ret
AlbumEntry	endp

ForceRef AlbumEntry

AlbumInitExit	ends

;==============================================================================
;
;		    DRAWING ROUTINES/ENTRY POINTS
;
;==============================================================================

AlbumCode		segment	resource


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSetTimer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set the one-shot timer for the next draw tick.

CALLED BY:	AlbumDrawAndWait, AlbumEraseAndWait
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
		cx	= timer interval in ticks
RETURN:		nothing
DESTROYED:	ax, bx, cx, dx

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumSetTimer	proc	near
	class	AlbumApplicationClass
	.enter

	mov	al, TIMER_EVENT_ONE_SHOT
	mov	dx, MSG_ALBUM_APP_DRAW
	mov	bx, ds:[LMBH_handle]		; ^lbx:si <- destination

	call	TimerStart
	mov	ds:[di].AAI_timerHandle, bx
	mov	ds:[di].AAI_timerID, ax

	.leave
	ret
AlbumSetTimer	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumAppDraw
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Timer-driven draw loop handler.

CALLED BY:	MSG_ALBUM_APP_DRAW
PASS:		*ds:si	= AlbumApplicationClass object
		ds:di	= AlbumApplicationClass instance data
RETURN:		nothing
DESTROYED:	ax, cx, dx, bp

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumAppDraw	method	dynamic	AlbumApplicationClass, MSG_ALBUM_APP_DRAW
	.enter

	tst	ds:[di].SAI_curGState
	jz	quit

	cmp	ds:[di].AAI_nextAction, ALBUM_ACTION_ERASE
	je	doErase

	call	AlbumDrawAndWait
	jmp	quit

doErase:
	call	AlbumEraseAndWait

quit:
	.leave
	ret
AlbumAppDraw	endm


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumEraseAndWait
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Erase the current background and pause for next background

CALLED BY:	AlbumDrawAndWait()
PASS:		none
RETURN:		none
DESTROYED:	ax, bx, cx, dx

PSEUDO CODE/STRATEGY:


KNOWN BUGS/SIDE EFFECTS/IDEAS:


REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	ardeb	6/28/91		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumEraseAndWait	proc	far
	class	AlbumApplicationClass
	uses	ax, cx, es, si, di
	.enter

	call	AlbumErase			;erase the current background

	mov	ds:[di].AAI_nextAction, ALBUM_ACTION_DRAW
	mov	es, ss:[TPD_dgroup]
	mov	cx, es:[astate].AS_pause
	call	AlbumSetTimer

	.leave
	ret
AlbumEraseAndWait	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumDrawAndWait
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Draw a new background and hold it on screen for a while
CALLED BY:	AlbumEraseAndWait()

PASS:		none
RETURN:		none
DESTROYED:	ax, bx, cx, dx

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumDrawAndWait	proc	far
	class	AlbumApplicationClass
	uses	ax, cx, es, si, di
	.enter

	call	AlbumDraw			;draw a new background

	mov	ds:[di].AAI_nextAction, ALBUM_ACTION_ERASE
	mov	es, ss:[TPD_dgroup]
	mov	cx, es:[astate].AS_duration
	call	AlbumSetTimer

	.leave
	ret
AlbumDrawAndWait	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumDraw
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Do one step of drawing the screen saver
CALLED BY:	timer

PASS:		none
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
	This routine *must* be sure there's still a gstate around, as there
	is no synchronization provided by our parent to deal with timer
	methods that have already been queued after the SAVER_STOP method
	is received.
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	9/11/91		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumDraw	proc	near
	uses	ds, si, di
	.enter

	mov	ds, ss:[TPD_dgroup]
if	ALBUM_TRACE_WARNINGS
EC <	WARNING	ALBUM_WARN_STAGE_DRAW_ENTER				>
endif
	;
	; Make sure there is a GState to draw with
	;
	mov	di, ds:[curGState]
	tst	di
	jz	quit
	;
	; Open a BG bitmap file
	;
if	ALBUM_TRACE_WARNINGS
EC <	WARNING	ALBUM_WARN_STAGE_OPEN_RANDOM				>
endif
	call	OpenRandomBGFile		;open me jesus
	;
	; Fill the background with the requested color
	;
	pushf					;save any error from open
EC <	pushf								>
EC <	WARNING_C ALBUM_WARN_FAIL_OPEN_RANDOM			>
EC <	popf								>
	push	bx				;save VM file handle
	mov	al, ds:[astate].AS_color
	cmp	al, -1				;random color?
	jne	gotColor			;branch if not random
	mov	dx, C_WHITE+1
	mov	bx, ds:[curRandom]
	call	SaverRandom
	mov	al, dl				;al <- Colors value
gotColor:
	mov	ah, CF_INDEX
	call	GrSetAreaColor
	clr	ax
	clr	bx
	mov	cx, ds:[winWidth]
	mov	dx, ds:[winHeight]		;(cx,dx) <- window width, height
	call	GrFillRect
	pop	bx				;bx <- VM file handle
	popf					;flags from VMOpen
	jc	quit				;branch if error opening
	;
	; Make sure the color attributes are correct for drawing
	;
	mov	ax, C_BLACK or (CF_INDEX shl 8)
	call	GrSetAreaColor
	call	GrSetTextColor
	;
	; Draw it...
	;
	mov	ax, ds:[astate].AS_mode	;ax <- SaverBitmapMode
	mov	cx, ds:[winWidth]
	mov	dx, ds:[winHeight]
	call	SaverDrawBGBitmap		;draw me jesus
EC <	WARNING_C ALBUM_WARN_FAIL_DRAW_BG_BITMAP		>
EC <	pushf								>
EC <	jnc	noBgDiag						>
EC <	push	bx							>
EC <	call	AlbumECDiagnoseBGBitmapFail				>
EC <	pop	bx							>
EC <noBgDiag:								>
EC <	popf								>

	mov	al, FILE_NO_ERRORS
	call	VMClose				;close me jesus

quit:

	.leave
	ret
AlbumDraw	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		OpenRandomBGFile
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Open a random BG bitmap file
CALLED BY:	AlbumDraw()

PASS:		ds:fileBuffer - handle of filename buffer
		ds:fileCount - # of files in buffer
RETURN:		bx - handle of BG file
		carry - set if error
DESTROYED:	ax, cx, dx

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/31/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

OpenRandomBGFile	proc	near
	uses	es, si, di
	.enter

	;
	; Switch to the BACKGRND directory
	;
	mov	bx, ds:filePath
	tst	bx
	jnz	gotPath
	mov	bx, SP_USER_DATA
gotPath:
	call	GotoBGDirectory
EC <	pushf								>
EC <	WARNING_C ALBUM_WARN_FAIL_GOTO_BG_DIR			>
EC <	popf								>
	jc	quit				;branch if error
	;
	; Lock the buffer of filenames and pick a random file
	;
	mov	dx, ds:fileCount		;dx <- # of files
	tst	dx				;any files?
	jz	noFilesError			;branch if no files
	mov	bx, ds:fileBuffer		;bx <- handle of buffer
	call	MemLock				;lock me jesus
EC <	pushf								>
EC <	WARNING_C ALBUM_WARN_FAIL_MEMLOCK_FILE_LIST		>
EC <	popf								>
	jc	quit				;branch if error
	mov	ds, ax				;ds <- seg addr of buffer
	mov	es, ss:[TPD_dgroup]
	mov	bx, es:[curRandom]
	mov	dx, es:[fileCount]
	call	SaverRandom
	mov	si, dx				;si <- random start index
	mov	cx, es:[fileCount]		;cx <- max tries
tryOpen:
	mov	ax, si				;ax <- file index
	mov	bx, size FileLongName
	mul	bx				;dx:ax <- offset
	mov	dx, ax				;ds:dx <- ptr to file name
	;
	; Try to open this candidate file
	;
	mov	ax, (VMO_OPEN shl 8) or \
			mask VMAF_USE_BLOCK_LEVEL_SYNCHRONIZATION or \
			mask VMAF_FORCE_DENY_WRITE or mask VMAF_FORCE_READ_ONLY
	push	cx				;preserve loop count
	clr	cx
	call	VMOpen				;open says me
	pop	cx
EC <	WARNING_C ALBUM_WARN_FAIL_VMOPEN_BG			>
	jc	nextCandidate			;try another if open failed
	;
	; Only keep files that look like real background files.
	;
	push	cx				;validation clobbers cx
	call	AlbumIsValidBGFile
	pop	cx
	jnc	foundValid
	mov	al, FILE_NO_ERRORS
	call	VMClose
nextCandidate:
	inc	si
	cmp	si, es:[fileCount]
	jb	indexOK
	clr	si
indexOK:
	loop	tryOpen
EC <	WARNING	ALBUM_WARN_FAIL_NO_VALID_BG_FILES			>
	stc
	jmp	unlockAndQuit
foundValid:
	clc
	;
	; Unlock the filename buffer
	;
unlockAndQuit:
	pushf					;preserve open/validate status
	push	bx				;save VM file handle
	mov	ds, ss:[TPD_dgroup]
	mov	bx, ds:fileBuffer		;bx <- handle of buffer
	call	MemUnlock
	pop	bx				;bx <- VM file handle
	popf					;restore open/validate carry
quit:
	.leave
	ret

noFilesError:
EC <	WARNING	ALBUM_WARN_FAIL_NO_FILES				>
	stc					;carry <- error
	jmp	quit
OpenRandomBGFile	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumIsValidBGFile
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Check if an opened VM file is a valid background file.

CALLED BY:	OpenRandomBGFile
PASS:		bx	= VM file handle
RETURN:		carry clear if file has BKGD token + compatible protocol
DESTROYED:	ax, cx, dx, di, es

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumIsValidBGFile	proc	near
	uses	ds, si, bp, di
	.enter

	sub	sp, size GeodeToken
	mov	di, sp
	segmov	es, ss

	mov	ax, FEA_TOKEN
	mov	cx, size GeodeToken
	call	FileGetHandleExtAttributes
	jc	invalid

	cmp	{word} es:[di].GT_chars[0], 'B' or ('K' shl 8)
	jne	invalid
	cmp	{word} es:[di].GT_chars[2], 'G' or ('D' shl 8)
	jne	invalid

	mov	ax, FEA_PROTOCOL
	mov	cx, size ProtocolNumber
	call	FileGetHandleExtAttributes
	jc	invalid

	cmp	es:[di].PN_major, BG_PROTO_MAJOR
	jne	invalid
	cmp	es:[di].PN_minor, BG_PROTO_MINOR
	jb	invalid

	clc
	jmp	done

invalid:
	stc

done:
	.leave
	ret
AlbumIsValidBGFile	endp

if ERROR_CHECK

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumECDiagnoseBGBitmapFail
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Emit EC warnings describing why SaverDrawBGBitmap rejected file.

CALLED BY:	AlbumDraw (EC only)
PASS:		bx	= VM file handle
RETURN:		nothing
DESTROYED:	ax, cx, dx, di, es

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
AlbumECDiagnoseBGBitmapFail	proc	near
	uses	si, ds, bp
	.enter

	sub	sp, size GeodeToken
	mov	di, sp
	segmov	es, ss
	mov	ax, FEA_TOKEN
	mov	cx, size GeodeToken
	call	FileGetHandleExtAttributes
	jnc	haveToken
	WARNING	ALBUM_WARN_FAIL_BG_TOKEN_ATTR
	jmp	done

haveToken:
	cmp	{word} es:[di].GT_chars[0], 'B' or ('K' shl 8)
	jne	badToken
	cmp	{word} es:[di].GT_chars[2], 'G' or ('D' shl 8)
	je	checkProto
badToken:
	WARNING	ALBUM_WARN_FAIL_BG_TOKEN_CHARS
	jmp	done

checkProto:
	mov	ax, FEA_PROTOCOL
	mov	cx, size ProtocolNumber
	call	FileGetHandleExtAttributes
	jnc	haveProto
	WARNING	ALBUM_WARN_FAIL_BG_PROTOCOL_ATTR
	jmp	done

haveProto:
	cmp	es:[di].PN_major, BG_PROTO_MAJOR
	jne	badProto
	cmp	es:[di].PN_minor, BG_PROTO_MINOR
	jb	badProto
	jmp	done

badProto:
	WARNING	ALBUM_WARN_FAIL_BG_PROTOCOL_VERSION

done:
	add	sp, size GeodeToken
	.leave
	ret
AlbumECDiagnoseBGBitmapFail	endp
endif


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumErase
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Erase the screen
CALLED BY:

PASS:		none
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumErase	proc	near
	uses	ds, si, di
	.enter

	mov	ds, ss:[TPD_dgroup]
	;
	; Make sure there is a GState to draw with
	;
	mov	di, ds:[curGState]
	tst	di
	jz	quit
	;
	; Set area color for erasure
	;
	mov	ax, C_BLACK or (CF_INDEX shl 8)
	call	GrSetAreaColor
	;
	; Erase the screen
	;
	clr	ax
	clr	bx
	mov	cx, ds:[winWidth]
	mov	dx, ds:[winHeight]		;(ax,bx,cx,dx) <- window bounds
	mov	si, SAVER_FADE_FAST_SPEED
	call	SaverFadePatternFade		;paint it black...

quit:
	.leave
	ret
AlbumErase	endp

AlbumCode	ends

AlbumInitExit	segment	resource
;==============================================================================
;
;		    UI ACTION HANDLER ENTRY POINTS
;
;==============================================================================


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSetPause
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set pause between backgrounds
CALLED BY:	AlbumPauseRange

PASS:		cx - pause between backgrounds (seconds)
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumSetPause	proc	far
	.enter
	.leave
	ret
AlbumSetPause	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSetDuration
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set duration of each background
CALLED BY:	AlbumDurationRange

PASS:		cx - duration of each background (seconds)
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumSetDuration	proc	far
	.enter
	.leave
	ret
AlbumSetDuration	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSetDrawMode
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set draw mode for bitmap drawing
CALLED BY:	AlbumDrawOptions list

PASS:		cx - SaverBitmapMode
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumSetDrawMode	proc	far
	.enter
	.leave
	ret
AlbumSetDrawMode	endp


COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		AlbumSetColor
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set color for bitmap drawing
CALLED BY:	AlbumColor list

PASS:		cl - Colors
RETURN:		none
DESTROYED:	anything

PSEUDO CODE/STRATEGY:
KNOWN BUGS/SIDE EFFECTS/IDEAS:
REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	eca	10/29/91	Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

AlbumSetColor	proc	far
	.enter
	.leave
	ret
AlbumSetColor	endp

AlbumInitExit	ends
