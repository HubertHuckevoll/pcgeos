COMMENT @----------------------------------------------------------------------

	Copyright (c) GeoWorks 1990 -- All Rights Reserved

PROJECT:	PC GEOS
MODULE:		Hello (Sample PC GEOS application)
FILE:		hello.asm

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Eric	11/90		Initial version
	Eric	 3/91		Simplified by removing text color changes.

DESCRIPTION:
	This file source code for the Hello application. This code will
	be assembled by ESP, and then linked by the GLUE linker to produce
	a runnable .geo application file.

IMPORTANT:
	This example is written for the PC/GEOS V1.0 API. For the V2.0 API,
	we have new ObjectAssembly and Object-C versions.

RCS STAMP:
	$Id: hello.asm,v 1.1 97/04/04 16:32:32 newdeal Exp $

------------------------------------------------------------------------------@

;------------------------------------------------------------------------------
;			Include files
;------------------------------------------------------------------------------

include geos.def
include heap.def
include geode.def
include resource.def
include ec.def

include object.def
include graphics.def
include gstring.def
include lmem.def

include Objects/winC.def


;------------------------------------------------------------------------------
;			Libraries used
;------------------------------------------------------------------------------

UseLib ui.def

;------------------------------------------------------------------------------
;			Class & Method Definitions
;------------------------------------------------------------------------------

;Here we define "HelloProcessClass" as a subclass of the system provided
;"GenProcessClass". As this application is launched, an instance of this class
;will be created, and will handle all application-related events (messages).
;The application thread will be responsible for running this object,
;meaning that whenever this object handles a method, we will be executing
;in the application thread.

HelloProcessClass	class	GenProcessClass

;define messages for this class here.

HelloProcessClass	endc	;end of class definition

;This class definition must be stored in memory at runtime, so that
;the PC/GEOS messaging system can examine it. We will place it in this
;application's idata (initialized data) area, which is part of
;the "DGroup" resource.

idata	segment
	HelloProcessClass	mask CLASSF_NEVER_SAVED
				;this flag necessary because ProcessClass
				;objects are hybrid objects.
idata	ends


;------------------------------------------------------------------------------
;			Resources
;------------------------------------------------------------------------------
;The "hello.ui" file, which contains user-interface descriptions for this
;application, is written in a language called Espire. That file gets compiled
;by UIC, and the resulting assembly statements are written into the
;hello.rdef file. We include that file here, so that these descriptions
;can be assembled into our application.
;
;Precisely, we are assembling .byte and .word statements which comprise the
;exact instance data for each generic object in the .ui file. When this
;application is launched, these resources (such as MenuResource) will be loaded
;into the Global Heap. The objects in the resource can very quickly become
;usable, as they are pre-instantiated.

include		hello.rdef		;include compiled UI definitions

;------------------------------------------------------------------------------
;		Code for HelloProcessClass
;------------------------------------------------------------------------------

CommonCode	segment	resource	;start of code resource


COMMENT @----------------------------------------------------------------------

FUNCTION:	MSG_META_EXPOSED handler.

DESCRIPTION:	This method is sent by the Windowing System when we must
		redraw a portion of the document in the View area.

PASS:		ds	= dgroup
		cx	= handle of window which we must draw to.

RETURN:		ds	= same

CAN DESTROY:	bx, si, di, ds, es

PSEUDO CODE/STRATEGY:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Eric	11/90		initial version

------------------------------------------------------------------------------@

HelloExposed	method	HelloProcessClass, MSG_META_EXPOSED

	mov	di, cx			;set ^hdi = window handle
	call	GrCreateState		;Get a default graphics state that we
					;can use while drawing.

	;first, start a window update. This tells the windowing system that
	;we are in the process of drawing to this window.

	call	GrBeginUpdate

	;if we had background graphics to draw, we would call the
	;apropriate graphics routines now.

	; Draw the bitmap chunks into the window (pass ^hdi = GState).

	call	HelloDrawBitmaps

	;now free the GState, and indicate that we are done drawing to the
	;window.

	call	GrEndUpdate
	call	GrDestroyState

	ret

