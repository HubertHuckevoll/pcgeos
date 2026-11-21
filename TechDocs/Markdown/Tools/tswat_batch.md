# Run Swat tests in batch mode

Run a Swat regression test with Perl from the SDK checkout. On Linux or
Windows, use a configured SDK environment with an installed Swat debugger,
a built target, and an emulator with IPX support. Set `BASEBOX` to the
emulator executable if you use an executable other than `dosbox`. On
Windows, use a Swat build from this checkout to get batch transcript output.
Close the interactive target before you run a test. The default test target
uses UDP port 8079.

## Run a test

Install the geode that the test checks in the test target. Run the Perl
script from the SDK root.

```text
perl path/to/Test/test.pl
```

- The default is the EC target. Use `-n` to select the normal target.
- Use `--timeout SECONDS` to change the 60-second limit for target startup
  and test execution.
- Use `--no-window` to skip the read-only transcript window. The runner
  opens it when a supported terminal is available. Closing the window
  leaves the test running. Redirect standard output to keep a transcript.
- Use `--help` to see the available options.

The runner selects the target from its SDK profile in `LOCAL_ROOT`, then
starts the emulator and Swat. It uses a private Swat startup file and stops
the processes it starts. The test runs against the installed target files.

The Perl test reports a result and returns an exit code.

- `PASS` (`0`) means the check passed.
- `FAIL` (`1`) means the behavior differed from the expected behavior.
- `ERROR` (`2`) means the run did not produce a valid test result.
- `TIMEOUT` (`124`) means target startup or the test exceeded the time limit.

## Write a test

Put each test in a Perl file in the geode's `Test` folder. Embed the Swat Tcl
after `__DATA__`. This example uses the module path for a test in
`Library/<geode>/Test`. Adjust the relative path for other folders.

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../../Tools/swat";
use SwatTestRunner;

exit SwatTestRunner::run(do { local $/; <DATA> }, @ARGV);

__DATA__
expr {![null [patient find loader]]}
```

Make the last Tcl command produce `1` if the check passes or `0` if it
fails. Use `error` if the test cannot reach the condition it must check. Use
`echo` to print the expected and actual values on failure. Call
`flush-output` when the next step can take time. Use `protect` to release
breakpoints and restore saved state even if Tcl reports an error.
