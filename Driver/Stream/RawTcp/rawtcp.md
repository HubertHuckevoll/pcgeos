These are the instructions to create RawTcp - a raw TCP (9100) stream driver for the "JetDirect protocol" (sending PS data created by a printer driver to a TCP/IP host/port) that can be used as a PPT_CUSTOM port.

### Ground rules & constraints (must follow)
- No spooler core change required for the first working version.
- Use existing stream driver pattern (Netstr as a template).
- Use Library/Socket API (not socket drivers directly).
- INI‑only configuration is sufficient initially.
- Follow GEOS style:
    - This is a driver and implemented in ASM / ESP
    - formatting: use tabs aligned to local code
    - Small buffers (≤8 KB preferred), if more is needed, look into hugelmem.asm / hugelmem.def
    - No globals in libraries, create a per‑open context struct in dgroup or segment:
        - socket handle
        - resolved address (if cached)
        - connection state flag
        - pointer/offset to host string, port
        - optional error state


Document the exact error codes to return for parse errors (missing host/port, invalid port), network connect failures, and send/close errors. Reference existing conventions in `Driver/Stream/Netstr/netstrMain.asm` or `Driver/Stream/Serial/serialMain.asm`, and align with spooler errors like `PERROR_NETWORK_ERR` where appropriate.

### Architecture overview (what you must deliver)

- .gp for stream driver in Driver/Stream/RawTcp/
- RawTcpStrategy implementing all required entry points
- STREAM_ESC_LOAD_OPTIONS parsing config
- TCP socket open/write/close using Library/Socket APIs
- Proper error returns (matching stream driver conventions)

### Spooler integration

