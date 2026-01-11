COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	Copyright (c) GeoWorks 2024 -- All Rights Reserved

PROJECT:	PC GEOS
MODULE:		Stream Drivers -- RawTcp
FILE:		rawtcpMain.asm

AUTHOR:		OpenAI Assistant

ROUTINES:
	Name			Description
	----			-----------
	RawTcpStrategy		Entry point for RawTcp stream driver
	RawTcpLoadOptions	Reads INI options for host/port
	RawTcpOpen		Opens a TCP connection per print job
	RawTcpWrite		Sends data to the TCP socket
	RawTcpClose		Closes the TCP connection

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	OA	9/24/24		Initial revision

DESCRIPTION:
	RawTcp is a simple TCP stream driver for the JetDirect protocol
	(usually TCP port 9100). It reads connection parameters via
	STREAM_ESC_LOAD_OPTIONS and opens a new connection for each job.

	Behavior summary:
	- INI-only configuration via "rawTcpHost" and "rawTcpPort"
	- No hostname resolution; dotted-quad IPv4 only
	- No persistent connections; socket opens/closes per job
	- Uses Socket library APIs (SocketCreate/SocketConnect/SocketSend)
	- Returns StreamError values on failure (STREAM_NO_DEVICE,
	  STREAM_CLOSED)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

include	rawtcp.def

;------------------------------------------------------------------------------
; Constants
;------------------------------------------------------------------------------

RAWTCP_DEFAULT_PORT		equ	9100
RAWTCP_CONNECT_TIMEOUT_TICKS	equ	10 * 60
RAWTCP_RETRY_COUNT		equ	3
RAWTCP_RETRY_DELAY_TICKS	equ	15

RAWTCP_SEND_BUFFER_SIZE	equ	4096
RAWTCP_RECV_BUFFER_SIZE	equ	2048
RAWTCP_MAX_SEND_CHUNK		equ	2048

RAWTCP_TCP_DOMAIN_LENGTH	equ	5

;------------------------------------------------------------------------------
; Data structures
;------------------------------------------------------------------------------

RawTcpConfigFlags	record
	RCF_HOST_VALID:1
	RCF_PORT_VALID:1
	:14
RawTcpConfigFlags	end

RawTcpConfig	struct
	RTC_cfgFlags	RawTcpConfigFlags
	RTC_cfgPort	word
	RTC_cfgIPAddr	IPAddr
	RTC_cfgHostString	byte	MAX_IP_DECIMAL_ADDR_LENGTH_ZT dup (0)
RawTcpConfig	ends

RawTcpContext	struct
	RTC_socket	word
	RTC_connected	word
	RTC_port	word
	RTC_ipAddr	IPAddr
	RTC_hostP	word
	RTC_error	word
	RTC_hostString	byte	MAX_IP_DECIMAL_ADDR_LENGTH_ZT dup (0)
RawTcpContext	ends

RawTcpSocketAddress	struct
	RTSA_socketAddress	SocketAddress
	RTSA_extAddress	word
	RTSA_ipAddr	byte	IP_ADDR_SIZE dup (?)
RawTcpSocketAddress	ends

;------------------------------------------------------------------------------
; Driver info table
;------------------------------------------------------------------------------

idata		segment

DriverTable	DriverInfoStruct	<
	RawTcpStrategy, mask DA_CHARACTER, DRIVER_TYPE_STREAM
>
ForceRef	DriverTable

rawTcpHostKeyString	char	"rawTcpHost",0
rawTcpPortKeyString	char	"rawTcpPort",0
rawTcpTcpDomainString	char	"TCPIP",0

idata		ends

;------------------------------------------------------------------------------
; Globals
;------------------------------------------------------------------------------

udata		segment
rawTcpConfigH	hptr	0
udata		ends

;------------------------------------------------------------------------------
; Escape table
;------------------------------------------------------------------------------

Resident	segment	resource

even
DefEscapeTable	1
DefEscape	RawTcpLoadOptions, STREAM_ESC_LOAD_OPTIONS

;------------------------------------------------------------------------------
; Strategy routine and dispatch table
;------------------------------------------------------------------------------

DefFunction	macro	funcCode, routine
if ($-rawTcpFunctions) ne funcCode
	ErrMessage <routine not in proper slot for funcCode>
endif
		nptr	routine
		endm

