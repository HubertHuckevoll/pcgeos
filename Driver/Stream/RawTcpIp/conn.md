
The raw TCP/IP (rawtcp) stream driver offers the capability to print via TCP/IP aka JetDirect protocol. Now I want to extend the spooler and the spooler UI to allow for selecting this stream driver as "port".

Here is what I currently do:

    set port = CU in GEOS.INI.
    Spooler maps "CU" => PPT_CUSTOM.
    InitCustomPort loads the stream driver via "portDriver" and calls DR_STREAM_OPEN.
    DR_PRINT_SET_STREAM passes the stream handle to the printer driver.

I must ensure that the printer driver declares CC_CUSTOM and the port driver is a proper stream driver, which works.

However, now I want to add a proper JetDirect / Raw TCP/IP printing PrinterConnection and PrinterPortType, so that JetDirect type of printing can be selected in the UI for a printer that supports it.

Here is what I found out so far.

1) PrinterConnections (driver capability flags)

Each printer driver’s PrinterInfo includes a PrinterConnections bitfield that advertises which connection types it supports (serial, parallel, file, custom, etc.). The driver info resources set these flags (e.g., many drivers set RC_RS232C and/or CC_CENTRONICS, while the host/PS/fax entries set CC_CUSTOM). That’s the data the preferences UI uses to decide which port choices are valid for a given printer.
(Examples in Driver/Printer/*/*Info.asm, and the PrinterConnections definition in CInclude/Internal/printDr.h.)

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


2) PrinterPortType (actual chosen port type for a job)

Values:

    PPT_SERIAL, PPT_PARALLEL, PPT_FILE, PPT_NOTHING, PPT_CUSTOM

This is the actual port selection stored in the job’s JobParameters (JP_portInfo.PPI_type). It’s what the spooler uses when it opens the port for a print job.

So:
    PrinterConnections = what the driver says it can do
    PrinterPortType = what the user/config actually picked


So I'm thinking. I guess I will have to add a PrinterConnections capability flag (like the existing RS232CConnection, CentronicsConnection, etc.):

    RawTCPIP as the bitfield name

    Enum values:

        TC_NO_RAWTCPIP / TC_RAWTCPIP


Then, for PrinterPortType (actual chosen port), to mirror the capability name:

    PPT_RAWTCPIP

Add a dedicated parameter block under PortParams:

    RawTcpipPortParams

    Fields like:

        address/hostname (string)

        port number (word)

Example names:

    TPP_hostName, TPP_port (TCP/IP-specific)


Relevant code pointers
    Port string → port type mapping: Library/Spool/UI/uiPrintControl.asm (portTable / PrinterGetPortInfo)
    Custom port INI data: Library/Spool/UI/uiPrintControl.asm (PrinterGetCustomPortData, key "customPortData")
    Driver connection flags: CInclude/Internal/printDr.h (PrinterConnections)
    Examples of CC_CUSTOM: Driver/Printer/PScript/hostPrinterInfo.asm, Driver/Printer/Fax/*Info.asm
    Definition reference: CInclude/Internal/printDr.h (the PrinterConnections record and its enum fields).
    CInclude/Internal/spoolInt.h (PrinterPortType)
    Library/Spool/UI/uiPrintControl.asm


Task 1:

**Headers/defs (types + enums):**

* `CInclude/Internal/spoolInt.h`

  * Add new enum value: `PPT_RAWTCPIP`.
  * Add `typedef struct` `RawTcpipPortParams`:

    * `SBCS: char RTPP_host[64];`
    * `DBCS: wchar RTPP_host[64];`
    * `word RTPP_port;`
  * Add `RawTcpipPortParams PP_rawtcpip;` to `PortParams` union.

* `Include/Internal/spoolInt.def`

  * Mirror `PPT_RAWTCPIP` in `PrinterPortType`.
  * Add `RawTcpipPortParams` struct with identical fields and size:

    * `RTPP_host` as `char[64]` (SBCS) / `wchar[64]` (DBCS).
    * `RTPP_port` as `word`.
  * Add `PP_rawtcpip RawTcpipPortParams` to `PortParams` union.

**PrinterConnections capability bit:**

* `Include/Internal/printDr.def`

  * Add `PC_TCPIP TCPIPConnection:1` to `PrinterConnections record`.

* `CInclude/Internal/printDr.h`

  * Add `typedef ByteEnum TCPIPConnection;`
  * Add `#define TC_NO_TCPIP 0x0` and `#define TC_TCPIP 0x1`.
  * Add the matching bit mask for `PC_TCPIP` in `PrinterConnections`.

**Spooler table wiring (stub handlers only):**

* `Library/Spool/Process/processTables.asm`

  * Extend all tables with a new `PPT_RAWTCPIP` entry:

    * `portNameTable`, `portVerifyTable`, `portInitTable`, `portExitTable`,\
      `portErrorTable`, `portCloseTable`, `portInputTable`.
  * Add stub handlers with these exact names:

    * `InitRawTcpipPrintPort`
    * `VerifyRawTcpipPrintPort`
    * `ExitRawTcpipPrintPort`
    * `ErrorRawTcpipPrintPort`
    * `CloseRawTcpipPrintPort`
  * In each stub, add a **placeholder comment** (no real logic yet):

    * `; TODO: RAWTCPIP port init - load rawtcpip.geo and call DR_STREAM_OPEN with PP_rawtcpip (default port 9100)`
    * `; TODO: RAWTCPIP port verify - validate params / attempt open-close`
    * `; TODO: RAWTCPIP port exit - close stream if open`
    * `; TODO: RAWTCPIP port error/close handling`
  * Return neutral values consistent with other port stubs.

**UI port string mapping (placeholder only):**

* `Library/Spool/UI/uiPrintControl.asm`

  * Add a new `portTable` entry mapping `"IP"` → `PPT_RAWTCPIP`.
  * In `PrinterGetPortInfo`, add a placeholder comment:

    * `; TODO: RAWTCPIP params - parse host/port into PP_rawtcpip (UI/INI not wired yet)`

Use the existing formatting conventions (tabs in ASM, C89 rules, handles/pointers naming).
