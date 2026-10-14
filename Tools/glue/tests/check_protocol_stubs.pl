#!/usr/bin/env perl
# Link small OMF fixtures with the real Glue; no GEOS runtime is required.
use strict;
use warnings;
use Cwd qw(abs_path);
use FindBin;
use File::Temp qw(tempdir);

my $glue = abs_path($ARGV[0] || "$FindBin::Bin/../../../bin/glue")
    or die "Cannot find Glue\n";
my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;

sub write_file {
    my ($name, $data) = @_;
    open my $file, '>:raw', $name or die "$name: $!\n";
    print $file $data;
    close $file or die $!;
}
sub counted { return pack('C', length($_[0])) . $_[0]; }
sub record {
    my ($type, $data) = @_;
    my $bytes = pack('Cv', $type, length($data) + 1) . $data;
    my $sum = 0;
    $sum += $_ for unpack('C*', $bytes);
    return $bytes . pack('C', -$sum & 255);
}
sub segdef {
    my ($size, $name, $class) = @_;
    return record(0x98, pack('CvCCC', 0x48, $size, $name, $class, 0));
}
sub ledata {
    my ($segment, $offset, $data) = @_;
    return record(0xa0, pack('Cv', $segment, $offset) . $data);
}
sub object {
    my ($stub, $entry, $stub_size) = @_;
    $stub_size ||= 400;
    $entry ||= 'Entry';
    my $data = record(0x80, counted('fixture'));
    $data .= record(0x96, join('', map { counted($_) }
        qw(_DATA DATA CODE_TEXT CODE _BOGUS_PROTOMINORRELOCS DGROUP)));
    $data .= segdef(1536, 1, 2) . segdef(16, 3, 4);
    $data .= segdef($stub_size, 5, 4) if length $stub;
    $data .= record(0x9a, pack('C3', 6, 255, 1)); # DGROUP contains _DATA.
    $data .= record(0x90, pack('C2', 0, 2) . counted($entry) . pack('vC', 0, 0));
    $data .= ledata(1, 0, "\x5a" x 768) . ledata(1, 768, "\x5a" x 768);
    $data .= ledata(2, 0, "\xc3" . "\x90" x 15);
    return $data . $stub . record(0x8a, "\0");
}
sub link_fixture {
    my ($name, $expect_success) = @_;
    open my $params, '>>', "$name.gp" or die $!;
    print $params "tokenchars \"TST0\"\ntokenid 0\n";
    close $params or die $!;
    my @command = ($glue, '-G', '2', '-Og', "$name.gp", '-L.',
                   '-o', "$name.geo", ($name eq 'provider' ? '-l' : ()), "$name.obj");
    open my $log, '>', "$name.log" or die $!;
    open my $saved_out, '>&', \*STDOUT or die $!;
    open my $saved_err, '>&', \*STDERR or die $!;
    open STDOUT, '>&', $log or die $!;
    open STDERR, '>&', $log or die $!;
    my $result = system(@command);
    open STDOUT, '>&', $saved_out or die $!;
    open STDERR, '>&', $saved_err or die $!;
    if ($result == -1 || ($result & 127) || (($result == 0) != $expect_success)) {
        open my $file, '<', "$name.log" or die $!;
        print STDERR <$file>;
        die "$name: unexpected Glue exit status $result\n";
    }
}
sub inspect {
    my ($name, $protocol) = @_;
    open my $file, '<:raw', "$name.geo" or die $!;
    local $/;
    my $data = <$file>;
    substr($data, 0, 4) eq "\xc7E\xc1S" or die "$name: not a GEOS 2.x geode\n";
    my ($resources, $libraries, $exports) = unpack('v3', substr($data, 264, 6));
    $resources == 3 or die "$name: synthetic stub became a resource\n";
    if (defined $protocol) {
        $libraries == 1 && unpack('v', substr($data, 356, 2)) == $protocol
            or die "$name: lost the imported minor protocol requirement\n";
    }
    my $table = 344 + 14 * $libraries + 4 * $exports;
    my $offset = 256 + unpack('V', substr($data, $table + 2 * $resources + 4, 4));
    for my $byte (0 .. 63) {
        next if $byte == 18 || $byte == 19;
        ord(substr($data, $offset + $byte, 1)) == 0
            or die "$name: corrupt startup byte $byte\n";
    }
    my $payload = "\x5a" x 1536;
    substr($payload, 0, 2) = "\x5b\x5b" if $name eq 'real_backpatch';
    substr($data, $offset + 64, 1536) eq $payload
        or die "$name: initialized data changed\n";
    my $code_offset = 256 + unpack('V', substr($data, $table + 2 * $resources + 8, 4));
    my $code = $name eq 'real_relocation' ? "\x9a\0\0\0\0" . "\x90" x 11 : "\xc3" . "\x90" x 15;
    substr($data, $code_offset, 16) eq $code
        or die "$name: normal code emission changed\n";
    unpack('v', substr($data, $table + 6 * $resources + 4, 2)) ==
        ($name eq 'real_relocation' ? 4 : 0)
        or die "$name: wrong runtime relocation count\n";
    return substr($data, $offset, 1600);
}