rawTcpFunctions	label	nptr
DefFunction	DR_INIT,			RawTcpNull
DefFunction	DR_EXIT,			RawTcpExit
DefFunction	DR_SUSPEND,		RawTcpNull
DefFunction	DR_UNSUSPEND,		RawTcpNull
DefFunction	DR_STREAM_GET_DEVICE_MAP,	RawTcpGetDeviceMap
DefFunction	DR_STREAM_OPEN,		RawTcpOpen
DefFunction	DR_STREAM_CLOSE,		RawTcpClose
DefFunction	DR_STREAM_SET_NOTIFY,	RawTcpSetNotify
DefFunction	DR_STREAM_GET_ERROR,	RawTcpGetError
DefFunction	DR_STREAM_SET_ERROR,	RawTcpSetError
DefFunction	DR_STREAM_FLUSH,		RawTcpNull
DefFunction	DR_STREAM_SET_THRESHOLD,	RawTcpNull
DefFunction	DR_STREAM_READ,		RawTcpReadUnsupported
DefFunction	DR_STREAM_READ_BYTE,	RawTcpReadUnsupported
DefFunction	DR_STREAM_WRITE,		RawTcpWrite
DefFunction	DR_STREAM_WRITE_BYTE,	RawTcpWriteByte
DefFunction	DR_STREAM_QUERY,		RawTcpNull

rawTcpData	sptr	dgroup

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpStrategy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Entry point for all RawTcp-driver functions

CALLED BY:	GLOBAL
PASS:		di	= routine number
		bx	= stream token (open calls ignore this)
RETURN:		depends on function
DESTROYED:

PSEUDO CODE/STRATEGY:
	Dispatch to the appropriate handler. Escape codes are dispatched
	via RawTcpEscape.

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	OA	9/24/24		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpStrategy	proc	far
	uses	es, ds
	tst	di
	js	handleEscape

	.enter

	segmov	es, ds
	mov	ds, cs:rawTcpData

	cmp	di, DR_STREAM_OPEN
	jbe	notYetOpen
	tst	bx
	jnz	haveHandle
	mov	ax, STREAM_CLOSED
	stc
	jmp	exit

haveHandle:
	call	cs:rawTcpFunctions[di]
	jmp	exit

notYetOpen:
	cmp	di, DR_STREAM_OPEN
	jne	doNotYetOpenCall
	EC < WARNING RAWTCP_STRATEGY_BEFORE_OPEN_CALL >
	call	cs:rawTcpFunctions[di]
	EC < WARNING RAWTCP_STRATEGY_AFTER_OPEN_CALL >
	jmp	exit

doNotYetOpenCall:
	call	cs:rawTcpFunctions[di]
	jmp	exit

handleEscape:
	push	es
	push	ds
	call	RawTcpEscape
	pop	ds
	pop	es
	ret

exit:
	.leave
	ret
RawTcpStrategy	endp

global	RawTcpStrategy:far

;------------------------------------------------------------------------------
; Escape handling
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpEscape
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Execute escape function for RawTcp

CALLED BY:	GLOBAL
PASS:		di	= escape code (ORed with 8000h)
RETURN:		di	= 0 if escape not supported
DESTROYED:	see individual functions

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpEscape	proc	far

	push	di, cx, ax, es
	segmov	es, cs
	mov	ax, di
	mov	di, offset escCodes
	mov	cx, NUM_ESC_ENTRIES
	repne	scasw
	pop	ax, es
	jne	notFound

	pop	cx
	EC < WARNING RAWTCP_ESCAPE_BEFORE_CALL >
	call	{word} cs:[di+((offset escRoutines)-(offset escCodes)-2)]
	EC < WARNING RAWTCP_ESCAPE_AFTER_CALL >
	pop	di
	ret

notFound:
	pop	cx
	pop	di
	clr	di
	ret
RawTcpEscape	endp

;------------------------------------------------------------------------------
; INI option loading
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpLoadOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Read host/port options from the .INI file.

CALLED BY:	RawTcpEscape (STREAM_ESC_LOAD_OPTIONS)
PASS:		ds:si	= initfile category (printer name)
RETURN:	nothing
DESTROYED:	allows ax,bx,cx,dx,di,si,bp,es

PSEUDO CODE/STRATEGY:
	- Free any previous config block
	- Read rawTcpPort (default 9100)
	- Read rawTcpHost (dotted IPv4 only)
	- Parse and store IP address for fast connect

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpLoadOptions	proc	near
	uses	ax,bx,cx,dx,di,si,bp,es
	.enter

	EC < WARNING RAWTCP_LOAD_OPTIONS_START >
	;
	; Switch to dgroup to manage config handle.
	;
	push	ds
	push	si
	mov	ax, dgroup
	mov	ds, ax

	mov	bx, ds:[rawTcpConfigH]
	tst	bx
	jz	allocConfig
	call	MemFree
	clr	ds:[rawTcpConfigH]

