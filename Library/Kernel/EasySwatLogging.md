# EC Warning Log: Kernel + GOC Macros + Swat Integration (EC-only)

## Goal
Add an EC-only kernel log record + helper, expose EC macros in GOC, and extend Swat’s `why-warning` so EC builds can print either a **typed value** or a **C string** based on a stored type tag.

---

## Kernel data (EC-only, `idata`)
**File:** `Library/Kernel/Boot/bootVariable.def`

1. Under the kernel’s EC guard (`if ERROR_CHECK` … `endif`), add two EC-only globals in the **idata** segment:
   - `ECLogTypeTag`: fixed **32-byte** buffer. We will write **up to 31 bytes** and then a trailing `0`.
   - `ECLogAddr`: **dword** holding a **far pointer** with **low word = offset, high word = segment**.

2. Update comments in this file to explicitly state:
   - `ECLogTypeTag` is NUL-terminated on write; tags longer than 31 bytes are truncated.
   - `ECLogAddr` layout is **low=offset/high=segment**, so Swat can parse `seg:off` correctly.
   - Rationale: `idata` is always resident and Swat can read by symbol name.

Example (pseudodef; keep your project’s segment/def syntax):
```asm
if ERROR_CHECK
ECLogTypeTag   byte 32 dup (0)   ; NUL-terminated, writer truncates to 31 + NUL
ECLogAddr      dword 0            ; far ptr dword: low=off, high=seg

endif
```

---

## Kernel helper (EC-only, `kcode`)
**File:** `Library/Kernel/Boot/bootBoot.asm`

1. Add far routine `_pascal` **`ECWarningLogRecord`** wrapped in `if ERROR_CHECK` guards.

2. **Signature / calling convention:**
   - `_pascal` far proc.
   - Stack (right-to-left):
     `const char __far *typeTagP`, then `dword addr`.
   - **Meaning of `addr`:** far pointer **dword** to the value/string to print (**low=offset, high=segment**).
   - Check Library/User/User/userC.asm, functions like CLIPBOARDTESTITEMFORMAT, CLIPBOARDENUMITEMFORMATS, etc. to see how variables are passed and used from C to ASM in ESP


3. **Implementation:**
   - Copy **up to 31 bytes** from `typeTagP` into `ECLogTypeTag`, then store a trailing `0`.
   - Store `addr` into `ECLogAddr` (write low word to `[ECLogAddr]`, high word to `[ECLogAddr+2]`).
   - Load `AX = EC_LOG_WARNING` and call `CWARNINGNOTICE`.
   - Return to caller.

Minimal sketch for the core functionality:
```asm

   ...

    ; Copy up to 31 bytes from typeTagP -> ECLogTypeTag, then NUL
    push ds
    lds  si, [bp+6]               ; DS:SI = typeTagP
    ; ES:DI must point at ECLogTypeTag (idata). If ES not already idata, load it.
    ; Example (if allowed by your model):
    push es
    mov  ax, seg ECLogTypeTag
    mov  es, ax
    mov  di, offset ECLogTypeTag
    mov  cx, 31
.copyLoop:
    lodsb
    or   al, al
    jz   .terminate
    stosb
    loop .copyLoop
.terminate:
    mov  al, 0
    stosb
    pop  es
    pop  ds

    ; Store addr (low=off, high=seg) to ECLogAddr
    mov  ax, [bp+10]
    mov  dx, [bp+12]
    mov  word ptr ECLogAddr, ax
    mov  word ptr ECLogAddr+2, dx

    ; Issue warning
    mov  ax, EC_LOG_WARNING
    call CWARNINGNOTICE

   ...

```

---

## Kernel exports / ordinals
**File:** `Library/Kernel/geos.gp`

Add `incminor SwatLoggingSupport` (see "incminor RawBitmaCreation"), then

Export **all three**:
   ```
   export ECWarningLogRecord
   export ECLogTypeTag
   export ECLogAddr
   export ECWARNINGLOGRECORD
   export ECLOGTYPETAG
   export ECLOGADDR

   ```

Don't touch kernelResource.def.
And no need to guard this with "if ERROR_CHECK" - GP files dont't understand this.

