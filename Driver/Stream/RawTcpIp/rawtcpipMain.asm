COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:	PC GEOS
MODULE:		Stream Drivers -- RawTcpIp
FILE:		rawtcpipMain.asm

AUTHOR:		OpenAI Assistant, prompted by Meyer in 01/2026

ROUTINES:
	Name			Description
	----			-----------
	RawTcpIpStrategy		Entry point for RawTcpIp stream driver
	RawTcpIpLoadOptions	Reads INI options for host/port
	RawTcpIpOpen		Opens a TCP connection per print job
	RawTcpIpWrite		Sends data to the TCP socket
	RawTcpIpClose		Closes the TCP connection

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	OA	01/2026		Initial revision

DESCRIPTION:
	RawTcpIp is a simple TCP stream driver for the JetDirect protocol
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

include	rawtcpip.def

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

RawTcpIpConfigFlags	record
	RCF_HOST_VALID:1
	RCF_PORT_VALID:1
	:14
RawTcpIpConfigFlags	end

RawTcpIpConfig	struct
	RTC_cfgFlags	RawTcpIpConfigFlags
	RTC_cfgPort	word
	RTC_cfgIPAddr	IPAddr
	RTC_cfgHostString	byte	MAX_IP_DECIMAL_ADDR_LENGTH_ZT dup (0)
RawTcpIpConfig	ends

RawTcpIpContext	struct
	RTC_socket	word
	RTC_connected	word
	RTC_port	word
	RTC_ipAddr	IPAddr
	RTC_hostP	word
	RTC_error	word
	RTC_hostString	byte	MAX_IP_DECIMAL_ADDR_LENGTH_ZT dup (0)
RawTcpIpContext	ends

RawTcpIpSocketAddress	struct
	RTSA_socketAddress	SocketAddress
	RTSA_extAddress	word
	RTSA_ipAddr	byte	IP_ADDR_SIZE dup (?)
RawTcpIpSocketAddress	ends

;------------------------------------------------------------------------------
; Driver info table
;------------------------------------------------------------------------------

idata		segment

DriverTable	DriverInfoStruct	<
	RawTcpIpStrategy, mask DA_CHARACTER, DRIVER_TYPE_STREAM
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
DefEscape	RawTcpIpLoadOptions, STREAM_ESC_LOAD_OPTIONS

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
DefFunction	DR_INIT,			RawTcpIpNull
DefFunction	DR_EXIT,			RawTcpIpExit
DefFunction	DR_SUSPEND,			RawTcpIpNull
DefFunction	DR_UNSUSPEND,			RawTcpIpNull
DefFunction	DR_STREAM_GET_DEVICE_MAP,	RawTcpIpGetDeviceMap
DefFunction	DR_STREAM_OPEN,			RawTcpIpOpen
DefFunction	DR_STREAM_CLOSE,		RawTcpIpClose
DefFunction	DR_STREAM_SET_NOTIFY,		RawTcpIpSetNotify
DefFunction	DR_STREAM_GET_ERROR,		RawTcpIpGetError
DefFunction	DR_STREAM_SET_ERROR,		RawTcpIpSetError
DefFunction	DR_STREAM_FLUSH,		RawTcpIpNull
DefFunction	DR_STREAM_SET_THRESHOLD,	RawTcpIpNull
DefFunction	DR_STREAM_READ,			RawTcpIpReadUnsupported
DefFunction	DR_STREAM_READ_BYTE,		RawTcpIpReadUnsupported
DefFunction	DR_STREAM_WRITE,		RawTcpIpWrite
DefFunction	DR_STREAM_WRITE_BYTE,		RawTcpIpWriteByte
DefFunction	DR_STREAM_QUERY,		RawTcpIpNull

rawTcpData	sptr	dgroup

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpStrategy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Entry point for all RawTcpIp-driver functions

CALLED BY:	GLOBAL
PASS:		di	= routine number
		bx	= stream token (open calls ignore this)
RETURN:		depends on function
DESTROYED:

PSEUDO CODE/STRATEGY:
	Dispatch to the appropriate handler. Escape codes are dispatched
	via RawTcpIpEscape.

REVISION HISTORY:
	Name	Date		Description
	----	----		-----------
	OA	9/24/24		Initial version

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpStrategy	proc	far
	uses	es, ds

	tst	di			; Test di, see if it's an escape function
	js	handleEscape		; Jump if sign bit is set (i.e. < 0)

	.enter

	segmov	es, ds			; Set ES to DS for upcoming operations
	mov	ds, cs:rawTcpData	; Point DS to our data segment

	cmp	di, DR_STREAM_OPEN	; Check if the function is DR_STREAM_OPEN or earlier
	jbe	notYetOpen		; If so, handle as a pre-open call
	tst	bx			; Check if we have a valid stream handle in BX
	jnz	haveHandle		; If yes, proceed to call the function
	mov	ax, STREAM_CLOSED	; Otherwise, return a STREAM_CLOSED error
	stc				; Set carry to indicate an error
	jmp	exit			; And exit