allocConfig:
	mov	ax, size RawTcpConfig
	mov	cx, ALLOC_DYNAMIC_NO_ERR_LOCK or \
		    (mask HAF_ZERO_INIT shl 8) or \
		    mask HF_SHARABLE
	call	MemAlloc
	jnc	allocOk
	EC < WARNING RAWTCP_CONFIG_ALLOC_FAILED >
	jmp	doneRestore
allocOk:
	mov	ds:[rawTcpConfigH], bx
	mov	es, ax

	mov	es:[RTC_cfgPort], RAWTCP_DEFAULT_PORT
	clr	es:[RTC_cfgFlags]

	;
	; Restore category pointer for InitFileRead* calls.
	;
	pop	si
	pop	ds

	;
	; Read rawTcpPort (default RAWTCP_DEFAULT_PORT)
	;
	mov	cx, dgroup
	mov	dx, offset rawTcpPortKeyString
	call	InitFileReadInteger
	jnc	havePort
	mov	ax, RAWTCP_DEFAULT_PORT
	EC < WARNING RAWTCP_CONFIG_PORT_DEFAULTED >
havePort:
	mov	es:[RTC_cfgPort], ax
	tst	ax
	jz	readHost
	or	es:[RTC_cfgFlags], mask RCF_PORT_VALID

readHost:
	;
	; Read rawTcpHost (dotted IPv4). Use a temporary block then copy.
	;
	mov	cx, dgroup
	mov	dx, offset rawTcpHostKeyString
	clr	bp
	call	InitFileReadString
	jnc	haveHostString
	EC < WARNING RAWTCP_CONFIG_HOST_MISSING >
	jmp	unlockConfig

haveHostString:

	push	bx
	call	MemLock
	mov	ds, ax
	clr	si

	mov	di, offset RTC_cfgHostString
	mov	cx, MAX_IP_DECIMAL_ADDR_LENGTH_ZT
copyHost:
	lodsb
	mov	es:[di], al
	inc	di
	cmp	al, 0
	je	parseHost
	loop	copyHost
	mov	byte ptr es:[di-1], 0

parseHost:
	;
	; Parse and validate dotted-quad IP address.
	;
	mov	ax, es
	mov	ds, ax
	mov	si, offset RTC_cfgHostString
	mov	di, offset RTC_cfgIPAddr
	call	RawTcpParseIPv4
	jc	hostInvalid
	cmp	byte ptr es:[RTC_cfgHostString], 0
	je	hostInvalid
	or	es:[RTC_cfgFlags], mask RCF_HOST_VALID
	test	es:[RTC_cfgFlags], mask RCF_PORT_VALID
	jz	portInvalid
	EC < WARNING RAWTCP_CONFIG_READY >
	jmp	unlockHost

hostInvalid:
	EC < WARNING RAWTCP_CONFIG_HOST_INVALID >
	jmp	unlockHost

portInvalid:
	EC < WARNING RAWTCP_CONFIG_PORT_INVALID >
unlockHost:
	pop	bx
	EC < WARNING RAWTCP_CONFIG_BEFORE_HOST_MEMUNLOCK >
	call	MemUnlock
	EC < WARNING RAWTCP_CONFIG_AFTER_HOST_MEMUNLOCK >
	EC < WARNING RAWTCP_CONFIG_BEFORE_HOST_MEMFREE >
	call	MemFree
	EC < WARNING RAWTCP_CONFIG_AFTER_HOST_MEMFREE >

unlockConfig:
	push	ds
	mov	ax, dgroup
	mov	ds, ax
	mov	bx, ds:[rawTcpConfigH]
	pop	ds
	EC < WARNING RAWTCP_CONFIG_BEFORE_CONFIG_MEMUNLOCK >
	call	MemUnlock
	EC < WARNING RAWTCP_CONFIG_AFTER_CONFIG_MEMUNLOCK >
	jmp	done

; MemAlloc failed; restore stack and exit

doneRestore:
	pop	si
	pop	ds

done:
	.leave
	ret
RawTcpLoadOptions	endp

;------------------------------------------------------------------------------
; Driver entry points
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpNull
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	No-op routine for unsupported functions.

CALLED BY:	various driver entry points
RETURN:		carry clear

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpNull	proc	near
	clc
	ret
RawTcpNull	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpExit
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Free cached configuration block, if present.

CALLED BY:	DR_EXIT

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpExit	proc	near
	uses	bx
	.enter
	mov	bx, ds:[rawTcpConfigH]
	tst	bx
	jz	done
	call	MemFree
	clr	ds:[rawTcpConfigH]

	done:
	clc
	.leave
	ret
RawTcpExit	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpGetDeviceMap
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Return no physical device map.

