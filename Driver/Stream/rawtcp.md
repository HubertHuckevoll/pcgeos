“RAW TCP (9100)”

Below is a much more detailed, non‑redundant, implementation‑grade guide for an AI agent to build a TCP/IP stream driver, connect it to the spooler, and (optionally) add UI. Everything is based on static inspection and prior analysis; no code was executed.
TCP/IP Stream Driver + Spooler + UI: Exact Implementation Guide

Goal: A custom stream driver that sends printer data to a TCP/IP host/port, connects via PPT_CUSTOM, and optionally adds a TCP/IP options dialog in the printer UI.

0) Ground rules & constraints (must follow)

    No spooler core change required for the first working version.

    Use existing stream driver pattern (Netstr as a template).

    Use Library/Socket API (not socket drivers directly).

    INI‑only configuration is sufficient initially (customPortData or explicit keys).

    Follow GEOS style:

        ASM: tabs aligned to local code.

        GOC/C: 4 spaces, C89, variables at top.

        _pascal by default.

        Small buffers (≤8 KB preferred).

        No globals in libraries; use per‑instance context.

1) Architecture overview (exact data flow)

Printer setup (INI)
    ↓
Spooler UI (Custom port selected)
    - Loads customPortData into CPP_info
    ↓
Spooler process (processCustom.asm)
    - Loads custom stream driver geode
    - Calls STREAM_ESC_LOAD_OPTIONS (passes CPP_info)
    - Opens stream
    ↓
Your TCP/IP stream driver
    - Parses config
    - Opens TCP socket
    - Sends data on DR_STREAM_WRITE
    - Closes socket on DR_STREAM_CLOSE

