### Spooler integration

Each printer driver’s PrinterInfo includes a PrinterConnections bitfield that advertises which connection types it supports (serial, parallel, file, custom, etc.). The driver info resources set these flags (e.g., many drivers set RC_RS232C and/or CC_CENTRONICS, while the host/PS/fax entries set CC_CUSTOM). That’s the data the preferences UI uses to decide which port choices are valid for a given printer.
(Examples in Driver/Printer/*/*Info.asm, and the PrinterConnections definition in CInclude/Internal/printDr.h.)

We need to check the PScript driver in Driver / Printer for a printer device that advertises CC_CUSTOM in its driver’s PrinterInfo, so we can later set the printer’s INI entry to:

```
[<printer category>]
port = CU
portDriver = rawtcp.geo
```

This way the spooler will treat it as a custom port and load our stream driver — even though the Preferences UI doesn’t provide a “Custom” option in the port list. I think the "HP LaserJet 4L" seems to be a good candidate to add the CC_CUSTOM flag to.

Relevant code pointers
    Port string → port type mapping: Library/Spool/UI/uiPrintControl.asm (portTable / PrinterGetPortInfo)
    Custom port INI data: Library/Spool/UI/uiPrintControl.asm (PrinterGetCustomPortData, key "customPortData")
    Driver connection flags: CInclude/Internal/printDr.h (PrinterConnections)
    Examples of CC_CUSTOM: Driver/Printer/PScript/hostPrinterInfo.asm, Driver/Printer/Fax/*Info.asm



1) PrinterConnections (driver capability flags)

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




Where: CInclude/Internal/printDr.h
What it is: A bitfield embedded in each printer driver’s PrinterInfo record.

It declares what connection types the printer driver supports:

    RS232CConnection (serial)

    CentronicsConnection (parallel)

    FileConnection (print-to-file)

    CustomConnection (driver supplies its own stream driver)

    others like SCSI, Appletalk, IEEE-488

This is capability metadata. The Preferences/Spool UI uses it to decide which port options should be available for a given printer model.
2) PrinterPortType (actual chosen port type for a job)

Where: CInclude/Internal/spoolInt.h (PrinterPortType)
Values:

    PPT_SERIAL, PPT_PARALLEL, PPT_FILE, PPT_NOTHING, PPT_CUSTOM

This is the actual port selection stored in the job’s JobParameters (JP_portInfo.PPI_type). It’s what the spooler uses when it opens the port for a print job.

So:

    PrinterConnections = what the driver says it can do

    PrinterPortType = what the user/config actually picked

3) The CC_/RC_/FC_ enums (per-connection flags)*

These are the individual flags that populate PrinterConnections.
Example:

    CC_CUSTOM is the CustomConnection flag (driver provides its own stream driver).

    RC_RS232C is serial support.

    CC_CENTRONICS is parallel support.

    FC_FILE is print-to-file support.

So CC_CUSTOM does not select the port by itself — it only advertises support. The actual selection is PPT_CUSTOM.
4) Port “names” in INI (LPT/COM/CU/UN)

Where: Library/Spool/UI/uiPrintControl.asm
The UI reads a string like "LPT1" or "COM2" or "CU" (custom) and maps it to PPT_*.
This is just the INI representation of the chosen port.
5) Other port-related types

From spoolInt.h:

    SerialPortParams, ParallelPortParams, FilePortParams, CustomPortParams

    Union PortParams, embedded in PrintPortInfo
    These are the port-specific configuration blocks stored in JP_portInfo.

Relevance to a JetDirect (TCP/IP) stream driver
What you need:

    A stream driver that implements the standard stream driver interface (so the spooler can call DR_STREAM_OPEN, etc.).

    A printer driver that advertises CC_CUSTOM in its PrinterConnections.

    The printer’s INI category should set:

    port = CU
    portDriver = yourtcpip.geo
    customPortData = <whatever your driver needs>

How it flows:

    Preferences/UI (or installer) sets port = CU.

    Spooler maps "CU" → PPT_CUSTOM.

    InitCustomPort loads your stream driver (portDriver) and calls DR_STREAM_OPEN.

    DR_PRINT_SET_STREAM passes the stream handle to the printer driver.

So:
Your JetDirect plan fits perfectly into the CUSTOM model.
Just ensure your printer driver declares CC_CUSTOM and your port driver is a proper stream driver.



Here’s how I’d name them to keep things generic and consistent with existing style:
PrinterConnections (capability flags)

Keep it generic to avoid vendor-specific naming:

    NetworkConnection as the bitfield name

    Enum values:

        NC_NO_NETWORK

        NC_NETWORK

So in PrinterConnections you’d add a NetworkConnection bit (like the existing RS232CConnection, CentronicsConnection, etc.).

If you want to be explicit that it’s TCP/IP-only, then:

    TCPIPConnection with TC_NO_TCPIP / TC_TCPIP

But “Network” is more future-proof.
PrinterPortType (actual chosen port)

Again, generic:

    PPT_NETWORK

or if you want to mirror the capability name:

    PPT_TCPIP

I’d go with PPT_NETWORK unless you know this will only ever be TCP/IP.
Port parameters struct

Add a dedicated parameter block under PortParams:

    NetworkPortParams (or TcpipPortParams)

    Fields like:

        address/hostname (string)

        port number (word)

        optional timeout/retry settings

        optional protocol flags (RAW vs LPR, etc.) if you want to expand later

Example names:

    NPP_hostName, NPP_port

    or TPP_hostName, TPP_port (if TCP/IP-specific)

My preference (most generic)

    Capability: NetworkConnection with NC_NETWORK

    Port type: PPT_NETWORK

    Params: NetworkPortParams with NPP_* fields

That keeps the door open for non‑TCP/IP network transports later, while still fitting JetDirect.

If you want it JetDirect‑specific and explicit, then:

    TCPIPConnection / PPT_TCPIP / TcpipPortParams

But I’d recommend the generic Network naming unless you’re sure it should be TCP/IP forever.