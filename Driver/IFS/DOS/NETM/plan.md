Proposed Task Breakdown

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