Files involved:

    Include/Internal/spoolInt.def → defines PPT_CUSTOM + 128‑byte CPP_info

    Library/Spool/UI/uiPrintControl.asm → reads customPortData

    Library/Spool/Process/processCustom.asm → loads custom stream driver + calls escape

    Driver/Stream/Netstr/netstrMain.asm → good template

    Library/Socket/* → socket API

2) Spooler integration: exactly what is already provided
-   Port type wiring

    PPT_CUSTOM is already defined (Include/Internal/spoolInt.def).

    processCustom.asm loads the custom driver geode and calls STREAM_ESC_LOAD_OPTIONS, then DR_STREAM_OPEN.

-   Configuration input

    uiPrintControl.asm → PrinterGetCustomPortData

    Reads customPortData key from printer’s INI category and copies to CPP_info (128 bytes).

    This data is opaque to spooler: your driver interprets it.

Conclusion: You don’t need to change spooler to “connect” a TCP/IP driver. Just implement the custom stream driver and point to it in the printer’s config.

3) Build a new TCP/IP stream driver (core work)

3.1 Create driver directory + .gp

Location: Driver/Stream/TcpPort/

Create new .gp (clone Netstr’s structure):

    Use Driver/Stream/Netstr/netstr.gp as baseline.

    Ensure DriverType = STREAM.

    Export one strategy entrypoint, e.g. TcpPortStrategy.

Key requirements:

    The geode name must be unique.

    The driver must export DRIVER_TYPE_STREAM.

3.2 Main ASM file structure

Base it on Driver/Stream/Netstr/netstrMain.asm.
Mandatory entry points to implement:

    DR_STREAM_OPEN

    DR_STREAM_WRITE

    DR_STREAM_CLOSE

    DR_STREAM_SET_NOTIFY (even if it’s a stub)

    STREAM_ESC_LOAD_OPTIONS

Context storage

Create a per‑open context struct in dgroup or segment:

    socket handle

    resolved address (if cached)

    connection state flag

    pointer/offset to host string, port

    optional error state

Do not use large buffers; keep I/O in small chunks (≤ 8 KB).

3.3 STREAM_ESC_LOAD_OPTIONS behavior

This is where you parse configuration. The input is the 128‑byte `customPortData` buffer (from `CPP_info`) which is treated as ASCII text. Required format:

* First token must be `tcpport` (case‑insensitive).
* Remaining tokens are `key=value`, separated by whitespace.
* Value forms:

  * Quoted string: `host="printer.example.com"`
  * Bracketed IPv6: `host=[2001:db8::1]`
  * Unquoted: `port=9100`

Implement these steps:

1. **Copy and terminate input**

   * Copy the 128‑byte buffer into a local small buffer (<= 256 bytes) and ensure it is null‑terminated.
   * Strip trailing garbage (stop at first `0x00`).

2. **Tokenizer**

   * Implement a simple tokenizer that skips ASCII whitespace and returns the next token.
   * A token is either:

     * the first keyword (`tcpport`), or
     * a `key=value` pair, where `value` may include whitespace **only if quoted**.

3. **Parse first token**

   * Compare case‑insensitive against `tcpport`. If mismatch, return an error (carry set / error code).

4. **Parse key=value pairs**

   * Split each token at the first `=` into `key` and `value`.
   * Accept known keys: `host`, `port`, `timeout`, `keepalive`, `retries` (expandable list).
   * For `value`:

     * If it begins with `"` then consume until the matching `"` and allow embedded spaces and colons.
     * If it begins with `[` then consume until `]` (IPv6 literal).
     * Otherwise, read until whitespace.

5. **Store results**

   * Store `host` in a small fixed buffer (e.g., 128 bytes) in the per‑open context.
   * Store `port` as a numeric word (validate 1–65535).
   * Store optional numeric values (`timeout`, `keepalive`, `retries`) if present; otherwise use defaults.

6. **Validation**

   * `host` and `port` must be present; otherwise return error.
   * If value parsing fails (missing closing `"` or `]`, or non‑numeric `port`), return error.

7. **Error reporting**

   * Use the same error/return conventions as existing stream drivers in `Driver/Stream/Netstr/netstrMain.asm` and `Driver/Stream/Serial/serialMain.asm` (carry set, error code in AX).

8. **Document the format**

   * Update `TechDocs/Markdown/Tools/tini.md` in the printer device section with a full example:

     * `customPortData = tcpport host="printer.example.com" port=9100 timeout=30`
     * `customPortData = tcpport host=[2001:db8::1] port=9100`

Reference points for style and patterns:

* `Driver/Stream/Netstr/netstrMain.asm` for stream driver layout and INI parsing.
* `Library/Socket` usage patterns in `Appl/Test/WebServ/webserv.asm` and `Library/DHCP/dhcpMain.asm` (for later socket open).


3.4 DR_STREAM_OPEN

Steps (use socket library APIs; see WebServ/DHCP ASM patterns):

    Ensure TCP/IP domain available

        Use SocketOpenDomainMedium if needed (see Library/Resolver/resolver*.asm).

    Create socket

        SocketCreate(SDT_STREAM)

    Resolve host (if host is a name)

        SocketResolve or SocketCreateResolvedAddress

    Connect

        SocketConnect

    Configure

        SocketSetIntSocketOption for send/recv buffers (e.g., 8 KB)

If any step fails: return error in carry/AX (match style in existing stream drivers).
3.5 DR_STREAM_WRITE

    Input data buffer from spooler.

    Use SocketSend.

    Handle partial send (loop until count sent or error).

    Return count sent or error.

3.6 DR_STREAM_CLOSE

    SocketClose (or SocketCloseSend if required).

    Clear state.

    Release any memory handles.

3.7 DR_STREAM_SET_NOTIFY

    Stream API expects notify support; implement minimal stub or pass to StreamStrategy if required.

    See Driver/Stream/Parallel/parallelMain.asm for how they delegate.

4) Wiring to spooler (INI + printer driver)
4.1 Enable Custom Port in printer driver

Printer drivers list connection types in:

    Include/Internal/printDr.def (PrinterConnections)

    Ensure PC_CUSTOM is enabled.

If driver already allows Custom, nothing to do.
4.2 Add custom port data in INI

In printer’s INI category:

Option A: customPortData

customPortData = <binary blob>

(You’ll need a tool or helper to write raw binary; use in test builds.)

Option B: explicit keys

tcpHost = printer.example.com
tcpPort = 9100

5) Optional UI: TCP/IP options dialog (advanced)

If you want a UI similar to “Serial Port Options”:
5.1 Identify current serial options UI

    Library/Spool/UI/uiPrintControl.asm contains logic that enables/disables the serial options button.

    Look for the port‑type handling logic and follow its patterns.

5.2 Add TCP/IP UI objects

    Add a dialog with:

        Host field

        Port field

        Timeout field (optional)

5.3 Enable/disable TCP/IP options button

    Hook into the same port selection logic.

    If port type is PPT_CUSTOM, enable the TCP/IP dialog button.

5.4 Save settings to INI

    On dialog apply, write keys (tcpHost, tcpPort, tcpTimeout) in printer’s INI category.

    Alternatively, pack and write customPortData (harder for UI).

6) Recommended reference files (exact path list)

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

7) Minimal “connect + send + close” flow (ASM style guide)

From best references (WebServ + DHCP):

    Resolve:

        Use SocketResolve or SocketCreateResolvedAddress

    Create:

        SocketCreate(SDT_STREAM)

    Connect:

        SocketConnect

    Send:

        SocketSend with job data

    Close:

        SocketClose

Follow error handling patterns from webserv.asm or dhcpMain.asm.
8) What the AI agent must deliver (exact checklist)

- New driver directory Driver/Stream/TcpPort/
- .gp for stream driver
- TcpPortStrategy implementing all required entry points
- STREAM_ESC_LOAD_OPTIONS parsing config
- TCP socket open/write/close using Library/Socket APIs
- Proper error returns (matching stream driver conventions)
- INI key support or customPortData parsing
- (Optional) Printer UI dialog for TCP/IP settings

9) Why this works without spooler changes

    processCustom.asm is already designed to load custom stream drivers.

    customPortData is already passed into your driver.

    Port selection logic already allows “Custom.”

Your driver simply becomes the custom port’s stream handler.