# Native Windows parallel builds in pmake

## Scope

The native Windows backend supports Windows 10 and Windows 11. It uses the
existing 32-bit Open Watcom toolchain. The default is one job.

Use pmake -J 8 -L 8 to allow eight local targets at the same time. Both options
accept decimal values from 1 through 63. The smaller value is the local limit.
Each recursive pmake process inherits the options and has its own limits.
There is no shared job pool. A recursive build can therefore run more than
eight processes in total.

Windows and Linux print the configured mode and limits at startup, for
example: pmake: parallel enabled (-J 8 -L 8). A local limit of one reports
serial. Serial compatibility mode also shows -M, even if the limits are
higher. Each recursive invocation prints its own line. This reports the
configuration; dependencies can leave fewer jobs ready to run. Preview
and query runs do not print this line.

Windows and Linux also print live start and finish lines, for example:
pmake[1234]: started SSL (3/8 local jobs active). The limit is the smaller
of -J and -L. Counts cover that pmake process, not all recursive processes.
They count shells that have started and have not yet been collected. A
finished line reports a shell exit; the target result can still be an
error. In -B mode, each command is a separate shell job. With -P, outer
progress stays live while tool output is captured. Nested progress is
part of that capture. The -s flag suppresses these progress lines. The
-M compatibility path retains its existing serial output.

One shell runs the recipe lines for each target. Directory and environment
changes remain in that shell. Output is live, with the existing target banners.
Output from different targets can mix. Use call when a recipe must call a batch
file and then continue.

Add -P to print each target of the outer Windows invocation as one block
when it finishes.
For example, use pmake -J 8 -L 8 -P. Both output streams share one unique
temporary file per target. Output is delayed until completion; the build
stays parallel. Long lines are preserved. The block starts with the target
banner and ends with its result. Recursive pmake calls inherit -P, but
write through to the outer capture. This keeps unfinished recursive output
available on cancellation. The internal PMAKE_OUTPUT_CAPTURED environment
variable marks this condition. The -B mode keeps the capture file across
commands. The -M serial compatibility path retains its existing output
behavior.

On cancellation, pmake stops the build processes, prints the captured
output, and closes the files. Capture files use delete-on-close. Live
output remains the default. Linux keeps its existing -P implementation.

Commands longer than 1000 characters use response files. Watcom requires
an unquoted response-file path. If TMP has spaces, pmake uses its Windows
short path. If short names are disabled, set TMP to a directory without
spaces. The path remains absolute so recipe directory changes work.

The default shell comes from COMSPEC. If COMSPEC is empty or absent, pmake uses
cmd.exe. An explicit .SHELL path has priority. Paths with spaces are quoted.
The Windows -n and -N options still select NC builds. The -u and -U options
still show commands without running them. The -M serial mode and the -B
command-at-a-time mode remain available.

The wait array has 63 child slots and one cancellation slot. A larger limit
requires a different wait design. See the
[Microsoft wait documentation](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitformultipleobjects).
Each pmake process creates an unnamed job object. Shells join it before they
start. Nested job objects keep recursive tools in the parent job hierarchy.
See the [Microsoft job object documentation](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects).

## Build and regression commands

Keep PC/GEOS stopped. From a Windows command prompt with the SDK environment:

    cd /d %ROOT_DIR%\Tools\pmake\pmake
    wmake -a pmake.exe
    cd /d %ROOT_DIR%
    perl Tools\pmake\Tests\windows-parallel.pl Tools\pmake\pmake\pmake.exe

These commands do not install the executable. Use wmake install in the pmake
source directory when you want to install the SDK tool.

On Linux, build both formats and run the portable checks:

    cd "$ROOT_DIR/Tools/pmake/pmake"
    wmake -a pmake.exe
    wmake -a pmake.e
    cd "$ROOT_DIR"
    perl Tools/pmake/Tests/windows-parallel.pl Tools/pmake/pmake/pmake.e

The runner uses core Perl modules. It creates temporary Makefiles and uses
worker modes in the same script. Marker files check overlap, replacement of a
short job, and dependency order. Each worker handshake and each pmake run has
a timeout. The Windows run also checks the 63-child boundary, rejected values,
full Windows exit codes, shell selection, temporary files, and batch calls.
The Windows checks also cover grouped output, long lines, failure output,
ignored errors, and recursive capture ownership.
If WATCOM is set, it also checks long compiler commands after directory
changes, TMP paths with spaces, and response-file cleanup after errors.

