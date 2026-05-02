Please implement a cleaner approach for filesystem auto detection: leave `os2.geo`, `ntfat.geo`, `mslf.geo`, and `ms4.geo` behavior unchanged, and instead improve the kernel’s primary filesystem driver auto-selection during boot.

Goal:
- On pure DOS, load `ms4.geo`.
- On hosted/emulated DOS such as Basebox/DOSBox, load `os2.geo`.
- Keep explicit `geos.ini` driver choices working exactly as before.
- Avoid leaving current paths attached to the skeleton FSD if the first selected driver creates no usable drives.

Implementation direction:
1. Find the kernel boot path that reads `geos.ini` `primaryFSD` / `fs` and loads the primary FSD.
2. Add a conservative `auto` mode, for example:
   - `primaryFSD = auto`
   - if primaryFSD == auto, use the "fs" ini-key as a reservoir for filesystem drivers to choose from (check how the behaviour for this key is currently, it takes a list)
3. The detector should classify whether MS4-style DOS internals are safe, not merely detect DOSBox by name.
   Useful signals:
   - documented DOS probing behavior
   - DOS List-of-Lists / CWD / DCB sanity checks, but only as a classifier
   - SFT/DCB/CWD validation
   - emulator/Basebox signatures only if stable and non-invasive
4. Add fallback behavior:
   - Try the preferred driver.
   - Verify that it registered at least one usable managed drive or successfully revector current path drives away from the skeleton FSD.
   - If not, try the next candidate.
   - Do not crash or continue boot with skeleton FSD as the active driver for normal file operations.
5. Keep `ufat.geo` experimental and do not make it the default until proven stable.
6. Update product `geos.ini` templates only after the kernel auto-selection is implemented.
7. Build affected geodes from `Installed/...` with:
   - `yes | clean`
   - `mkmf`
   - `pmake depend`
   - `pmake -L 4 full`

Important constraints:
- This is 16-bit PC/GEOS.
- Kernel and drivers are ESP assembler.
- Keep the patch minimal.
- Do not rewrite existing filesystem drivers.
- Preserve pure DOS behavior.
- Preserve explicit existing `geos.ini` config behavior.
- Use ASCII only in code/comments.
- Do not edit generated Makefile/dependencies.mk in source directories.
- read AGENTS.md