HelloExposed	endm


COMMENT @----------------------------------------------------------------------

FUNCTION:	HelloDrawBitmaps

DESCRIPTION:	This procedure draws the bitmap chunks onto the document.

CALLED BY:	HelloExposed

PASS:		ds	= dgroup
		di	= handle of GState to draw with (the GState structure
			contains the handle of the window to draw into.)

RETURN:		ds, di	= same

DESTROYED:	?

PSEUDO CODE/STRATEGY:

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	Eric	11/90		initial version

------------------------------------------------------------------------------@

HELLO_BITMAP_COUNT		equ	6
HELLO_BITMAP_LEFT		equ	10
HELLO_BITMAP_TOP		equ	10
HELLO_BITMAP_X_STEP		equ	70

HelloDrawBitmaps	proc	near
	uses	ax, bx, cx, dx, si
	.enter

	mov	si, offset helloBitmapChunks
	mov	cx, HELLO_BITMAP_COUNT
	mov	ax, HELLO_BITMAP_LEFT
drawLoop:
	mov	bx, HELLO_BITMAP_TOP
	mov	dx, cs:[si]
	push	ax, cx, si
	mov	cx, handle TestBitmapResource
	call	TestDrawBitmap
	pop	ax, cx, si
	add	ax, HELLO_BITMAP_X_STEP
	add	si, size word
	loop	drawLoop

	.leave
	ret
HelloDrawBitmaps	endp

helloBitmapChunks	word \
	offset GeoWriteApp16Chunk,
	offset GeoWriteAppMonoChunk,
	offset BridgeChunk,
	offset WassermannTCChunk,
	offset BerndChunk,
	offset DragonChunk


COMMENT @----------------------------------------------------------------------

FUNCTION:	TestDrawBitmap

DESCRIPTION:	Lock a bitmap optr, draw it, and unlock it.

PASS:		di	= GState handle
		ax	= x position
		bx	= y position
		cx	= bitmap block handle
		dx	= bitmap chunk handle

RETURN:		nothing

DESTROYED:	nothing

------------------------------------------------------------------------------@

TestDrawBitmap	proc	near
gstate		local	hptr
xPos		local	word
yPos		local	word
bitmapBlock	local	hptr
bitmapChunk	local	word
	uses	ax, bx, cx, dx, si, di, ds
	.enter

	mov	ss:[gstate], di
	mov	ss:[xPos], ax
	mov	ss:[yPos], bx
	mov	ss:[bitmapBlock], cx
	mov	ss:[bitmapChunk], dx

	mov	bx, cx
	call	MemLock
	mov	ds, ax
	mov	si, ss:[bitmapChunk]
	mov	si, ds:[si]		; ds:si = bitmap

	mov	di, ss:[gstate]
	mov	ax, ss:[xPos]
	mov	bx, ss:[yPos]
	clr	dx			; no callback
	call	GrDrawBitmap

	mov	bx, ss:[bitmapBlock]
	call	MemUnlock

	.leave
	ret
TestDrawBitmap	endp


COMMENT @----------------------------------------------------------------------

FUNCTION:	TestDrawGString

DESCRIPTION:	Lock a gstring optr, load it, draw it, destroy the loaded
		gstring handle, and unlock the optr block.

PASS:		di	= GState handle
		ax	= x position
		bx	= y position
		cx	= gstring block handle
		dx	= gstring chunk handle

RETURN:		nothing

DESTROYED:	nothing

------------------------------------------------------------------------------@

