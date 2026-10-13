#!/usr/bin/env perl
# Check the reserved startup thread data in linked GEOS 2.x process geodes.
use strict;
use warnings;
use FindBin;

my @paths = @ARGV ? @ARGV : map {
    "$FindBin::Bin/../../../../Installed/Appl/Breadbox/BbxBrow/$_.geo"
} qw(bbxbrowec bbxbrow);

for my $path (@paths) {
    open my $file, '<:raw', $path or die "$path: $!\n";
    local $/;
    my $data = <$file>;
    length($data) >= 344 && substr($data, 0, 4) eq "\xc7E\xc1S"
        or die "$path: expected a GEOS 2.x geode\n";
    unpack('v', substr($data, 256, 2)) & 0x8000
        or die "$path: expected a process geode\n";
    my ($resources, $libraries, $exports) =
        unpack('v3', substr($data, 264, 6));
    my $table = 344 + 14 * $libraries + 4 * $exports;
    $resources >= 2 && $table + 10 * $resources <= length($data)
        or die "$path: invalid resource table\n";
    my $size = unpack('v', substr($data, $table + 2, 2));
    my $offset = 256 + unpack('V',
        substr($data, $table + 2 * $resources + 4, 4));
    $size >= 64 && $offset + $size <= length($data)
        or die "$path: invalid dgroup resource\n";

    # GeoWrite sets only TPD_stackBot (offset 18); other fields start at zero.
    for my $byte (0 .. 63) {
        next if $byte == 18 || $byte == 19;
        my $value = ord(substr($data, $offset + $byte, 1));
        $value == 0 or die sprintf(
            "%s: corrupt startup thread data at byte %d: 0x%02x\n",
            $path, $byte, $value);
    }
    print "$path: startup thread data is clean\n";
}
