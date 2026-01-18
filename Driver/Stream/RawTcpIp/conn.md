
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