---

## Warning enum & external (EC-only)
**File:** `Include/ec.def`

1. Behind `Warnings etype word, 0`, on a new line, add
   `EC_LOG_WARNING			enum Warnings`

Add a brief comment what it does.


2. Behind `global SysSetECLevel:far`, after a newline, add
   ```asm
   global  ECWarningLogRecord:far
   ```

---

## C header + macros (EC-only)
**File:** `CInclude/ec.h`

1. After the declaration of "SysSetECLevel",
   - Provide a correct prototype (note no need to add `__far` on the char pointer as all GOC pointers are far pointers by default):
     ```c
     extern void _pascal ECWarningLogRecord(const char *typeTagP, dword addr);
     ```

   - after the following "#if	ERROR_CHECK" line, add a helper to construct a **far pointer dword** (guarantees low=off/high=seg):
     ```c
     #define EC_MAKE_FARPTR(p)  ((((dword)FP_SEG(p)) << 16) | ((dword)FP_OFF(p)))
     ```

   - Then define the public macros:
     ```c
     /* Truncation: type tags longer than 31 bytes will be truncated by the callee. */
     #define EC_LOG_T(type, expr)   ECWarningLogRecord(#type, EC_MAKE_FARPTR(&(expr)))
     #define EC_LOG_STR(expr)       ECWarningLogRecord("string", EC_MAKE_FARPTR((expr)))
     ```

2. Under `#else /* !ERROR_CHECK */`, compile them to nothing:
   ```c
   #define EC_LOG_T(type, expr)   ((void)0)
   #define EC_LOG_STR(expr)       ((void)0)
   ```

---

## Swat: extend `why-warning`
**File:** `Tools/swat/lib.new/fatalerr.tcl`

1. In the `why-warning` handler, add a branch for the new warning code **`EC_LOG_WARNING`**.

2. Behavior:
   - Read the tag: **`pstring ECLogTypeTag`** (this repo’s `pstring` reads NUL-terminated C strings by symbol name).
   - Read the far pointer dword: fetch `ECLogAddr` as a value; parse **low=offset, high=segment**.
   - If the tag equals `"string"` → print the C string at `seg:off`: `pstring $seg:$off`.
   - Else → print a **typed value** at `seg:off` using `_print` and a typed address expression: `"$tag $seg:$off"`.
   - Handle edge cases:
     - If `ECLogAddr == 0`, print `(null)` and return `0`.
     - Format addresses as 4-digit hex (e.g., `%04x:%04x`) for clarity.
   - Return `0` to continue execution (maintains existing behavior).

Concrete snippet (adjust to match the rest of fatalerr.tcl):
```tcl
# inside why-warning { code ... }
if {$code == EC_LOG_WARNING} {
    # Read tag (C-string) and far pointer
    set tag [pstring ECLogTypeTag]
    set addr [value ECLogAddr dword]   ;# low=off, high=seg
    set off [expr {$addr & 0xffff}]
    set seg [expr {($addr >> 16) & 0xffff}]
    if {$addr == 0} {
        echo "EC log: (null)"
        return 0
    }
    if {$tag eq "string"} {
        echo -n "EC log (string): "
        pstring [format %04x:%04x $seg $off]
    } else {
        echo -n "EC log ($tag): "
        _print "$tag [format %04x:%04x $seg $off]"
    }
    return 0
}
```

*(Notes: `pstring` here is the autoloaded routine from `Tools/swat/lib.new/pvm.tcl` that reads C-style NUL-terminated strings by address or symbol. `_print` is from `Tools/swat/lib.new/print.tcl`.)*


## Developer notes (current behavior)

- `EC_LOG_T(type, expr)` should continue to use plain type tokens at call sites (for example `word`, `WWFixed`), because the macro still passes `#type` unchanged.
- Swat `why-warning` now resolves typed tags by trying these type names in order: raw tag (`tag`), global kernel namespace (`geos::tag`), then current patient namespace (`<patient>::tag`) when a patient is known.
- If none of those type symbols can be resolved, Swat prints a readable fallback including raw `word`/`dword` values from the logged address and continues execution.
