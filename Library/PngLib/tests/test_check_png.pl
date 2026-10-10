#!/usr/bin/env perl
use strict;
use warnings;
use Compress::Zlib qw(compress crc32);
use File::Temp qw(tempdir);
use FindBin;

sub chunk
{
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', crc32($type . $data));
}

sub run_check
{
    my $pid = open my $pipe, '-|';
    defined $pid or die "$!\n";
    if (!$pid) {
        open STDERR, '>&', STDOUT or die "$!\n";
        exec $^X, "$FindBin::Bin/check_png.pl", @_;
        die "exec: $!\n";
    }
    local $/;
    my $output = <$pipe>;
    close $pipe;
    return ($?, $output);
}

my $dir = tempdir(CLEANUP => 1);
my $signature = "\x89PNG\r\n\x1a\n";
my $header = chunk('IHDR', pack('NNCCCCC', 1, 1, 8, 0, 0, 0, 0));
my $stream = compress("\0\x7f");
my $idat = chunk('IDAT', $stream);
my $iend = chunk('IEND', '');
my $png = $signature . $header . $idat . $iend;
my @cases = (
    ['valid', $png, 'OK'],
    ['split IDAT', $signature . $header . chunk('IDAT', substr($stream, 0, 3)) .
        chunk('IDAT', substr($stream, 3)) . $iend, 'OK'],
    ['empty file', '', 'bad PNG signature'],
    ['bad signature', 'invalid!', 'bad PNG signature'],
    ['truncated chunk', $signature . substr($idat, 0, -1), 'truncated chunk'],
    ['bad CRC', $signature . $header . substr($idat, 0, -1) .
        chr(ord(substr($idat, -1)) ^ 1) . $iend, 'bad IDAT CRC'],
    ['no IDAT', $signature . $header . $iend, 'unfinished zlib stream'],
    ['bad zlib', $signature . $header . chunk('IDAT', 'invalid') . $iend, 'zlib error:'],
    ['bad zlib checksum', $signature . $header . chunk('IDAT',
        substr($stream, 0, -1) . chr(ord(substr($stream, -1)) ^ 1)) . $iend, 'zlib error:'],
    ['missing IEND', $signature . $header . $idat, 'missing or malformed IEND'],
    ['trailing bytes', $png . 'x', 'missing or malformed IEND'],
);
for my $length (0 .. length($stream) - 1) {
    push @cases, ["unfinished $length", $signature . $header .
        chunk('IDAT', substr($stream, 0, $length)) . $iend, 'unfinished zlib stream'];
}
for my $case (@cases) {
    my ($name, $data, $expected) = @$case;
    my $path = "$dir/$name.png";
    open my $file, '>:raw', $path or die "$!\n";
    print {$file} $data or die "$!\n";
    close $file or die "$!\n";
    my ($status, $output) = run_check($path);
    die "$name: $output" unless $status == ($expected eq 'OK' ? 0 : 256) &&
        $output =~ /\A\Q$path: $expected\E[^\n]*\n\z/;
}
my ($status, $output) = run_check();
die "usage: $output" unless $status == 256 && $output eq "usage: check_png.pl FILE...\n";
($status, $output) = run_check("$dir/missing.png");
die "missing file: $output" unless $status == 256 && index($output, "$dir/missing.png: ") == 0;
($status, $output) = run_check("$dir/valid.png", "$dir/split IDAT.png");
die "multiple valid files: $output" unless !$status &&
    $output eq "$dir/valid.png: OK\n$dir/split IDAT.png: OK\n";
($status, $output) = run_check("$dir/valid.png", "$dir/bad CRC.png", "$dir/split IDAT.png");
# stdout may be buffered until after the error on stderr.
die "multiple files: $output" unless $status == 256 &&
    index($output, "$dir/valid.png: OK\n") >= 0 &&
    index($output, "$dir/bad CRC.png: bad IDAT CRC\n") >= 0 &&
    index($output, "$dir/split IDAT.png") < 0;
print "PNG checker regression checks passed\n";