haveHandle:
	call	cs:rawTcpFunctions[di]	; Call the appropriate driver function from the jump table
	jmp	exit

notYetOpen:
	cmp	di, DR_STREAM_OPEN	; Is the call specifically to open the stream?
	jne	doNotYetOpenCall	; If not, jump to the other handler
	call	cs:rawTcpFunctions[di]	; If yes, call the open function
	jmp	exit

doNotYetOpenCall:
	call	cs:rawTcpFunctions[di]	; Call the pre-open function from the jump table
	jmp	exit

handleEscape:
	push	es			; Save ES and DS registers
	push	ds
	call	RawTcpIpEscape		; Call the escape function handler
	pop	ds			; Restore registers
	pop	es
	ret				; Return from the driver call

exit:
	.leave
	ret
RawTcpIpStrategy	endp

global	RawTcpIpStrategy:far

;------------------------------------------------------------------------------
; Escape handling
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpEscape
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Execute escape function for RawTcpIp

CALLED BY:	GLOBAL
PASS:		di	= escape code (ORed with 8000h)
RETURN:		di	= 0 if escape not supported
DESTROYED:	see individual functions

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpEscape	proc	far

	push	di, cx, ax, es		; Save registers that will be used
	segmov	es, cs			; Set ES to CS for scanning the escape code table
	mov	ax, di			; Move the escape code from DI into AX for scasw
	mov	di, offset escCodes	; Point DI to the beginning of the escape code table
	mov	cx, NUM_ESC_ENTRIES	; Load CX with the number of escape codes to check
	repne	scasw			; Scan the table for the escape code in AX
	pop	ax, es			; Restore original AX and ES
	jne	notFound		; If no match was found, jump to notFound

	pop	cx			; Restore original CX
	;--- now call the correct routine from a parallel table ---
	call	{word} cs:[di+((offset escRoutines)-(offset escCodes)-2)]
	pop	di			; Restore original DI
	ret

notFound:
	pop	cx			; Restore original CX and DI
	pop	di
	clr	di			; Clear DI to signal an error/not found
	ret
RawTcpIpEscape	endp

;------------------------------------------------------------------------------
; INI option loading
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpLoadOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Read host/port options from the .INI file.

CALLED BY:	RawTcpIpEscape (STREAM_ESC_LOAD_OPTIONS)
PASS:		ds:si	= initfile category (printer name)
RETURN:	nothing
DESTROYED:	allows ax,bx,cx,dx,di,si,bp,es

PSEUDO CODE/STRATEGY:
	- Free any previous config block
	- Read rawTcpPort (default 9100)
	- Read rawTcpHost (dotted IPv4 only)
	- Parse and store IP address for fast connect

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpLoadOptions	proc	near
	uses	ax,bx,cx,dx,di,si,bp,es
	.enter

	;
	; Switch to dgroup to manage config handle.
	;
	push	ds			; Preserve original DS and SI
	push	si
	mov	ax, dgroup		; Switch DS to the driver's data segment
	mov	ds, ax

	mov	bx, ds:[rawTcpConfigH]	; Load existing config block handle, if any
	tst	bx			; Check if a handle already exists
	jz	allocConfig		; If not (handle is zero), jump to allocate a new one
	call	MemFree			; If one exists, free the old memory block
	clr	ds:[rawTcpConfigH]	; Clear the handle variable

allocConfig:
	mov	ax, size RawTcpIpConfig	; Get the size needed for the config structure

	; Set up allocation flags: dynamic, zero-initialized, and sharable
	mov	cx, ALLOC_DYNAMIC_NO_ERR_LOCK or (mask HAF_ZERO_INIT shl 8) or mask HF_SHARABLE
	call	MemAlloc		; Allocate memory for the configuration
	jnc	allocOk			; If allocation succeeds (no carry), continue
	EC < WARNING RAWTCP_CONFIG_ALLOC_FAILED > ; Log a warning on failure
	jmp	doneRestore		; Jump to cleanup code

allocOk:
	mov	ds:[rawTcpConfigH], bx	; Store the new handle (from BX) in our global variable
	mov	es, ax			; Set ES to the new block's segment (from AX) for access

	mov	es:[RTC_cfgPort], RAWTCP_DEFAULT_PORT ; Initialize the port with the default value
	clr	es:[RTC_cfgFlags]	; Clear all configuration flags

	;
	; Restore category pointer for InitFileRead* calls.
	;
	pop	si			; Restore original SI and DS
	pop	ds

	;
	; Read rawTcpPort (default RAWTCP_DEFAULT_PORT)
	;
	mov	cx, dgroup		; Set CX to dgroup for InitFile... routines
	mov	dx, offset rawTcpPortKeyString ; Point DX to the "rawTcpPort" key string
	call	InitFileReadInteger	; Read the integer value from the .ini file
	jnc	havePort		; If read was successful (no carry), jump
	mov	ax, RAWTCP_DEFAULT_PORT	; Otherwise, use the default port value
	EC < WARNING RAWTCP_CONFIG_PORT_DEFAULTED > ; Log a warning that we're using the default

