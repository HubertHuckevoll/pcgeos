#!/usr/bin/env perl
# Check PNG chunk integrity and require a complete zlib stream.

use strict;
use warnings;
use Compress::Raw::Zlib qw(crc32 Z_OK Z_BUF_ERROR Z_STREAM_END);

sub check_png
{
    my ($path) = @_;
    open my $file, '<:raw', $path or die "$!\n";
    local $/;
    my $data = <$file>;
    defined $data or die "$!\n";
    close $file or die "$!\n";
    die "bad PNG signature\n" unless substr($data, 0, 8) eq "\x89PNG\r\n\x1a\n";

    my $offset = 8;
    my $idat = '';
    my $saw_iend = 0;
    while ($offset + 12 <= length $data) {
        my $length = unpack('N', substr($data, $offset, 4));
        my $chunk_type = substr($data, $offset + 4, 4);
        my $end = $offset + 12 + $length;
        die "truncated chunk\n" if $end > length $data;
        my $chunk_data = substr($data, $offset + 8, $length);
        my $expected_crc = unpack('N', substr($data, $end - 4, 4));
        die "bad $chunk_type CRC\n"
            if crc32($chunk_type . $chunk_data) != $expected_crc;
        if ($chunk_type eq 'IDAT') {
            $idat .= $chunk_data;
        } elsif ($chunk_type eq 'IEND') {
            $saw_iend = 1;
        }
        $offset = $end;
    }

    my ($stream, $status) = Compress::Raw::Zlib::Inflate->new();
    die "zlib error: $status\n" unless $status == Z_OK;
    my $output = '';
    $status = $stream->inflate($idat, $output);
    die "zlib error: $status\n"
        unless $status == Z_OK || $status == Z_BUF_ERROR || $status == Z_STREAM_END;
    die "unfinished zlib stream\n" unless $status == Z_STREAM_END;
    die "missing or malformed IEND\n" unless $saw_iend && $offset == length $data;
}

unless (@ARGV) {
    print STDERR "usage: check_png.pl FILE...\n";
    exit 1;
}

for my $filename (@ARGV) {
    eval { check_png($filename); 1 } or do {
        print STDERR "$filename: $@";
        exit 1;
    };
    print "$filename: OK\n";
}