# A library whose marker requires minor protocol 1, without any runtime call.
write_file('provider.obj', object('', 'ProviderEntry'));
write_file('provider.gp', "name provider.lib\ntype library, single\nexport ProviderEntry\nincminor RequiredProtocol\n");
link_fixture('provider', 1);
-f 'provider.ldf' or die "Glue did not produce the fixture library\n";

my $external = record(0x8c, counted('RequiredProtocol') . "\0");
# Segment-relative far pointer at byte 1; frame=target, target=external 1.
my $fixup = record(0x9c, pack('C4', 0xcc, 1, 0x56, 1));
my $call = "\x9a\0\0\0\0";
my @cases = (
    ['baseline', '', undef],
    ['ledata', ledata(3, 0, "\xa5" x 400), undef],
    ['lidata', record(0xa2, pack('CvvvCC', 3, 0, 400, 0, 1, 0xa5)), undef],
    ['backpatch_byte', record(0xb2, pack('CCvv', 3, 0, 0, 0xa5)), undef],
    ['backpatch_word', record(0xb2, pack('CCvv', 3, 1, 0, 0xa5a5)), undef],
    ['lidata_large', record(0xa2, pack('CvvvCC', 3, 0, 30000, 0, 1, 0xa5)), undef, 30000],
    ['unreferenced', $external . ledata(3, 0, "\xa5" x 400), 0],
    ['real_backpatch', record(0xb2, pack('CCvv', 1, 0, 0, 1)) .
        record(0xb2, pack('CCvv', 1, 1, 1, 1)), undef],
    ['real_relocation', record(0x8c, counted('ProviderEntry') . "\0") .
        ledata(2, 0, $call . "\x90" x 11) . $fixup, 0],
    ['protocol', $external . ledata(3, 0, $call . "\xa5" x 395) . $fixup, 1],
    ['split_protocol', $external . ledata(3, 0, "\x9a") .
        ledata(3, 1, "\0" x 4 . "\xa5" x 395) .
        record(0x9c, pack('C4', 0xcc, 0, 0x56, 1)), 1],
);
my $baseline;
for my $case (@cases) {
    my ($name, $stub, $protocol, $size) = @$case;
    write_file("$name.obj", object($stub, 'Entry', $size));
    # The PROCESS attribute makes Glue reserve and initialize startup TPD.
    write_file("$name.gp", "name " . substr($name, 0, 8) . ".lib\ntype library, process, single\n" .
        (defined $protocol ? "library provider\n" : ''));
    link_fixture($name, 1);
    my $data = inspect($name, $protocol);
    $baseline = $data if $name eq 'baseline';
    ($name eq 'real_backpatch' || $data eq $baseline) or die "$name: startup or initialized data differs from baseline\n";
}
# Discarding a stub must not silence undefined protocol references.
write_file('missing.obj', object(record(0x8c, counted('MissingProtocol') . "\0") .
    ledata(3, 0, $call) . $fixup));
write_file('missing.gp', "name missing.lib\ntype library, process, single\n");
link_fixture('missing', 0);
open my $missing_log, '<', 'missing.log' or die $!;
join('', <$missing_log>) =~ /MissingProtocol.*undefined/
    or die "Missing reference failed for the wrong reason\n";
print "Glue protocol stubs: data, fixups, backpatches and missing references passed\n";