havePort:
	mov	es:[RTC_cfgPort], ax	; Store the port value in our config block
	tst	ax			; Check if the port value is non-zero
	jz	readHost		; If zero, it's not valid, so skip setting the flag
	or	es:[RTC_cfgFlags], mask RCF_PORT_VALID ; Mark the port as valid in the flags

readHost:
	;
	; Read rawTcpHost (dotted IPv4). Use a temporary block then copy.
	;
	mov	cx, dgroup		; Set CX to dgroup
	mov	dx, offset rawTcpHostKeyString ; Point DX to the "rawTcpHost" key string
	clr	bp			; BP must be zero for InitFileReadString
	call	InitFileReadString	; Read the host string from the .ini file
	jnc	haveHostString		; If successful, continue
	EC < WARNING RAWTCP_CONFIG_HOST_MISSING > ; Log a warning if the host key is missing
	jmp	unlockConfig		; Skip to cleanup

haveHostString:
					; The handle for the temp string block is in BX
	push	bx			; Save the handle of the temporary string block
	call	MemLock			; Lock the block to get its address in AX:0
	mov	ds, ax			; Point DS to the temporary string block
	clr	si			; Clear SI to start reading from the beginning of the string

	mov	di, offset RTC_cfgHostString ; Set DI to the destination buffer in our config block
	mov	cx, MAX_IP_DECIMAL_ADDR_LENGTH_ZT ; Set CX to the max length to copy

copyHost:
	lodsb				; Load a byte from DS:SI into AL, and increment SI
	mov	es:[di], al		; Store the byte in the config block at ES:DI
	inc	di			; Increment the destination pointer
	cmp	al, 0			; Was this the null terminator?
	je	parseHost		; If so, we're done copying
	loop	copyHost		; Loop until CX is zero
	mov	byte ptr es:[di-1], 0	; Ensure the string is null-terminated if it was too long

parseHost:
	;
	; Parse and validate dotted-quad IP address.
	;
	mov	ax, es			; Point DS to our config block (where ES is pointing)
	mov	ds, ax
	mov	si, offset RTC_cfgHostString ; SI points to the IP string to be parsed
	mov	di, offset RTC_cfgIPAddr ; DI points to the destination for the binary IP
	call	RawTcpIpParseIPv4		; Call the parsing routine
	jc	hostInvalid		; If carry is set, the IP was invalid
	cmp	byte ptr es:[RTC_cfgHostString], 0 ; Check if the source string was empty
	je	hostInvalid		; If so, treat as invalid
	or	es:[RTC_cfgFlags], mask RCF_HOST_VALID ; Mark the host as valid
	test	es:[RTC_cfgFlags], mask RCF_PORT_VALID ; Check if the port was also marked as valid
	jz	portInvalid		; If not, the configuration is incomplete
	jmp	unlockHost		; Both are valid, proceed to cleanup

hostInvalid:
	EC < WARNING RAWTCP_CONFIG_HOST_INVALID > ; Log that the host string is not a valid IP
	jmp	unlockHost

portInvalid:
	EC < WARNING RAWTCP_CONFIG_PORT_INVALID > ; Log that the port is invalid (e.g., 0)

unlockHost:
	pop	bx			; Restore the handle to the temporary host string block
	call	MemUnlock		; Unlock it
	call	MemFree			; And free it

unlockConfig:
	push	ds			; Save DS
	mov	ax, dgroup		; Point DS to our data segment
	mov	ds, ax
	mov	bx, ds:[rawTcpConfigH]	; Get the handle to our main config block
	pop	ds			; Restore DS
	call	MemUnlock		; Unlock the main config block
	jmp	done			; Jump to the end

; MemAlloc failed; restore stack and exit
doneRestore:
	pop	si			; Restore SI and DS from the stack
	pop	ds

done:
	.leave				; Restore stack frame
	ret				; Return
RawTcpIpLoadOptions	endp

;------------------------------------------------------------------------------
; Driver entry points
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpNull
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	No-op routine for unsupported functions.

CALLED BY:	various driver entry points
RETURN:		carry clear

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpNull	proc	near
	clc
	ret
RawTcpIpNull	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpExit
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Free cached configuration block, if present.

CALLED BY:	DR_EXIT

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpExit	proc	near
	uses	bx

	.enter
	mov	bx, ds:[rawTcpConfigH]	; Load the handle for the configuration block
	tst	bx			; Check if the handle is valid (non-zero)
	jz	done			; If it's zero, there's nothing to free, so exit
	call	MemFree			; Free the memory block associated with the handle in BX
	clr	ds:[rawTcpConfigH]	; Clear the global handle variable to mark it as freed

	done:
	clc				; Clear carry flag to indicate success

	.leave
	ret