Linux keeps its current behavior. Two failure-status assertions are TODO checks:
with -k, Linux Make_Run can return success after command errors. The Windows
.END execution tests are skipped on Linux because the _LINUX branch in Job_End
does not collect the .END child. This change does not repair these Linux paths.

## Native cancellation and handle checks

Windows runtime validation is pending. The Linux regression run and Windows
cross-build cannot validate Windows process scheduling or cancellation.

Create persistent test inputs in a new directory. These inputs include recursive
jobs and descendant workers that ignore Ctrl+C and wait for five minutes:

    cd /d %ROOT_DIR%
    perl Tools\pmake\Tests\windows-parallel.pl --native-fixtures "%TEMP%\PmakeNative"
    cd /d "%TEMP%\PmakeNative"
    set TMP=%CD%
    set TEMP=%CD%
    %ROOT_DIR%\Tools\pmake\pmake\pmake.exe -r -f Cancel.mk -J 8 -L 8

Wait until pid-* files and the partial and precious files exist. Press Ctrl+C.
Check that pmake returns a nonzero status, partial is removed, and precious
remains. No survived-* file must appear. Repeat with Ctrl+Break.

In PowerShell, check the recorded descendant process IDs after cancellation:

    Set-Location "$env:TEMP\PmakeNative"
    Get-ChildItem pid-* | ForEach-Object {
        Get-Process -Id ([int]$_.Name.Substring(4)) -ErrorAction SilentlyContinue
    }
    Get-ChildItem PMA*,survived-* -ErrorAction SilentlyContinue

Both commands must produce no results. If TMP and TEMP were set in the first
command prompt, use the original temporary directory in this separate shell.
Repeat these cancellation checks with -P. Each holding-worker line must
appear after cancellation, and no PMA capture files must remain.

Also check Task Manager for any remaining pmake, cmd, or tool descendants from
this build. Repeat cancellation during startup and during a recursive build.
Check that temporary command files are removed after success, failure, and
cancellation. Long recipes can also create response files; include such a
recipe when you check cancellation in a product build.

Run the handle test from the fixture directory:

    %ROOT_DIR%\Tools\pmake\pmake\pmake.exe -r -f Soak.mk -J 8 -L 8

While it runs, sample pmake handle counts in a second PowerShell window:

    while ($p = Get-Process pmake -ErrorAction SilentlyContinue) {
        $p | Select-Object Id,HandleCount
        Start-Sleep -Milliseconds 250
    }

Repeat the handle test with -P to include capture files.

Handle counts must stay bounded as the 1000 targets run. Run the same command
several times. Check that no processes or PMA* files remain after each run.
The fixture contains only test files. Remove its directory when the checks are
complete.

## Native product checks

From the Installed directory, build EC and NC components separately:

    cd /d %ROOT_DIR%\Installed
    %ROOT_DIR%\Tools\pmake\pmake\pmake.exe -J 8 -L 8 full
    %ROOT_DIR%\Tools\pmake\pmake\pmake.exe -n -J 8 -L 8 full

Check the complete output and exit status of each build. Repeat the existing
EC and NC product assembly steps from README.md. Keep PC/GEOS stopped during
these checks. Product build validation is pending.

## Linux-host validation results

Both wmake pmake.exe and wmake pmake.e link successfully. The Linux regression
runner passes, with the two expected -k TODO results and the Windows-only
checks skipped.

The full builds still report legacy diagnostics. Windows reports W121 for old
preprocessor directive text, W120 for lvalue casts, W131 for missing prototypes
(getopt, free, and ffs), W1179 for type qualifiers, W1181 for a signed argument,
and W1027 for the duplicate Sprite and Watcom strtol definitions. Linux also
reports W102 for type mismatches, W126 for a pointer comparison, and a missing
JobInterrupt prototype. These diagnostics come from existing code and headers.
They remain outside this Windows backend change. No new backend diagnostic
remains. A successful link does not mean a warning-free build.
