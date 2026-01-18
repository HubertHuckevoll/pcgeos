These are the instructions to create RawTcp - a raw TCP (9100) stream driver for the "JetDirect" protocol (sending printer data created by a printer driver unchanged to a TCP/IP host/port) that can be used as a "PPT_CUSTOM" port in the PC/GEOS spooler.

### Ground rules & constraints (must follow)
- No spooler core change required for the first working version.
- Use existing stream driver pattern (Netstr as a template).
- Use Library/Socket API (not socket drivers directly).
- INI‑only configuration is sufficient initially, no UI changes needed.
- Follow GEOS style:
    - This is a driver and implemented in ASM / ESP
    - formatting: use tabs aligned to local code
    - Small buffers (≤8 KB preferred), if more is needed, look into LMem, HugeLMem
    - No globals in libraries, create a per‑open context struct in a segment (MemHandle via MemAlloc/HAF_ZERO_INIT):
        - socket handle
        - IP4 address
        - connection state flag
        - pointer/offset to host string, port
        - optional error state
- Document behavior in driver comments very well.

### Architecture overview (what you must deliver)

- .gp for stream driver in Driver/Stream/RawTcp/
- RawTcpStrategy implementing all required entry points
- TCP socket open/write/close using Library/Socket APIs
- Proper error returns (matching stream driver conventions, see below)

### Create rawtcp.gp in Driver/Stream/RawTcp/

For the .gp file clone Netstr’s structure:
- Use Driver/Stream/Netstr/netstr.gp as baseline.
- Ensure DriverType = STREAM.
- Export one strategy entrypoint, e.g. RawTcpStrategy.

Key requirements:
name        rawtcp.drvr
longname    "RawTcp Stream Driver"
tokenchars  "ISTR"
tokenid     0

The driver must export DRIVER_TYPE_STREAM.

Define the exact library dependencies to add in `Driver/Stream/RawTcp/rawtcp.gp` (e.g., `library socket`) and which `.def` files to include in the driver’s `.def` or `.asm`. Point to examples like `Driver/Stream/Netstr/netstr.def` and socket usage in `Appl/Test/WebServ/webserv.asm` for consistency.

### Main ASM file structure

Base it on Driver/Stream/Netstr/netstrMain.asm.
Mandatory entry points to implement:

- DR_STREAM_OPEN
- DR_STREAM_WRITE
- DR_STREAM_CLOSE
- DR_STREAM_SET_NOTIFY (even if it’s a stub)
- STREAM_ESC_LOAD_OPTIONS

Note: Use socket library APIs (`Library/Socket`) but see also WebServ, NewsRead and BBxBrow apps for usage patterns.

### STREAM_ESC_LOAD_OPTIONS behavior

The spooler passes the printer INI category (JP_printerName) to STREAM_ESC_LOAD_OPTIONS. This is already hard‑wired in Library/Spool/Process/processCustom.asm.

Netstr’s STREAM_ESC_LOAD_OPTIONS (NetstreamLoadOptions) reads INI keys (e.g., "queue") via InitFileReadString.

Implication for RawTcp: When implementing STREAM_ESC_LOAD_OPTIONS, it should read the INI category and read the INI keys we need
and store them internally. Use "rawTcpHost" (e.g. "rawTcpHost=127.0.0.1") and "rawTcpPort" (e.g. "rawTcpPort=9100"), case sensivitive, as INI keys.

If rawTcpPort is not given assume port 9100. If rawTcpHost is missing or empty, hard-fail DR_STREAM_OPEN.

No IPv6 Support for now, just IP4 and port. Also, no host names allowed in rawTcpHost (so no resolver needed), just dotted-quad IPv4.

Defaults for timeout, retries, and keepalive must be given internally as constants, but are not (yet) configurable for now via INI.
Missing host or port should result in the driver returning an error if possible, otherwise fail silently.

Note: After calling STREAM_ESC_LOAD_OPTIONS, the spooler allocates a block, copies CPP_info into it, and passes that to DR_STREAM_OPEN. We ignore this mechanism completely, as we are using our own config reading via STREAM_ESC_LOAD_OPTIONS.

References:
Spooler call path uses printer name category for STREAM_ESC_LOAD_OPTIONS: Library/Spool/Process/processCustom.asm
Netstr’s STREAM_ESC_LOAD_OPTIONS reads INI via InitFileReadString: Driver/Stream/Netstr/netstrMain.asm

### DR_STREAM_OPEN

Each print job should open/close a socket, no persistent connection.

Here are some more socket defaults:
Send/recv buffer sizes
    Send buffer: 4 KB (4096)
    Recv buffer: 2 KB (2048)
    Rationale: printing is write-heavy; receive data is minimal/unused. 4 KB keeps memory small and avoids fragmentation while still reducing syscall frequency.

Socket options
    SO_NODELAY: ON (disable Nagle)
    Rationale: printer protocols often expect immediate flush; small blocks shouldn’t be delayed.

    SO_LINGER: OFF (or 0)
    Rationale: avoid blocking on close; spooler already controls job boundaries.

    Keepalive: OFF
    Rationale: you open/close per job, so keepalive adds overhead without benefit.