RawTcpIpExit	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpGetDeviceMap
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Return no physical device map.

CALLED BY:	DR_STREAM_GET_DEVICE_MAP
RETURN:		ax = 0

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpGetDeviceMap	proc	near
	clr	ax
	clc
	ret
RawTcpIpGetDeviceMap	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpSetNotify
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Notification stub (no async events reported).

CALLED BY:	DR_STREAM_SET_NOTIFY

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpSetNotify	proc	near
	clc
	ret
RawTcpIpSetNotify	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpGetError
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	No stored error; return 0.

CALLED BY:	DR_STREAM_GET_ERROR

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpGetError	proc	near
	clr	ax
	clc
	ret
RawTcpIpGetError	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpSetError
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Ignore error postings.

CALLED BY:	DR_STREAM_SET_ERROR

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpSetError	proc	near
	clc
	ret
RawTcpIpSetError	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpReadUnsupported
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	RawTcpIp is write-only; read operations are unsupported.

CALLED BY:	DR_STREAM_READ, DR_STREAM_READ_BYTE
RETURN:		carry set, ax = STREAM_CLOSED

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpReadUnsupported	proc	near
	mov	ax, STREAM_CLOSED
	stc
	ret
RawTcpIpReadUnsupported	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpWriteByte
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Write a single byte by delegating to RawTcpIpWrite.

CALLED BY:	DR_STREAM_WRITE_BYTE

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpWriteByte	proc	near
	push	ds			; Save caller's registers
	push	si
	push	cx

	sub	sp, 2			; Allocate 2 bytes on the stack for the character
	mov	si, sp			; Point SI to the allocated stack space
	mov	ss:[si], cl		; Store the character (passed in CL) onto the stack

	segmov	ds, ss			; Point DS:SI to the character on the stack
	segmov	es, ds
	mov	si, sp			; Set SI to the source buffer (the character on the stack)
	mov	cx, 1			; Set CX to 1, as we are writing a single byte
	call	RawTcpIpWrite		; Call the underlying write routine

	mov	cx, ax			; Temporarily save the return value (bytes written) from AX
	lahf				; Load flags (especially carry) into AH to preserve them
	add	sp, 2			; Deallocate the 2 bytes from the stack
	sahf				; Restore the flags from AH
	mov	ax, cx			; Restore the return value into AX

	pop	cx			; Restore caller's registers
	pop	si
	pop	ds
	ret
RawTcpIpWriteByte	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpOpen
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
RawTcpIpOpen	proc	near
	uses	ax,cx,dx,si,di,bp,es
	.enter

	push	ds			; Save caller's data segment
	mov	bx, ds:[rawTcpConfigH]	; Get the handle to the global configuration block
	tst	bx			; Check if the configuration has been loaded
	jnz	haveConfig		; If yes, proceed
	EC < WARNING RAWTCP_OPEN_NO_CONFIG > ; Log an error if no config is found
	jmp	configError		; Jump to the error handling routine

haveConfig:
	mov	dx, bx			; Temporarily save the config handle in DX
	call	MemLock			; Lock the config block to get its segment address
	mov	es, ax			; Place the config block's segment in ES

	test	es:[RTC_cfgFlags], mask RCF_HOST_VALID ; Check if the host was validated in config
	jnz	hostValid		; If so, continue
	EC < WARNING RAWTCP_OPEN_CONFIG_INVALID > ; Log error if config is not valid
	jmp	configUnlockError	; Jump to cleanup and error handling

hostValid:
	test	es:[RTC_cfgFlags], mask RCF_PORT_VALID ; Check if the port was validated in config
	jnz	portValid		; If so, continue
	EC < WARNING RAWTCP_OPEN_CONFIG_INVALID > ; Log error if config is not valid
	jmp	configUnlockError	; Jump to cleanup and error handling
portValid:

	;
	; Allocate context for this open. This context is specific to this stream instance.
	;
	mov	ax, size RawTcpIpContext	; Get the size of the context structure
	mov	cx, ALLOC_DYNAMIC_NO_ERR_LOCK or (mask HAF_ZERO_INIT shl 8) or mask HF_SHARABLE
	call	MemAlloc		; Allocate the context block
	jnc	contextAllocOk		; If successful, continue
	EC < WARNING RAWTCP_OPEN_CONTEXT_ALLOC_FAILED >
	jmp	configUnlockError	; Jump to cleanup on failure