CALLED BY:	DR_STREAM_GET_DEVICE_MAP
RETURN:		ax = 0

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpGetDeviceMap	proc	near
	clr	ax
	clc
	ret
RawTcpGetDeviceMap	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpSetNotify
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Notification stub (no async events reported).

CALLED BY:	DR_STREAM_SET_NOTIFY

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpSetNotify	proc	near
	clc
	ret
RawTcpSetNotify	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpGetError
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	No stored error; return 0.

CALLED BY:	DR_STREAM_GET_ERROR

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpGetError	proc	near
	clr	ax
	clc
	ret
RawTcpGetError	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpSetError
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Ignore error postings.

CALLED BY:	DR_STREAM_SET_ERROR

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpSetError	proc	near
	clc
	ret
RawTcpSetError	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpReadUnsupported
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	RawTcp is write-only; read operations are unsupported.

CALLED BY:	DR_STREAM_READ, DR_STREAM_READ_BYTE
RETURN:		carry set, ax = STREAM_CLOSED

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpReadUnsupported	proc	near
	mov	ax, STREAM_CLOSED
	stc
	ret
RawTcpReadUnsupported	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpWriteByte
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Write a single byte by delegating to RawTcpWrite.

CALLED BY:	DR_STREAM_WRITE_BYTE

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpWriteByte	proc	near
	push	ds
	push	si
	push	cx
	sub	sp, 2
	mov	si, sp
	mov	ss:[si], cl
	segmov	ds, ss
	segmov	es, ds
	mov	si, sp
	mov	cx, 1
	call	RawTcpWrite
	mov	cx, ax
	lahf
	add	sp, 2
	sahf
	mov	ax, cx
	pop	cx
	pop	si
	pop	ds
	ret
RawTcpWriteByte	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpOpen
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Open a socket connection for a print job.

CALLED BY:	DR_STREAM_OPEN
PASS:		bx	= ignored (CPP_info block from spooler)
RETURN:		bx	= stream token (context handle)
		carry set + ax = STREAM_NO_DEVICE on failure

PSEUDO CODE/STRATEGY:
	- Validate config data loaded by STREAM_ESC_LOAD_OPTIONS
	- Allocate a per-open context block
	- Create and connect a TCP socket (with limited retries)
	- Configure socket options (send/recv buffers, NO_DELAY, LINGER)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpOpen	proc	near
	uses	ax,cx,dx,si,di,bp,es
	.enter

	push	ds
	mov	bx, ds:[rawTcpConfigH]
	tst	bx
	jnz	haveConfig
	EC < WARNING RAWTCP_OPEN_NO_CONFIG >
	jmp	configError
haveConfig:
	mov	dx, bx
	EC < WARNING RAWTCP_OPEN_BEFORE_MEMLOCK >
	call	MemLock
	EC < WARNING RAWTCP_OPEN_AFTER_MEMLOCK >
	mov	es, ax

	test	es:[RTC_cfgFlags], mask RCF_HOST_VALID
	jnz	hostValid
	EC < WARNING RAWTCP_OPEN_CONFIG_INVALID >
	jmp	configUnlockError
hostValid:
	test	es:[RTC_cfgFlags], mask RCF_PORT_VALID
	jnz	portValid
	EC < WARNING RAWTCP_OPEN_CONFIG_INVALID >
	jmp	configUnlockError
portValid:

	;
	; Allocate context for this open.
	;
	mov	ax, size RawTcpContext
	mov	cx, ALLOC_DYNAMIC_NO_ERR_LOCK or \
		    (mask HAF_ZERO_INIT shl 8) or \
		    mask HF_SHARABLE
	call	MemAlloc
	jnc	contextAllocOk
	EC < WARNING RAWTCP_OPEN_CONTEXT_ALLOC_FAILED >
	jmp	configUnlockError
contextAllocOk:

	mov	bp, bx				; context handle
	mov	ds, ax				; ds = context segment

	mov	ds:[RTC_socket], 0
	mov	ds:[RTC_connected], 0
	mov	ax, es:[RTC_cfgPort]
	mov	ds:[RTC_port], ax
	mov	ds:[RTC_hostP], offset RTC_hostString
	clr	ds:[RTC_error]

	;
	; Copy IP and host string into context.
	;
	push	ds
	push	es
	mov	ax, ds
	mov	cx, es
	mov	ds, cx
	mov	es, ax

	lea	si, [RTC_cfgIPAddr]
	lea	di, [RTC_ipAddr]
	mov	cx, size IPAddr
	rep	movsb

	lea	si, [RTC_cfgHostString]
	lea	di, [RTC_hostString]
	mov	cx, MAX_IP_DECIMAL_ADDR_LENGTH_ZT
	rep	movsb

	pop	es
	pop	ds

	mov	bx, dx
	call	MemUnlock

	;
	; Retry socket open/connect a few times.
	;
	mov	cx, RAWTCP_RETRY_COUNT
