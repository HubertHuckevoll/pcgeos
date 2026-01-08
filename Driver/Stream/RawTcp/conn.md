1) PrinterConnections (driver capability flags)

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