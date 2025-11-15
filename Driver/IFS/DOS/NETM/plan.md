Proposed Task Breakdown

    Introduce the NetMount driver skeleton

        Copy Driver/IFS/DOS/MSNet to Driver/IFS/DOS/netm and rename every MSNet* symbol, structure, and resource to a NetM*/NetMount* prefix so the new module is isolated from the legacy MS-Net driver while still exporting the same entry tables and helper layout.

Author NetMount-specific .gp, .rev, constants, variables, and string tables that mirror the MSNet originals but with updated names/long strings ready for later functional work.

    Leave build-system updates for a later task so subsequent functional branches can rebase cleanly; only new files are touched in this step.

Detect NetMount and register with DOS redirectors

    In netmInitExit.asm, replace the MSNet machine-name probe with code that scans INT 2F multiplex IDs (AH=C0h..FFh) for the JA/RO/NM signature, verifies the redirector API via INT 2F AX=1100h, and captures the primary DOS FSD’s strategy vector just as MSNet does today.

    Ensure the init routine still performs the existing PSP capture, interrupt hooks, and primary FSD registration, but under the new NetMount prefixes established in Task 1 so later tasks won’t re-touch these blocks.

Enumerate NetMount drives with the DOS redirector API

    Rewrite the NetMInitLocateDrives flow to iterate the DOS redirector list via INT 2F/AX=1106h (and related subfunctions) instead of MSDOS_GET_REDIRECTED_DEVICE, capturing each NetMount disk’s drive letter and canonical remote path before invoking FSDInitDrive with the correct fixed/network flags.

    Populate per-drive private data as needed for later restore work, but avoid altering unrelated sections to minimize merge overlap with Task 2.

Persist and restore NetMount mappings

    Reimplement DR_FS_DISK_SAVE and DR_FS_DISK_RESTORE under the NetMount prefix so they query the redirector for a drive’s remote target, persist that string in saved private data, and invoke NetMount’s multiplex entry to remount volumes before handing control back to DOS—mirroring the existing MSNet save/restore scaffolding while swapping to the new INT 2F calls.

    Keep helper flows (e.g., hand-offs to the primary FSD) intact so only the redirector-facing logic changes, keeping this task focused and sequential with Task 3.

Integrate NetMount into the build and packaging system

    After the functional work lands, add the new driver to the packaging manifests (Driver/IFS/DOS/UNINST, Installed/Driver/IFS/DOS/...) and generate the installed-side makefiles so the component is built and distributed alongside the existing IFS drivers.

        Update long names, tokens, and extended-info strings to reference NetMount explicitly and verify the renamed helper routines (open-file takeover, NetMCallPrimary, etc.) remain wired through the entry tables before tagging the driver for release.

Each step should branch from and merge after the previous one, ensuring only new hunks are touched at each stage and avoiding the need to resolve overlapping edits.