openRetry:
	mov	ax, SDT_STREAM
	EC < WARNING RAWTCP_OPEN_BEFORE_SOCKET_CREATE >
	call	SocketCreate
	EC < WARNING RAWTCP_OPEN_AFTER_SOCKET_CREATE >
	jnc	createOk
	EC < WARNING RAWTCP_OPEN_SOCKET_CREATE_FAILED >
	jmp	retryDelay

createOk:
	mov	ds:[RTC_socket], bx

	;
	; Build socket address on stack for connect.
	;
	push	ds
	push	si
	push	di
	push	cx
	mov	ax, size RawTcpSocketAddress
	sub	sp, ax
	mov	di, sp
	segmov	es, ss

	mov	ax, ds:[RTC_port]
	mov	es:[di].RTSA_socketAddress.SA_port.SP_port, ax
	mov	es:[di].RTSA_socketAddress.SA_port.SP_manuf, MANUFACTURER_ID_SOCKET_16BIT_PORT
	mov	es:[di].RTSA_socketAddress.SA_domainSize, RAWTCP_TCP_DOMAIN_LENGTH
	mov	es:[di].RTSA_socketAddress.SA_domain.offset, offset rawTcpTcpDomainString
	mov	ax, dgroup
	mov	es:[di].RTSA_socketAddress.SA_domain.segment, ax
	mov	es:[di].RTSA_socketAddress.SA_addressSize, size word + IP_ADDR_SIZE

	lea	di, es:[di].RTSA_socketAddress.SA_address
	mov	{word} es:[di], 0			; ESACA_linkSize

	lea	si, ds:[RTC_ipAddr]
	add	di, size word
	mov	cx, size IPAddr
	rep	movsb

	mov	cx, ss
	mov	dx, sp
	push	bp
	mov	bp, RAWTCP_CONNECT_TIMEOUT_TICKS
	EC < WARNING RAWTCP_OPEN_BEFORE_SOCKET_CONNECT >
	call	SocketConnect
	EC < WARNING RAWTCP_OPEN_AFTER_SOCKET_CONNECT >
	pop	bp

	add	sp, size RawTcpSocketAddress
	pop	cx
	pop	di
	pop	si
	pop	ds

	jc	connectFail

	;
	; Set socket options (best effort, no error returns available).
	;
	call	RawTcpSetSocketOptions

	mov	ds:[RTC_connected], TRUE

	mov	bx, bp
	call	MemUnlock
	mov	bx, bp
	EC < WARNING RAWTCP_OPEN_SUCCESS >
	clc
	jmp	done

connectFail:
	EC < WARNING RAWTCP_OPEN_SOCKET_CONNECT_FAILED >
	call	SocketClose
	jmp	retryDelay
retryDelay:
	clr	ds:[RTC_socket]
	dec	cx
	jz	openFail
	mov	ax, RAWTCP_RETRY_DELAY_TICKS
	call	TimerSleep
	jmp	openRetry

openFail:
	mov	bx, bp
	call	MemUnlock
	mov	bx, bp
	call	MemFree

configError:
	mov	ax, STREAM_NO_DEVICE
	stc
	jmp	done

configUnlockError:
	mov	bx, dx
	call	MemUnlock
	mov	ax, STREAM_NO_DEVICE
	stc
	done:
	pop	ds
	.leave
	ret
RawTcpOpen	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpWrite
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Send data to the connected socket.

CALLED BY:	DR_STREAM_WRITE
PASS:		es:si	= buffer
		cx	= byte count
		bx	= context handle
RETURN:		carry clear + ax = bytes written on success
		carry set + ax = STREAM_CLOSED on failure

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpWrite	proc	near
	callerSeg	local	word
	contextSeg	local	word
	contextHandle	local	word
	driverSeg	local	word
	callerNeedsCopy	local	word
	callerIsLMem	local	word
	callerChunkSize	local	word
	chunkSize	local	word
	tempBufferH	local	word
	requestedCount	local	word
	uses	ax,dx,di,bp,es
	.enter

	mov	ss:[driverSeg], ds
	mov	ax, es
	tst	ax
	jz	invalidCallerSeg

	tst	bx
	jz	invalidHandle
	mov	di, bx
	mov	ss:[contextHandle], bx