Timeouts
    Connect timeout: 10 seconds
    Enough for network/link bring-up without stalling the spooler too long.

    Send timeout: 10 seconds per send call
    Keep bounded to prevent hangs on dead printers.

    Recv timeout: not needed (driver doesn’t read). If required by API, set to SOCKET_NO_TIMEOUT or a short value like 5 seconds.

Implement a reconnect and retry pattern on socket failure for a small number of times (3, changeable via a CONSTANT). There should be a delay between attempts of 250ms.

Inputs: spooler calls DR_STREAM_OPEN after STREAM_ESC_LOAD_OPTIONS.
Outputs: carry clear on success; carry set + AX error on failure.

Flow (pseudo‑logic):
    Validate config loaded
        If host missing/empty → stc, ax = STREAM_NO_DEVICE, return.
        If port missing/invalid (0 or >65535) → stc, ax = STREAM_NO_DEVICE, return.
    Resolve host (if needed)
        If numeric IPv4 parse fails and resolver fails → stc, ax = STREAM_NO_DEVICE, return.
    Create socket
        If SocketCreate fails → stc, ax = STREAM_NO_DEVICE, return.
    Connect
        On SocketConnect failure → close socket (best effort), stc, ax = STREAM_NO_DEVICE, return.
    Set socket options (send/recv buffers, NODELAY, etc.)
        If any option fails → close socket, stc, ax = STREAM_NO_DEVICE, return.
        (If you want to be more tolerant, you can ignore option errors and continue.)
    Success
        Store socket handle in context.
        clc, ax = 0, return.

### DR_STREAM_WRITE

Inputs: ds:si buffer, cx count (standard stream driver params).
Outputs: carry clear and ax = bytes written (or cx updated, as per convention); carry set + AX error.

Flow:
    Check socket connected
        If not connected/invalid handle → stc, ax = STREAM_CLOSED, return.
    Send loop (handle partial sends)
        Call SocketSend.
        If send fails at any point →
            close socket (best effort), mark disconnected,
            stc, ax = STREAM_CLOSED, return.
    Success
        clc, ax = bytesSent, return.

### DR_STREAM_CLOSE

Inputs: ax = STREAM_LINGER or STREAM_DISCARD (standard).
Outputs: carry clear on success; carry set + AX error on failure (optional).

Flow:
    If no socket open
        clc, ax = 0, return.
    Close socket
        If SocketClose fails:
            mark disconnected anyway.
            For strict reporting: stc, ax = STREAM_CLOSED, return.
            For lenient close: ignore error and clc, ax = 0.
    Cleanup
        Clear context state (socket handle = 0, connected flag = 0).
        clc, ax = 0, return.

### DR_STREAM_SET_NOTIFY

Stream API expects notify support; implement minimal stub or pass to StreamStrategy if required.
See Driver/Stream/Parallel/parallelMain.asm for how they delegate.

### Error handling

Use only standard StreamError values (no driver‑specific enums), and no explicit DR_STREAM_SET_ERROR calls in v1.
StreamError mapping table:
Failure	Return (carry set, AX=StreamError)	Rationale
missing host	STREAM_NO_DEVICE	Mirrors “no port/device” in legacy drivers.
invalid host (empty or malformed)	STREAM_NO_DEVICE	Treat as no reachable device.
missing port	STREAM_NO_DEVICE	Same as missing device.
invalid port (0 or >65535)	STREAM_NO_DEVICE	Consistent with “port does not exist.”
resolve failure	STREAM_NO_DEVICE	Legacy callers interpret this as unreachable device.
connect failure	STREAM_NO_DEVICE	Same user-visible behavior as “cannot open port.”
send failure	STREAM_CLOSED	Aligns with “connection dropped” semantics.
close failure	STREAM_CLOSED (or ignore)	Close errors typically non-fatal; if returned, use STREAM_CLOSED.

DR_STREAM_SET_ERROR / PERROR mapping
Recommended for max compatibility:
    Do not call DR_STREAM_SET_ERROR from the driver in v1.
    Return StreamError in AX with carry set; let the spooler map it.
This matches how existing stream drivers behave and avoids introducing new UI behaviors.

Summary of error codes used
    Missing/invalid host/port, resolve fail, connect fail, option fail:
    => STREAM_NO_DEVICE

    Send fail, close fail:
    => STREAM_CLOSED

### Recommended reference files (exact path list)

Stream driver skeletons
    Driver/Stream/Netstr/netstrMain.asm
    Driver/Stream/Parallel/parallelMain.asm
    Driver/Stream/Serial/serialMain.asm

Spooler custom‑port flow
    Library/Spool/Process/processCustom.asm
    Library/Spool/UI/uiPrintControl.asm
    Include/Internal/spoolInt.def

Socket API
    Library/Socket/socketApi.asm
    Library/Socket/socketConnection.asm
    Library/Socket/socketPacket.asm

ASM socket usage examples
    Appl/Test/WebServ/webserv.asm
    Library/DHCP/dhcpMain.asm
    Library/Resolver/resolver.asm
    Library/Resolver/resolverComm.asm