Each printer driver’s PrinterInfo includes a PrinterConnections bitfield that advertises which connection types it supports (serial, parallel, file, custom, etc.). The driver info resources set these flags (e.g., many drivers set RC_RS232C and/or CC_CENTRONICS, while the host/PS/fax entries set CC_CUSTOM). That’s the data the preferences UI uses to decide which port choices are valid for a given printer.
(Examples in Driver/Printer/*/*Info.asm, and the PrinterConnections definition in CInclude/Internal/printDr.h.)

The spool UI logic parses the printer’s port INI string and only recognizes four prefixes: "LP" (parallel), "CO" (serial), "CU" (custom), and "UN" (unknown). The UI only exposes LPT/COM/Unknown choices; “Custom” isn’t surfaced as a selectable UI option even though the backend supports it.
This is visible in Library/Spool/UI/uiPrintControl.asm:
    portTable maps "LP"→PPT_PARALLEL, "CO"→PPT_SERIAL, "CU"→PPT_CUSTOM, "UN"→PPT_NOTHING.
    PrinterGetPortInfo reads the port key from the printer’s INI category and maps it via that table.
    For PPT_CUSTOM, it calls PrinterGetCustomPortData to load customPortData (also from the printer’s INI category).

So CUSTOM is supported, but typically set by installation logic or manual INI edits, not via the port dropdown UI.

So we need to Change the PScript driver in Driver / Printer to hold an entry that advertises CC_CUSTOM in its driver’s PrinterInfo, so we can later set printer’s INI entry to:

```
[<printer category>]
port = CU
portDriver = rawtcp.geo
```

This way the spooler will treat it as a custom port and load our stream driver — even though the Preferences UI doesn’t provide a “Custom” option in the port list.

Relevant code pointers
    Port string → port type mapping: Library/Spool/UI/uiPrintControl.asm (portTable / PrinterGetPortInfo)
    Custom port INI data: Library/Spool/UI/uiPrintControl.asm (PrinterGetCustomPortData, key "customPortData")
    Driver connection flags: CInclude/Internal/printDr.h (PrinterConnections)
    Examples of CC_CUSTOM: Driver/Printer/PScript/hostPrinterInfo.asm, Driver/Printer/Fax/*Info.asm











PrinterConnections record — what it is and how it relates to ports

PrinterConnections is a bitfield in the printer’s info resource that advertises which connection types a specific printer driver supports. It’s defined in CInclude/Internal/printDr.h as a ByteFlags record, with one bit for each connection family:

    IEEE488Connection

    CustomConnection

    SCSIConnection

    RS232CConnection

    CentronicsConnection

    FileConnection

    AppletalkConnection

Each driver’s DriverInfo.asm (or per-device *Info.asm) fills out the PrinterInfo structure with these flags. That’s why some printers allow only LPT, others allow COM+LPT, some allow file, and a few allow CC_CUSTOM (e.g., fax, host/PS).

So this record is the printer driver’s declaration of supported connection types, and the UI uses that to decide which port choices are valid.

Definition reference: CInclude/Internal/printDr.h (the PrinterConnections record and its enum fields).






















### Build a new TCP/IP stream driver (core work)

#### Create rawtcp.gp in Driver/Stream/RawTcp/

For the .gp file clone Netstr’s structure:
- Use Driver/Stream/Netstr/netstr.gp as baseline.
- Ensure DriverType = STREAM.
- Export one strategy entrypoint, e.g. RawTcpStrategy.

Key requirements:
- The geode name must be unique.
- The driver must export DRIVER_TYPE_STREAM.

Define the exact library dependencies to add in `Driver/Stream/RawTcp/rawtcp.gp` (e.g., `library socket`, any resolver/net library if needed) and which `.def` files to include in the driver’s `.def` or `.asm`. Point to examples like `Driver/Stream/Netstr/netstr.def` and socket usage in `Appl/Test/WebServ/webserv.asm` for consistency.


#### Main ASM file structure

Base it on Driver/Stream/Netstr/netstrMain.asm.
Mandatory entry points to implement:

- DR_STREAM_OPEN
- DR_STREAM_WRITE
- DR_STREAM_CLOSE
- DR_STREAM_SET_NOTIFY (even if it’s a stub)
- STREAM_ESC_LOAD_OPTIONS

#### STREAM_ESC_LOAD_OPTIONS behavior

    The spooler passes the printer INI category (JP_printerName) to STREAM_ESC_LOAD_OPTIONS. This is already hard‑wired in Library/Spool/Process/processCustom.asm.

    Netstr’s STREAM_ESC_LOAD_OPTIONS (NetstreamLoadOptions) only reads INI keys (e.g., "queue") via InitFileReadString. It does not look at CPP_info at all.

    Implication for RawTcp: When implementing STREAM_ESC_LOAD_OPTIONS, it should read the INI category and parse any INI keys you decide to support (if any). It should not expect the 128‑byte CPP_info buffer there.
    Citations:

    Spooler call path uses printer name category for STREAM_ESC_LOAD_OPTIONS: Library/Spool/Process/processCustom.asm

    Netstr’s STREAM_ESC_LOAD_OPTIONS reads INI via InitFileReadString: Driver/Stream/Netstr/netstrMain.asm


✅ CPP_info is passed to DR_STREAM_OPEN

    After calling STREAM_ESC_LOAD_OPTIONS, the spooler allocates a block, copies CPP_info into it, and passes that to DR_STREAM_OPEN.
    Implication for RawTcp:
    If you want the customPortData text (tcpport host=... port=...) to be the driver’s main configuration, then the correct place to parse it is DR_STREAM_OPEN, not STREAM_ESC_LOAD_OPTIONS.
    Citation:

    Spooler copies CPP_info into a block and passes it to DR_STREAM_OPEN: Library/Spool/Process/processCustom.asm

    Command used: sed -n '40,140p' Library/Spool/Process/processCustom.asm

Practical guidance for RawTcp design
Option A (match existing behavior exactly)

    STREAM_ESC_LOAD_OPTIONS: read INI keys if you want optional defaults, but do not rely on it for required connection settings.

    DR_STREAM_OPEN: parse CPP_info for tcpport host=... port=... and validate.

This aligns with how the spooler calls drivers today. It also fits the Netstr precedent.






This is where you parse configuration. The input is the 128‑byte `customPortData` buffer (from `CPP_info`) which is treated as ASCII text. Required format:

* First token must be `tcpport`
* Everything may be case‑insensitive, including the rawtcp keyword and key names
* unknown keys and malformed values should be ignored and replaced with default values
* escape sequences are not allowed inside quoted values.
* Remaining tokens are `key=value`, separated by whitespace.
* Value forms:

  * Quoted string: `host="printer.example.com"`
  * Bracketed IPv6: `host=[2001:db8::1]`
  * Unquoted: `port=9100`

Defaults for timeout, retries, and keepalive must be given but are not configurable for now via INI, just use CONSTANTS.
Missing host or port should result in the driver returning an error.

Implement these steps:

3.3.1. **Copy and terminate input**

   * Copy the 128‑byte buffer into a local small buffer (<= 256 bytes) and ensure it is null‑terminated.
   * Strip trailing garbage (stop at first `0x00`).

3.3.2. **Tokenizer**

   * Implement a simple tokenizer that skips ASCII whitespace and returns the next token.
   * A token is either:

     * the first keyword (`tcpport`), or
     * a `key=value` pair, where `value` may include whitespace **only if quoted**.

3.3.3. **Parse first token**

   * Compare case‑insensitive against `tcpport`. If mismatch, return an error (carry set / error code).

3.3.4. **Parse key=value pairs**

   * Split each token at the first `=` into `key` and `value`.
   * Accept known keys: `host`, `port`, `timeout`, `keepalive`, `retries` (expandable list).
   * For `value`:

     * If it begins with `"` then consume until the matching `"` and allow embedded spaces and colons.
     * If it begins with `[` then consume until `]` (IPv6 literal).
     * Otherwise, read until whitespace.

3.3.5. **Store results**

   * Store `host` in a small fixed buffer (e.g., 128 bytes) in the per‑open context.
   * Store `port` as a numeric word (validate 1–65535).
   * Store optional numeric values (`timeout`, `keepalive`, `retries`) if present; otherwise use defaults.

3.3.6. **Validation**

   * `host` and `port` must be present; otherwise return error.
   * If value parsing fails (missing closing `"` or `]`, or non‑numeric `port`), return error.

3.3.7. **Error reporting**

    * Use the same error/return conventions as existing stream drivers in `Driver/Stream/Netstr/netstrMain.asm` and `Driver/Stream/Serial/serialMain.asm` (carry set, error code in AX).

    * Specify how RawTcp should handle host/port values that exceed the fixed buffers (e.g., reject with error). Include max lengths, behavior for unterminated quoted/IPv6 values, and what constitutes a parse failure vs. a recoverable ignore. Reference the `CPP_info` size limit and the proposed host buffer size.

3.3.8. **Document the format**

Add an extensive comment to the top of the relevant function that explains the format:
     * `customPortData = tcpport host="printer.example.com" port=9100 timeout=30`
     * `customPortData = tcpport host=[2001:db8::1] port=9100`

Reference points for style and patterns:

* `Driver/Stream/Netstr/netstrMain.asm` for stream driver layout and INI parsing.
* `Library/Socket` usage patterns in `Appl/Test/WebServ/webserv.asm` and `Library/DHCP/dhcpMain.asm` (for later socket open).


3.4 DR_STREAM_OPEN

    Ensure TCP/IP domain available

        Use socket library APIs (`Library/Socket`); see also WebServ, NewsRead and BBxBrow apps for usage patterns.

    Create socket

        SocketCreate(SDT_STREAM)

    Resolve host (if host is a name)

        SocketResolve or SocketCreateResolvedAddress

    Connect

        SocketConnect

    Configure

        SocketSetIntSocketOption for send/recv buffers (e.g., 8 KB)

Each print job should open/close a socket, no persistent connection. Implement a reconnect and retry pattern on socket failure for a small number of times (5). Document behavior in driver comments.

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

4. Wiring to spooler (INI + printer driver)

4.1 Enable Custom Port in printer driver

Printer drivers list connection types in:

    Include/Internal/printDr.def (PrinterConnections)

    Ensure PC_CUSTOM is enabled.

If driver already allows Custom, nothing to do.

5. Recommended reference files (exact path list)

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

6. Minimal “connect + send + close” flow (ASM style guide)

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



    Driver/Stream/Netstr/netstrMain.asm => good template.
    Library/Socket/* => socket API.
Inspect Appl/Test/WebServ/webserv.asm and Library/DHCP/dhcpMain.asm for socket call order and register usage. Choose the canonical call flow and document it in rawtcp driver comments.