EC < 	WARNING RAWTCP_WRITE_CAPTURE_CALLER_SEG >

	mov	ss:[requestedCount], cx

	mov	ss:[callerSeg], es
	mov	cx, ss
	cmp	ax, cx
	je	callerSegNeedsCopy
	mov	cx, ss:[callerSeg]
	call	MemSegmentToHandle
	jc	callerSegHandleBacked
callerSegNeedsCopy:
	mov	ss:[callerNeedsCopy], TRUE
	jmp	callerSegChecked
callerSegHandleBacked:
	clr	ss:[callerNeedsCopy]
callerSegChecked:
EC < 	mov	ax, ss:[callerSeg]				>
EC < 	tst	ah						>
EC < 	WARNING_Z RAWTCP_WRITE_CALLER_SEG_LOW			>
EC < 	tst	ax						>
EC < 	WARNING_Z RAWTCP_WRITE_CALLER_SEG_ZERO			>
EC < 	mov	ax, bx						>
EC < 	tst	ax						>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_HANDLE_ZERO		>
	mov	ss:[callerIsLMem], FALSE
	mov	ss:[callerChunkSize], 0
	;
	; Guard against caller buffer overruns in handle-backed segments.
	;
	tst	ss:[callerNeedsCopy]
	jnz	bufferOk
	push	bx
	push	ds
	mov	cx, ss:[callerSeg]
	call	MemSegmentToHandle
	jnc	bufferCheckDone
	mov	bx, cx
	mov	ax, MGIT_FLAGS_AND_LOCK_COUNT
	call	MemGetInfo
	test	al, mask HF_LMEM
	jz	bufferCheckBlock
	mov	ss:[callerIsLMem], TRUE
	mov	ds, ss:[callerSeg]
	ChunkSizePtr	ds, si, cx
	mov	ss:[callerChunkSize], cx
	cmp	cx, ss:[requestedCount]
	jae	bufferCheckDone
	jmp	shortBuffer
bufferCheckBlock:
	mov	ax, MGIT_SIZE
	call	MemGetInfo
	sub	ax, si
	jc	shortBuffer
	cmp	ax, ss:[requestedCount]
	jae	bufferCheckDone
shortBuffer:
	pop	ds
	pop	bx
	mov	ax, STREAM_SHORT_READ_WRITE
	clr	cx
	stc
	jmp	shortWriteExit
bufferCheckDone:
	pop	ds
	pop	bx
bufferOk:
EC < 	WARNING RAWTCP_WRITE_BEFORE_MEMLOCK >
	push	ds
	call	MemLock
	pop	ds
	tst	ax
	jz	lockFailed
EC < 	WARNING RAWTCP_WRITE_AFTER_MEMLOCK >
	mov	es, ax
	mov	ss:[contextSeg], ax
EC < 	mov	ax, ss:[contextSeg]				>
EC < 	tst	ah						>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_SEG_LOW		>
EC < 	tst	ax						>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_SEG_ZERO		>

	tst	es:[RTC_connected]
	jz	notConnected
	mov	bx, es:[RTC_socket]
	tst	bx
	jz	notConnected

	;
	; debug call
	;
;		call	RawTcpWriteDebugTest
;		mov	ax, ss:[requestedCount]
;		mov	cx, ss:[requestedCount]
;		jmp	done

	mov	cx, ss:[requestedCount]
	tst	ss:[callerIsLMem]
	jz	sendCountReady
	cmp	cx, ss:[callerChunkSize]
	jbe	sendCountReady
	mov	cx, ss:[callerChunkSize]
	mov	ss:[requestedCount], cx
sendCountReady:
	mov	dx, cx
	clr	bp

sendLoop:
	tst	dx
	jz	sendDone
	mov	cx, dx
	cmp	cx, RAWTCP_MAX_SEND_CHUNK
	jbe	sendChunk
	mov	cx, RAWTCP_MAX_SEND_CHUNK
sendChunk:
EC 	< WARNING RAWTCP_WRITE_LOAD_CALLER_SEG >
	mov	ss:[chunkSize], cx
	mov	ds, ss:[callerSeg]
	tst	ss:[callerNeedsCopy]
	jnz	sendChunkCopy
	mov	cx, ss:[chunkSize]
	clr	ax
EC < 	WARNING RAWTCP_WRITE_PRE_SEND_SEGMENTS >
EC < 	mov	ax, ds						>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_DS_ZERO			>
EC < 	mov	ax, ss:[callerSeg]				>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_CALLER_SEG_ZERO		>
EC < 	mov	ax, es						>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_ES_ZERO			>
EC < 	WARNING RAWTCP_WRITE_BEFORE_SOCKET_SEND >
EC < 	clr	ax					>
	call	SocketSend