contextAllocOk:
	mov	bp, bx			; Store the new context handle in BP. BP is now our instance handle.
	mov	ds, ax			; Point DS to the new context segment for easy access

	; Initialize fields in the new context block
	mov	ds:[RTC_socket], 0
	mov	ds:[RTC_connected], 0
	mov	ax, es:[RTC_cfgPort]	; Get port from config block (in ES)
	mov	ds:[RTC_port], ax	; Store port in context block (in DS)
	mov	ds:[RTC_hostP], offset RTC_hostString ; Set internal pointer to host string
	clr	ds:[RTC_error]		; Clear the error field

	;
	; Copy IP address and host string from the global config block into our local context.
	;
	push	ds			; Swap DS (context) and ES (config) for movsb
	push	es
	mov	ax, ds
	mov	cx, es
	mov	ds, cx
	mov	es, ax

	lea	si, [RTC_cfgIPAddr]	; DS:SI = source (config block's IP address)
	lea	di, [RTC_ipAddr]	; ES:DI = destination (context block's IP address)
	mov	cx, size IPAddr
	rep	movsb			; Copy the bytes

	lea	si, [RTC_cfgHostString]	; DS:SI = source (config block's host string)
	lea	di, [RTC_hostString]	; ES:DI = destination (context block's host string)
	mov	cx, MAX_IP_DECIMAL_ADDR_LENGTH_ZT
	rep	movsb			; Copy the string

	pop	es			; Restore DS and ES
	pop	ds

	mov	bx, dx			; Restore config handle from DX
	call	MemUnlock		; Unlock the global config block

	;
	; Retry socket open/connect a few times.
	;
	mov	cx, RAWTCP_RETRY_COUNT	; Initialize retry counter
openRetry:
	mov	ax, SDT_STREAM		; Specify a stream socket type
	call	SocketCreate		; Attempt to create the socket
	jnc	createOk		; If successful (no carry), continue
	EC < WARNING RAWTCP_OPEN_SOCKET_CREATE_FAILED >
	jmp	retryDelay		; If failed, go to retry logic

createOk:
	mov	ds:[RTC_socket], bx	; Store the new socket handle in our context

	;
	; Build the socket address structure on the stack for the connect call.
	;
	push	ds, si, di, cx		; Save registers
	mov	ax, size RawTcpIpSocketAddress
	sub	sp, ax			; Allocate space on the stack for the address struct
	mov	di, sp			; Point DI to the start of the struct
	segmov	es, ss			; Point ES to the stack segment to fill the struct

	; Fill in the SocketAddress structure fields
	mov	ax, ds:[RTC_port]
	mov	es:[di].RTSA_socketAddress.SA_port.SP_port, ax
	mov	es:[di].RTSA_socketAddress.SA_port.SP_manuf, MANUFACTURER_ID_SOCKET_16BIT_PORT
	mov	es:[di].RTSA_socketAddress.SA_domainSize, RAWTCP_TCP_DOMAIN_LENGTH
	mov	es:[di].RTSA_socketAddress.SA_domain.offset, offset rawTcpTcpDomainString
	mov	ax, dgroup
	mov	es:[di].RTSA_socketAddress.SA_domain.segment, ax
	mov	es:[di].RTSA_socketAddress.SA_addressSize, size word + IP_ADDR_SIZE

	; Copy the binary IP address into the address structure
	lea	di, es:[di].RTSA_socketAddress.SA_address
	mov	{word} es:[di], 0	; ESACA_linkSize (not used for IP)
	lea	si, ds:[RTC_ipAddr]	; Point SI to the IP address in our context
	add	di, size word		; Move DI past the linkSize field
	mov	cx, size IPAddr
	rep	movsb			; Copy the IP address

	; Make the connect call
	mov	cx, ss			; CX:DX points to the address struct on the stack
	mov	dx, sp
	push	bp			; Save our context handle (BP)
	mov	bp, RAWTCP_CONNECT_TIMEOUT_TICKS ; Load timeout value into BP
	call	SocketConnect		; Attempt to connect
	pop	bp			; Restore context handle

	add	sp, size RawTcpIpSocketAddress ; Clean up stack space for address struct
	pop	ds, si, di, cx		; Restore registers

	jc	connectFail		; If connect failed (carry set), handle failure

	; --- Connection Successful ---
	call	RawTcpIpSetSocketOptions	; Set socket to non-blocking, etc.
	mov	ds:[RTC_connected], TRUE ; Mark as connected in our context
	mov	bx, bp			; Get our context handle into BX (the return value)
	call	MemUnlock		; Unlock the context block
	mov	bx, bp			; Set return value BX again (just in case)
	clc				; Clear carry to indicate success
	jmp	done

connectFail:
	EC < WARNING RAWTCP_OPEN_SOCKET_CONNECT_FAILED >
	call	SocketClose		; Close the failed socket
	jmp	retryDelay		; Go to the retry/delay logic

retryDelay:
	clr	ds:[RTC_socket]		; Clear the socket handle in our context
	dec	cx			; Decrement the retry counter
	jz	openFail		; If out of retries, fail completely
	mov	ax, RAWTCP_RETRY_DELAY_TICKS ; Load delay time
	call	TimerSleep		; Wait before trying again
	jmp	openRetry		; Loop back to try creating a socket again

openFail:
	mov	bx, bp			; Get our context handle
	call	MemUnlock		; Unlock the context block
	mov	bx, bp			; Get handle again for MemFree
	call	MemFree			; Free the context block we allocated

configError:
	mov	ax, STREAM_NO_DEVICE	; Set error code for no config
	stc				; Set carry to indicate error
	jmp	done

configUnlockError:
	mov	bx, dx			; Get config handle from saved DX
	call	MemUnlock		; Unlock the global config block
	mov	ax, STREAM_NO_DEVICE	; Set error code
	stc				; Set carry to indicate error
done:
	pop	ds			; Restore caller's DS

	.leave
	ret
RawTcpIpOpen	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpWrite
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Send data to the connected socket.

CALLED BY:	DR_STREAM_WRITE
PASS:		es:si	= buffer
		cx	= byte count
		bx	= context handle
RETURN:		carry clear + ax = bytes written on success
		carry set + ax = STREAM_CLOSED on failure

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpWrite	proc	near
	callerSeg	local	word
	contextSeg	local	word
	contextHandle	local	word
	driverSeg	local	word
	tempBufferH	local	word
	requestedCount	local	word
	socketH		local	word
	uses	ax,dx,bp,es
	.enter

	;
	; store variables
	;
	mov	ss:[driverSeg], ds		; Store the driver's data segment
	mov	ss:[contextHandle], bx		; Store the context handle passed in BX
	mov	ss:[requestedCount], cx		; Store the number of bytes to write

	;
	; check context handle, lock if exists
	;
	tst	bx				; Check if the context handle is null
	jnz	short haveHandle		; If not null, proceed
	jmp	invalidHandle			; Otherwise, jump to error handler

haveHandle:
	mov	ss:[callerSeg], es		; Store the caller's segment
	push	ds				; Preserve DS
	call	MemLock				; Lock the context block, handle is in BX
	pop	ds				; Restore DS
	tst	ax				; Check if MemLock succeeded (returns segment in AX)
	jnz	short haveLock			; If successful (AX != 0), proceed
	jmp	lockFailed			; Otherwise, jump to error handler

haveLock:
	;
	; store context
	;
	mov	es, ax				; Point ES to the locked context block
	mov	ss:[contextSeg], ax		; Save the context segment

	;
	; Check socket
	;
	tst	es:[RTC_connected]		; Check if the 'connected' flag is set in the context
	jnz	short haveConnection		; If connected, proceed
	jmp	notConnected			; Otherwise, jump to error handler

haveConnection:
	mov	bx, es:[RTC_socket]		; Get the socket handle from the context
	tst	bx				; Check if the socket handle is valid (non-zero)
	jnz	short haveSocket		; If valid, proceed
	jmp	notConnected			; Otherwise, treat as not connected

haveSocket:
	mov	ss:[socketH], bx		; Store the socket handle

	;
	; Allocate temp buffer
	;
	mov	ds, ss:[driverSeg]		; Set DS to the driver's segment for memory allocation
	mov	ax, ss:[requestedCount]		; Set AX to the number of bytes to allocate
	mov	cx, ALLOC_DYNAMIC_NO_ERR or (mask HAF_ZERO_INIT shl 8) ; Set allocation flags (dynamic, no error code, zero-init)
	call	MemAlloc			; Allocate the temporary buffer
	jnc	short allocOk			; If allocation succeeded (no carry), proceed
	jmp	allocFailed			; Otherwise, jump to error handler

allocOk:
	;
	; Lock temp buffer
	;
	mov	ss:[tempBufferH], bx		; Store the handle to the temporary buffer
	push	bx				; Preserve the handle on the stack
	call	MemLock				; Lock the temporary buffer
	pop	bx				; Restore the handle
	tst	ax				; Check if the lock was successful (AX != 0)
	jz	tempLockFailed			; If it failed, jump to cleanup

	;
	; Copy data to temp buffer, as an AssertCheck
	; in SocketSend always expects a handle based
	; far pointer in EC builds...
	;
	push	es				; Preserve ES (pointing to context)
	mov	es, ax				; Point ES to the newly locked temp buffer (destination)
	mov	ds, ss:[callerSeg]		; Point DS to the caller's data (source)
	mov	di, 0				; Set destination index to start of buffer
	mov	cx, ss:[requestedCount]		; Set CX to the number of bytes to copy
	rep	movsb				; Copy the data from DS:[SI] to ES:[DI]
	pop	es				; Restore ES

	;
	; Setup for SocketSend
	;
	mov	ds, ax				; Point DS to the temp buffer containing the data
	clr	si				; Set source index to start of buffer
	mov	cx, ss:[requestedCount]		; Set CX to the number of bytes to send
	clr	ax				; Clear AX (parameter for SocketSend)

	;
	; Send
	;
	mov	bx, ss:[socketH]		; Load the socket handle into BX
	call	SocketSend			; Send the data

	;
	; clean up temp buffer
	;
	pushf					; Save flags (to preserve carry flag from SocketSend)
	mov	ds, ss:[driverSeg]		; Set DS to the driver's segment
	mov	bx, ss:[tempBufferH]		; Get handle to temporary buffer
	call	MemUnlock			; Unlock the buffer
	call	MemFree				; Free the buffer
	popf					; Restore flags
	jc	sendError			; If carry is set (send error), go to error handler

	;
	; prepare return values
	;
	mov	ax, ss:[requestedCount]		; Set AX to number of bytes requested (and sent)
	mov	cx, ss:[requestedCount]		; Set CX to number of bytes requested (and sent)
	clc					; Clear carry to indicate success
	jmp	done				; And exit

tempLockFailed:
	mov	ds, ss:[driverSeg]		; Set DS to the driver's segment
	mov	bx, ss:[tempBufferH]		; Get handle to temporary buffer
	call	MemFree				; Free the allocated memory since lock failed
	jmp	sendError			; Go to the send error handler

allocFailed:
	mov	ax, STREAM_CLOSED		; Set return code to indicate stream is closed
	clr	cx				; Clear CX
	stc					; Set carry flag to indicate an error
	jmp	done				; Go to final cleanup

sendError:
	EC < 	WARNING RAWTCP_WRITE_SEND_FAILED >
	mov	ds, ss:[driverSeg]		; Set DS to driver's segment
	mov	es, ss:[contextSeg]		; Point ES to the connection's context
	mov	bx, es:[RTC_socket]		; Get the socket handle from the context
	tst	bx				; Check if the socket handle is valid
	jz	skipClose			; If not, skip closing it
	call	SocketClose			; Close the socket
skipClose:
	EC < 	WARNING RAWTCP_WRITE_SOCKET_HANDLE_ZERO >
	clr	es:[RTC_socket]			; Clear the socket handle in the context
	clr	es:[RTC_connected]		; Clear the connected flag in the context
	mov	ax, STREAM_CLOSED		; Set return code to indicate stream is closed
	clr	cx				; Clear CX
	stc					; Set carry flag to indicate an error
	jmp	done				; Go to final cleanup

notConnected:
	EC < 	WARNING RAWTCP_WRITE_NOT_CONNECTED >
	mov	ax, STREAM_CLOSED		; Set return code to indicate stream is closed
	clr	cx				; Clear CX
	stc					; Set carry flag to indicate an error

done:
	mov	ds, ss:[driverSeg]		; Restore the driver's data segment
	mov	bx, ss:[contextHandle]		; Load the context handle
	call	MemUnlock			; Unlock the context block
	.leave					; Restore stack frame
	ret					; Return to caller

invalidHandle:
	EC < 	WARNING RAWTCP_INVALID_HANDLE >
	mov	ax, STREAM_CLOSED		; Set return code for invalid handle
	clr	cx				; Clear CX
	stc					; Set carry flag to indicate an error
	.leave					; Restore stack frame
	ret					; Return to caller

lockFailed:
	EC < 	WARNING RAWTCP_LOCK_FAILED >
	mov	ax, STREAM_CLOSED		; Set return code for lock failure
	clr	cx				; Clear CX
	stc					; Set carry flag to indicate an error
	.leave					; Restore stack frame
	ret					; Return to caller

RawTcpIpWrite	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpClose
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Close the socket and free the context block.

CALLED BY:	DR_STREAM_CLOSE
PASS:		ax	= STREAM_LINGER or STREAM_DISCARD (ignored)
		bx	= context handle
RETURN:		carry clear

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpClose	proc	near
	uses	ax,di,es
	.enter

	mov	di, bx			; Save the value of bx in di
	tst	bx			; Test if bx is zero
	jz	done			; If bx is zero, jump to the 'done' label

	call	MemLock			; Lock the memory block pointed to by bx, returns handle in ax
	mov	es, ax			; Move the segment address from ax to es

	mov	bx, es:[RTC_socket]	; Get the socket handle from the RawTcpIpData structure
	tst	bx			; Test if the socket handle is zero
	jnz	closeSocket		; If it's not zero, jump to 'closeSocket'
	EC < WARNING RAWTCP_CLOSE_WITHOUT_SOCKET > ; Log a warning if trying to close a non-existent socket
	jmp	clearState		; Jump to 'clearState'
closeSocket:
	call	SocketClose		; Close the socket

clearState:
	clr	es:[RTC_socket]		; Clear the socket handle in the RawTcpIpData structure
	clr	es:[RTC_connected]	; Clear the connected flag
	clr	es:[RTC_error]		; Clear the error status

	mov	bx, di			; Restore the original memory block handle from di to bx
	call	MemUnlock		; Unlock the memory block
	mov	bx, di			; Restore the original memory block handle from di to bx again
	call	MemFree			; Free the memory block

	done:
	clc				; Clear the carry flag to indicate success
	.leave				; Macro to restore the stack frame
	ret				; Return from the subroutine
RawTcpIpClose	endp

;------------------------------------------------------------------------------
; Helpers
;------------------------------------------------------------------------------

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpSetSocketOptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Set socket buffer sizes and boolean options.

CALLED BY:	RawTcpIpOpen
PASS:		bx	= socket handle
RETURN:		nothing

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpSetSocketOptions	proc	near
	uses	ax,cx
	.enter

	mov	ax, SO_SEND_BUF			; Set option to configure send buffer size
	mov	cx, RAWTCP_SEND_BUFFER_SIZE	; Set the send buffer size value
	call	SocketSetSocketOption		; Call the function to set the socket option

	mov	ax, SO_RECV_BUF			; Set option to configure receive buffer size
	mov	cx, RAWTCP_RECV_BUFFER_SIZE	; Set the receive buffer size value
	call	SocketSetSocketOption		; Call the function to set the socket option

	mov	ax, SO_NODELAY			; Set option to disable Nagle's algorithm (TCP_NODELAY)
	mov	cx, TRUE			; Enable the option
	call	SocketSetSocketOption		; Call the function to set the socket option

	mov	ax, SO_LINGER			; Set option to configure socket linger behavior
	mov	cx, FALSE			; Disable lingering (don't wait for pending data on close)
	call	SocketSetSocketOption		; Call the function to set the socket option

	.leave
	ret
RawTcpIpSetSocketOptions	endp

COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		RawTcpIpParseIPv4
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SYNOPSIS:	Parse dotted-quad IPv4 string into IPAddr.

CALLED BY:	RawTcpIpLoadOptions
PASS:		ds:si	= null-terminated string
		es:di	= IPAddr output buffer
RETURN:		carry clear if valid; IPAddr written
		carry set if invalid format

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
RawTcpIpParseIPv4	proc	near
	uses	ax,bx,cx,dx,si,di
	.enter

	clr	cl				; Clear the octet counter (macro for xor cl, cl).

parseOctet:
	xor	bx, bx				; Clear bx to accumulate the octet's value.
	clr	ch				; Clear the digit counter for this octet (macro for xor ch, ch).

digitLoop:
	lodsb					; Load a byte from SI into AL, then increment SI.
	cmp	al, '0'				; Compare the character with '0'.
	jb	endDigits			; If it's below '0', it's not a digit.
	cmp	al, '9'				; Compare the character with '9'.
	ja	endDigits			; If it's above '9', it's not a digit.
	inc	ch				; Increment the count of digits found for this octet.
	mov	ah, 0				; Clear the upper byte of AX to work with AL alone.
	sub	al, '0'				; Convert ASCII digit to its integer value (e.g., '5' -> 5).
	mov	dx, ax				; Store the single digit's value in DX.
	mov	ax, bx				; Move the current accumulated value into AX for calculation.
	shl	ax, 1				; Multiply AX by 2 (AX = old_bx * 2).
	mov	bx, ax				; Save the intermediate result in BX.
	shl	ax, 1				; Multiply AX by 2 again (AX = old_bx * 4).
	shl	ax, 1				; Multiply AX by 2 again (AX = old_bx * 8).
	add	ax, bx				; Add the intermediate result (AX = (old_bx * 8) + (old_bx * 2) = old_bx * 10).
	mov	bx, ax				; Store the new total (old_bx * 10) back in BX.
	add	bx, dx				; Add the new digit to the total (BX = (old_bx * 10) + new_digit).
	cmp	bx, 255				; Check if the octet value exceeds 255.
	ja	invalid				; If so, the IP address is invalid.
	jmp	digitLoop			; Loop to process the next character.

endDigits:
	cmp	ch, 0				; Check if any digits were parsed for this octet.
	je	invalid				; If not (e.g. an empty octet), it's invalid.
	mov	es:[di], bl			; Store the completed octet value (from BL) into the destination buffer.
	inc	di				; Increment the destination pointer.
	inc	cl				; Increment the total count of parsed octets.
	cmp	al, '.'				; Was the character that ended the loop a period?
	je	needMore			; If yes, we need to parse another octet.
	cmp	al, 0				; Was it the null terminator (end of string)?
	je	maybeDone			; If yes, we might be done.
	jmp	invalid				; Otherwise, it's an invalid character.

needMore:
	cmp	cl, 4				; Have we already parsed 4 octets?
	jae	invalid				; If yes, another octet is invalid (e.g. "1.2.3.4.").
	jmp	parseOctet			; Go back to parse the next octet.

maybeDone:
	cmp	cl, 4				; Did we parse exactly 4 octets?
	jne	invalid				; If not, the IP address is incomplete or too long.
	clc					; Clear the carry flag to signal success.
	jmp	parseDone			; Jump to the cleanup and return.

invalid:
	EC < WARNING RAWTCP_PARSE_IPV4_INVALID >; Log a warning for an invalid IPv4 string.
	stc					; Set the carry flag to signal an error.

parseDone:
	.leave					; Restore stack frame (mov sp, bp; pop bp).
	ret					; Return to caller (carry flag indicates success/failure).
RawTcpIpParseIPv4	endp

Resident	ends
