We need to add a kernel‑side EC log record + helper, expose macros in GOC, and extend Swat’s existing why-warning handler to print either a typed value or a string based on a stored type tag.

Kernel data record (EC-only, idata)
Edit Library/Kernel/Boot/bootVariable.def.
In idata segment, add EC-only globals:
ECLogTypeTag as a fixed char buffer exactly 32 bytes, null-terminated on write.
ECLogAddr as a dword storing a far pointer (segment).
Rationale: idata is always resident and Swat can read it by symbol name.

Kernel helper routine (EC-only, kcode)
Edit Library/Kernel/Boot/bootBoot.asm.
Add a far routine named ECWarningLogRecord with _pascal convention.
Parameters (stack order for _pascal):
const char *typeTagP (far pointer to null-terminated string)
dword addr (segment of the value to print)
Implementation:
Copy up to 31 bytes from typeTagP into ECLogTypeTag, then write a trailing 0.
Store addr into ECLogAddr.
Call CWARNINGNOTICE with the new warning code (defined below).
Wrap the whole routine in EC-only assembly guards so it is absent in non-EC builds.

Kernel exports / warning enum (fixed locations)
Edit Library/Kernel/kernelResource.def and export:
ECWarningLogRecord:far
ECLogTypeTag:byte
ECLogAddr:dword
Edit Include/ec.def:
Add the new warning enum under Warnings etype named EC_LOG_WARNING (next available value).
Add global ECWarningLogRecord:far so ASM can link.
The warning code value must be stable and reserved for this feature.

GOC macros (EC-only)
Edit CInclude/ec.h.
Add extern void _pascal ECWarningLogRecord(const char typeTagP, dword addr);
Implement macros (all under #if ERROR_CHECK):
EC_LOG_T(type, expr) → ECWarningLogRecord(#type, (dword)(void)&(expr))
EC_LOG_STR(expr) → ECWarningLogRecord("string", (dword)(void*)(expr))
Non-EC builds compile these macros to nothing.

Swat handler (extend existing why-warning)
Edit Tools/swat/lib.new/fatalerr.tcl inside why-warning.
Add a branch for EC_LOG_WARNING:
Read ECLogTypeTag using pstring ECLogTypeTag.
Read ECLogAddr via value fetch as a dword and format it into seg:off (segment=high word, offset=low word).
If tag equals "string" → pstring seg:off
Else => invoke _print with a typed address expression: "$tag $seg:$off".
Return 0 afterward to continue execution, matching current behavior.

Docs (required)
TechDocs/Markdown/Routines/rroute_f.md: document EC_LOG_T and EC_LOG_STR next to other EC macros.
TechDocs/Markdown/Tools/tswatcm.md: note that why-warning will emit EC log output for EC_LOG_WARNING.

Notes:
Swat already wires WarningNotice/CWARNINGNOTICE to why-warning via Tools/swat/lib.new/swat.tcl; no new Swat command is needed.
pstring is in Tools/swat/lib.new/pvm.tcl and autoloaded.
_print is in Tools/swat/lib.new/print.tcl and is safe for Tcl callers.