EC < 	WARNING RAWTCP_WRITE_AFTER_SOCKET_SEND >
EC < 	WARNING RAWTCP_WRITE_POST_SEND_VALIDATE >
EC < 	tst	bx						>
EC < 	WARNING_Z RAWTCP_WRITE_SOCKET_HANDLE_ZERO		>
EC < 	mov	ax, es						>
EC < 	tst	ax						>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_SEG_ZERO		>
	jc	sendError
	add	bp, ss:[chunkSize]
	add	si, ss:[chunkSize]
	sub	dx, ss:[chunkSize]
	jmp	sendLoop

sendChunkCopy:
	push	bx
	mov	ax, ss:[chunkSize]
	mov	cx, ALLOC_DYNAMIC_NO_ERR or \
		    (mask HAF_ZERO_INIT shl 8)
	call	MemAlloc
	jnc	tempAllocOk
	pop	bx
	jmp	sendError

tempAllocOk:
	mov	ss:[tempBufferH], bx
	pop	bx
	push	bx
	mov	bx, ss:[tempBufferH]
	push	ds
	call	MemLock
	pop	ds
	pop	bx
	tst	ax
	jz	tempLockFailed
	push	es
	mov	es, ax
	push	si
	push	di
	clr	di
	mov	cx, ss:[chunkSize]
	rep	movsb
	pop	di
	pop	si
	pop	es
	push	ds
	push	si
	mov	ds, ax
	clr	si
	mov	cx, ss:[chunkSize]
	clr	ax
EC < 	WARNING RAWTCP_WRITE_PRE_SEND_SEGMENTS >
EC < 	mov	ax, ds						>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_DS_ZERO			>
EC < 	mov	ax, ss:[callerSeg]				>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_CALLER_SEG_ZERO		>
EC < 	mov	ax, es						>
EC < 	tst	ax					>
EC < 	WARNING_Z RAWTCP_WRITE_ES_ZERO			>
EC < 	WARNING RAWTCP_WRITE_BEFORE_SOCKET_SEND >
EC < 	clr	ax					>
	call	SocketSend
EC < 	WARNING RAWTCP_WRITE_AFTER_SOCKET_SEND >
EC < 	WARNING RAWTCP_WRITE_POST_SEND_VALIDATE >
EC < 	tst	bx						>
EC < 	WARNING_Z RAWTCP_WRITE_SOCKET_HANDLE_ZERO		>
EC < 	mov	ax, es						>
EC < 	tst	ax						>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_SEG_ZERO		>
	pop	si
	pop	ds
	pushf
	push	bx
	mov	ds, ss:[driverSeg]
	mov	bx, ss:[tempBufferH]
	call	MemUnlock
	call	MemFree
	pop	bx
	popf
	jc	sendError
	add	bp, ss:[chunkSize]
	add	si, ss:[chunkSize]
	sub	dx, ss:[chunkSize]
	jmp	sendLoop

tempLockFailed:
	push	bx
	mov	bx, ss:[tempBufferH]
	mov	ds, ss:[driverSeg]
	call	MemFree
	pop	bx
	jmp	sendError

sendError:
EC < 	WARNING RAWTCP_WRITE_SEND_FAILED >
	mov	ds, ss:[driverSeg]
	mov	es, ss:[contextSeg]
	mov	bx, es:[RTC_socket]
	tst	bx
EC < 	WARNING_Z RAWTCP_WRITE_SOCKET_HANDLE_ZERO >
	jz	skipClose
EC < 	WARNING RAWTCP_WRITE_BEFORE_SOCKET_CLOSE >
	call	SocketClose
EC < 	WARNING RAWTCP_WRITE_AFTER_SOCKET_CLOSE >
skipClose:
	clr	es:[RTC_socket]
	clr	es:[RTC_connected]
	mov	ax, STREAM_CLOSED
	clr	cx
	stc
	jmp	done

sendDone:
	mov	ax, bp
	mov	cx, bp
	clc
	jmp	done

notConnected:
EC < 	WARNING RAWTCP_WRITE_NOT_CONNECTED >
	mov	ax, STREAM_CLOSED
	clr	cx
	stc

done:
	mov	ds, ss:[driverSeg]
	mov	bx, ss:[contextHandle]
EC < 	mov	ax, bx
EC < 	tst	ax 					>
EC < 	WARNING_Z RAWTCP_WRITE_CONTEXT_HANDLE_ZERO		>
	call	MemUnlock
	.leave
	ret

invalidHandle:
	mov	ax, STREAM_CLOSED
	clr	cx
	stc
	.leave
	ret

invalidCallerSeg:
	mov	ax, STREAM_CLOSED
	clr	cx
	stc
	.leave
	ret

shortWriteExit:
	.leave
	ret

