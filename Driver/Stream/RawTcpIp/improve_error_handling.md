## Goal

Preserve legacy stream-call behavior (Channel A) while adding richer,
user-visible diagnostics (Channel B) for RawTcpIp custom-port printing.

------------------------------------------------------------------------

## 1. Define RawTcpIp-specific stream error constants (\>= STREAM_FIRST_DEV_ERROR)

### Canonical location (shared ABI)

Add STREAM_RAWTCP\_\* constants in:

Include/Internal/rawtcpipDr.def

Keep numeric values contiguous from STREAM_FIRST_DEV_ERROR.

Required set:

-   STREAM_RAWTCP_BAD_CONFIG
-   STREAM_RAWTCP_CREATE_FAILED
-   STREAM_RAWTCP_CONNECT_REFUSED
-   STREAM_RAWTCP_CONNECT_TIMEOUT
-   STREAM_RAWTCP_CONNECT_FAILED
-   STREAM_RAWTCP_SEND_FAILED
-   STREAM_RAWTCP_NOT_CONNECTED
-   STREAM_RAWTCP_RESTART_FAILED

### Driver usage

Update Driver/Stream/RawTcpIp/rawtcpip.def to reference the shared
constants from rawtcpipDr.def. Do not duplicate numbering locally in the
driver.

------------------------------------------------------------------------

## 2. Add persistent error storage in RawTcpIp driver

File: Driver/Stream/RawTcpIp/rawtcpipMain.asm

### Per-context storage

Use existing RTC_error in RawTcpIpContext as last detailed stream error.

### Global fallback storage

Add global fallback in udata:

rawTcpLastError (for pre-open / invalid-context paths)

### Optional socket-level diagnostics

Recommended addition:

-   RTC_socketError in context
-   rawTcpLastSocketError as global fallback

This preserves stream-oriented error semantics in RTC_error while
optionally retaining raw socket AX values for debugging or future
extension.

------------------------------------------------------------------------

## 3. Implement Channel A return compatibility (do not change legacy returns)

### RawTcpIpOpen

All failures must continue to return:

CF=1\
AX=STREAM_NO_DEVICE

### RawTcpIpWrite

All failures must continue to return:

CF=1\
AX=STREAM_CLOSED

Strict rule:

Do not return any STREAM_RAWTCP\_\* values directly in AX. Custom codes
are Channel B only.

------------------------------------------------------------------------

## 4. Implement Channel B detailed error capture in RawTcpIp

### In RawTcpIpOpen

Store detailed error before legacy return:

-   Config invalid/missing\
    -\> STREAM_RAWTCP_BAD_CONFIG

-   SocketCreate failure\
    -\> STREAM_RAWTCP_CREATE_FAILED

-   SocketConnect failure:

    -   SE_CONNECTION_REFUSED\
        -\> STREAM_RAWTCP_CONNECT_REFUSED

    -   SE_TIMED_OUT\
        -\> STREAM_RAWTCP_CONNECT_TIMEOUT

    -   otherwise\
        -\> STREAM_RAWTCP_CONNECT_FAILED

If optional socket detail channel is enabled, store failing AX socket
error at each site.

### In RawTcpIpWrite

Store before teardown:

-   Not connected / invalid socket\
    -\> STREAM_RAWTCP_NOT_CONNECTED

-   SocketSend carry set\
    -\> STREAM_RAWTCP_SEND_FAILED

If socket detail tracking enabled, store AX at failure.

------------------------------------------------------------------------

## 5. Implement RawTcpIpGetError return-and-clear behavior

File: Driver/Stream/RawTcpIp/rawtcpipMain.asm

Replace stub that returns 0.

Behavior:

-   If BX is a valid context handle and lock succeeds:
    -   return RTC_error
    -   clear RTC_error
-   Else:
    -   return rawTcpLastError
    -   clear fallback

Return AX=0 if nothing stored. Always non-failing (clear carry).

Semantics: get-and-clear.

------------------------------------------------------------------------

## 6. Honor RawTcpIpSetError for symmetry

File: Driver/Stream/RawTcpIp/rawtcpipMain.asm

Behavior:

-   If valid context handle:
    -   store CX into RTC_error
-   Else:
    -   store into rawTcpLastError

Always clc.

------------------------------------------------------------------------

## 7. Implement runtime notifier plumbing for detailed errors

RawTcpIp currently has a DR_STREAM_SET_NOTIFY stub.

Implement minimal notifier storage in the per-open context:

-   store notify type
-   store routine destination (for SNE_ERROR)

On runtime failures (write / restart):

-   Post SNE_ERROR
-   Pass CX = STREAM_RAWTCP\_\*

Flow:

RawTcpIp -\> StreamErrorHandler -\> MSG_SPOOL_COMM_ERROR

Strict rule:

-   No driver-side dialog/UI calls.
-   Preserve existing notification wiring.

------------------------------------------------------------------------

## 8. Update spooler custom-port handling

Primary file: Library/Spool/Process/processCustom.asm

### Open path --- InitCustomPort

On DR_STREAM_OPEN failure:

1.  Call DR_STREAM_GET_ERROR
2.  Map returned detailed code to spooler error category

Phase 1 mapping (minimal risk):

-   STREAM_RAWTCP_CONNECT_TIMEOUT\
    -\> PERROR_TIMEOUT

-   All other RawTcpIp failures\
    -\> PERROR_NETWORK_ERR

-   Unknown\
    -\> PERROR_PARALLEL_ERR

### Runtime path --- ErrorCustomPort

-   Decode incoming DX custom error code.
-   Map to user-facing category (same Phase 1 mapping).
-   Preserve retry/abort UX.
-   Preserve queue lock discipline around SpoolErrorBox.

------------------------------------------------------------------------

## 9. Optional Phase 2: Extend spooler error text tables

Add new PERROR\_\* values in:

Include/Internal/spoolInt.def

Then update:

-   Library/Spool/Process/processError.asm
-   Associated UI text resources

Unknown codes must fall back to generic network/custom-port message.

------------------------------------------------------------------------

## 10. Keep restart semantics intact

In ErrorCustomPort:

Continue using STREAM_ESC_RESTART_OUTPUT.

If restart escape fails:

-   Record / propagate STREAM_RAWTCP_RESTART_FAILED
-   Follow existing abort logic
-   Notify with detailed code

------------------------------------------------------------------------

## 11. Validation checklist

-   Immediate returns unchanged (STREAM_NO_DEVICE / STREAM_CLOSED).
-   DR_STREAM_GET_ERROR is get-and-clear.
-   Pre-open failures retrievable via fallback global.
-   Runtime notifications carry detailed RawTcpIp code.
-   Spooler shows differentiated handling (timeout vs generic network).
-   No driver-side dialog/UI code added.
-   No unrelated stream drivers modified.

------------------------------------------------------------------------

## 12. Scope

Touched files:

-   Include/Internal/rawtcpipDr.def
-   Driver/Stream/RawTcpIp/rawtcpip.def
-   Driver/Stream/RawTcpIp/rawtcpipMain.asm
-   Library/Spool/Process/processCustom.asm
-   Optionally:
    -   Include/Internal/spoolInt.def
    -   Library/Spool/Process/processError.asm
    -   UI text resources

All changes are additive and ABI-safe.
