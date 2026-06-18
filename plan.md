# ESP/ASM Swat Logging

## Summary

Add a small EC-only logging facility for ESP/ASM that is useful for normal assembly debugging: registers, memory expressions, strings, flags, and plain trace messages. Keep C/GOC logging compatible, but design the ASM API around values ASM programmers actually inspect.

## Key Changes

- Extend the kernel EC log record with a kind field, captured value, value size, logged address, name string, and caller CS:IP.
- Add exported EC-only kernel entry points for value logging, memory logging, string logging, message logging, and flags logging.
- Add ESP macros in Include/ec.def:
  - EC_LOG_MSG "text"
  - EC_LOG_REG ax
  - EC_LOG_REG_PAIR dx, ax
  - EC_LOG_MEM <ss:[locals].SPMV_rvmf.RVMF_dataType>
  - EC_LOG_STR ds, si
  - EC_LOG_STR_NAME "folder name", ds, si
  - EC_LOG_FLAGS
- In non-EC builds, all macros expand to nothing.
- Make macros preserve flags and caller-visible registers unless the macro name explicitly logs flags after a mutation.

## Swat Output

- Message:
  EC log: after ReplaceVisMoniker setup

- Register:
  EC log ax = 0034h

- Register pair:
  EC log dx:ax = 1a2b:0034h

- Memory:
  EC log ss:[locals].SPMV_rvmf.RVMF_dataType = 01h

- String:
  EC log folder name = "Wastebasket"

- Flags:
  EC log flags = 0246h

## Type Resolution

- Start with reliable raw hex output for memory and register values.
- Add best-effort typed printing for memory expressions by normalizing ASM syntax:
  - ss:[locals].SPMV_rvmf.RVMF_dataType becomes locals.SPMV_rvmf.RVMF_dataType
  - ds:[di].field remains raw unless Swat can resolve the base register expression
- If Swat resolves the field type, print enum names such as VMDT_VIS_MONIKER.
- If type resolution fails, always print raw byte, word, or dword output.

## Test Plan

- Build the kernel from Installed/Library/Kernel with pmake -L 4 full.
- Add temporary test logging in an ESP routine, verify it assembles, then remove or keep only if it is intentional debug code.
- In Swat, verify:
  - EC_LOG_MSG prints once and continues execution.
  - EC_LOG_REG ax prints the captured AX value.
  - EC_LOG_REG_PAIR dx, ax prints a dword-style pair.
  - EC_LOG_MEM on ss:[locals].SPMV_rvmf.RVMF_dataType prints 01h after assignment to VMDT_VIS_MONIKER.
  - EC_LOG_STR prints a null-terminated string.
  - EC_LOG_FLAGS prints the pushed flags value.
- Confirm non-EC builds produce no logging code.

## Assumptions

- Logging remains EC-only.
- Raw output is sufficient for v1; typed enum names are best-effort.
- Register logging stores captured values directly in kernel EC state, not fake memory addresses.
- Memory logging stores both the original ASM expression text and the far address Swat should read.