lockFailed:
	mov	ax, STREAM_CLOSED
	clr	cx
	stc
	.leave
	ret
RawTcpWrite	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpClose
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Close the socket and free the context block.

CALLED BY:	DR_STREAM_CLOSE
PASS:		ax	= STREAM_LINGER or STREAM_DISCARD (ignored)
		bx	= context handle
RETURN:		carry clear

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpClose	proc	near
	uses	ax,di,es
	.enter

	mov	di, bx
	tst	bx
	jz	done

	call	MemLock
	mov	es, ax

	mov	bx, es:[RTC_socket]
	tst	bx
	jnz	closeSocket
	EC < WARNING RAWTCP_CLOSE_WITHOUT_SOCKET >
	jmp	clearState
closeSocket:
	EC < WARNING RAWTCP_CLOSE_BEFORE_SOCKET_CLOSE >
	call	SocketClose
	EC < WARNING RAWTCP_CLOSE_AFTER_SOCKET_CLOSE >

clearState:
	clr	es:[RTC_socket]
	clr	es:[RTC_connected]
	clr	es:[RTC_error]

	mov	bx, di
	call	MemUnlock
	mov	bx, di
	call	MemFree

	done:
	clc
	.leave
	ret
RawTcpClose	endp

;------------------------------------------------------------------------------
; Helpers
;------------------------------------------------------------------------------

rawTcpDebugTestPayload	db	"test"
rawTcpDebugTestPayloadLength	equ	($ - rawTcpDebugTestPayload)

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpWriteDebugTest
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Send a small debug payload to the socket.

CALLED BY:	RawTcpWrite
PASS:		es	= locked context segment
		bx	= socket handle
RETURN:		carry clear + ax/cx = bytes written on success
		carry set + ax = error on failure

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpWriteDebugTest	proc	near
	uses	ds,si,cx
	.enter

	mov	ax, cs
	mov	ds, ax
	mov	si, offset rawTcpDebugTestPayload
	mov	cx, rawTcpDebugTestPayloadLength
	clr	ax
	call	SocketSend
	jc	done
	mov	ax, rawTcpDebugTestPayloadLength
	mov	cx, ax

done:
	.leave
	ret
RawTcpWriteDebugTest	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpSetSocketOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set socket buffer sizes and boolean options.

CALLED BY:	RawTcpOpen
PASS:		bx	= socket handle
RETURN:		nothing

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpSetSocketOptions	proc	near
	uses	ax,cx
	.enter

	mov	ax, SO_SEND_BUF
	mov	cx, RAWTCP_SEND_BUFFER_SIZE
	call	SocketSetSocketOption

	mov	ax, SO_RECV_BUF
	mov	cx, RAWTCP_RECV_BUFFER_SIZE
	call	SocketSetSocketOption

	mov	ax, SO_NODELAY
	mov	cx, TRUE
	call	SocketSetSocketOption

	mov	ax, SO_LINGER
	mov	cx, FALSE
	call	SocketSetSocketOption

	.leave
	ret
RawTcpSetSocketOptions	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpParseIPv4
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Parse dotted-quad IPv4 string into IPAddr.

CALLED BY:	RawTcpLoadOptions
PASS:		ds:si	= null-terminated string
		es:di	= IPAddr output buffer
RETURN:		carry clear if valid; IPAddr written
		carry set if invalid format

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpParseIPv4	proc	near
	uses	ax,bx,cx,dx,si,di
	.enter

	clr	cl				; octet count

parseOctet:
	xor	bx, bx
	clr	ch				; digit count

digitLoop:
	lodsb
	cmp	al, '0'
	jb	endDigits
	cmp	al, '9'
	ja	endDigits
	inc	ch
	mov	ah, 0
	sub	al, '0'
	mov	dx, ax				; dx = digit
	mov	ax, bx
	shl	ax, 1
	mov	bx, ax
	shl	ax, 1
	shl	ax, 1
	add	ax, bx
	mov	bx, ax
	add	bx, dx
	cmp	bx, 255
	ja	invalid
	jmp	digitLoop

endDigits:
	cmp	ch, 0
	je	invalid
	mov	es:[di], bl
	inc	di
	inc	cl
	cmp	al, '.'
	je	needMore
	cmp	al, 0
	je	maybeDone
	jmp	invalid

needMore:
	cmp	cl, 4
	jae	invalid
	jmp	parseOctet

maybeDone:
	cmp	cl, 4
	jne	invalid
	clc
	jmp	parseDone

invalid:
	EC < WARNING RAWTCP_PARSE_IPV4_INVALID >
	stc

parseDone:
	.leave
	ret
RawTcpParseIPv4	endp

Resident	ends