TestDrawGString	proc	near
gstate		local	hptr
xPos		local	word
yPos		local	word
gstringBlock	local	hptr
gstringChunk	local	word
gstringH	local	hptr
	uses	ax, bx, cx, dx, si, di, ds
	.enter

	mov	ss:[gstate], di
	mov	ss:[xPos], ax
	mov	ss:[yPos], bx
	mov	ss:[gstringBlock], cx
	mov	ss:[gstringChunk], dx

	mov	bx, cx
	call	MemLock
	mov	ds, ax
	mov	si, ss:[gstringChunk]
	mov	si, ds:[si]		; ds:si = gstring bytes

	mov	bx, ds
	mov	cl, GST_PTR
	call	GrLoadGString
	mov	ss:[gstringH], si

	mov	di, ss:[gstate]
	mov	ax, ss:[xPos]
	mov	bx, ss:[yPos]
	clr	dx
	call	GrDrawGString

	mov	si, ss:[gstringH]
	clr	di
	mov	dl, GSKT_LEAVE_DATA
	call	GrDestroyGString

	mov	bx, ss:[gstringBlock]
	call	MemUnlock

	.leave
	ret
TestDrawGString	endp

ForceRef	TestDrawGString		; alternate draw helper for gstring chunks

CommonCode	ends		;end of CommonCode resource

;------------------------------------------------------------------------------
;		Bitmap chunks used by HelloDrawBitmaps
;------------------------------------------------------------------------------

TestBitmapResource	segment	lmem LMEM_TYPE_GENERAL

GeoWriteApp16Chunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	0ffh, 081h, 0bdh, 0a5h, 0a5h, 0bdh, 081h, 0ffh
	db	081h, 0bdh, 0a5h, 0a5h, 0bdh, 081h, 081h, 0ffh
	db	0ffh, 081h, 0bdh, 0a5h, 0a5h, 0bdh, 081h, 0ffh
	db	081h, 0bdh, 0a5h, 0a5h, 0bdh, 081h, 081h, 0ffh
GeoWriteApp16Chunk	endc

GeoWriteAppMonoChunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	0ffh, 000h, 081h, 000h, 0bdh, 000h, 0a5h, 000h
	db	0a5h, 000h, 0bdh, 000h, 081h, 000h, 0ffh, 000h
	db	000h, 0ffh, 000h, 081h, 000h, 0bdh, 000h, 0a5h
	db	000h, 0a5h, 000h, 0bdh, 000h, 081h, 000h, 0ffh
GeoWriteAppMonoChunk	endc

BridgeChunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	018h, 018h, 024h, 024h, 042h, 042h, 081h, 081h
	db	0ffh, 0ffh, 081h, 081h, 0ffh, 0ffh, 081h, 081h
	db	018h, 018h, 024h, 024h, 042h, 042h, 081h, 081h
	db	0ffh, 0ffh, 081h, 081h, 0ffh, 0ffh, 081h, 081h
BridgeChunk	endc

WassermannTCChunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	000h, 000h, 03ch, 03ch, 042h, 042h, 099h, 099h
	db	0a5h, 0a5h, 099h, 099h, 042h, 042h, 03ch, 03ch
	db	000h, 000h, 03ch, 03ch, 042h, 042h, 099h, 099h
	db	0a5h, 0a5h, 099h, 099h, 042h, 042h, 03ch, 03ch
WassermannTCChunk	endc

BerndChunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	0f0h, 00fh, 090h, 009h, 090h, 009h, 0f0h, 00fh
	db	090h, 009h, 090h, 009h, 0f0h, 00fh, 000h, 000h
	db	0f0h, 00fh, 090h, 009h, 090h, 009h, 0f0h, 00fh
	db	090h, 009h, 090h, 009h, 0f0h, 00fh, 000h, 000h
BerndChunk	endc

DragonChunk	chunk	Bitmap
	Bitmap	<16,16,BMC_UNCOMPACTED,BMF_MONO>
	db	001h, 080h, 003h, 0c0h, 007h, 0e0h, 00eh, 070h
	db	01ch, 038h, 038h, 01ch, 070h, 00eh, 0e0h, 007h
	db	0e0h, 007h, 070h, 00eh, 038h, 01ch, 01ch, 038h
	db	00eh, 070h, 007h, 0e0h, 003h, 0c0h, 001h, 080h
DragonChunk	endc

TestBitmapResource	ends
