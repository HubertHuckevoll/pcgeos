#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../../Tools/swat";
use SwatTestRunner;

# Install the current Bitmap, GrObj, and GeoDraw in an SDK test target.
# Run with perl Library/Bitmap/Test/format-protocol.pl from the SDK checkout.
# To test rejection, install Bitmap 8.1 in the same target and add --reject.
my $reject = grep { $_ eq '--reject' } @ARGV;
@ARGV = grep { $_ ne '--reject' } @ARGV;
# The older Bitmap library can have different symbols. This test uses none.
local $ENV{SWATIGNORE} = join ' ', ($ENV{SWATIGNORE} // ''), ($reject ? 'bitmap' : ());
local $ENV{BITMAP_TEST_REJECT} = $reject ? 1 : 0;
my $status = SwatTestRunner::run(do { local $/; <DATA> }, @ARGV);
print "  --reject  Expect the target with Bitmap 8.1 to reject GeoDraw.\n"
    if grep { $_ eq '--help' } @ARGV;
exit $status;

__DATA__
run draw
var loaded [expr {![null [patient find draw]]}]
var reject [getenv BITMAP_TEST_REJECT]
if {$reject && !$loaded} {
    # run leaves the result of UserLoadApplication in these registers.
    var code [penum GeodeLoadError [read-reg ax]]
    echo [format {Expected GeoDraw to reject Bitmap 8.1. Load error: %s} $code]
    var passed [expr {([read-reg cc]&1) && [string c $code GLE_LIBRARY_PROTOCOL_ERROR] == 0}]
} else {
    echo [format {GeoDraw started: %d} $loaded]
    var passed [expr {$loaded && !$reject}]
}
expr {$passed}
