#!/usr/bin/env perl
# Independent check of byte offsets, stream lengths and page references.
use strict;
use warnings;
my ($file, $expected_pages) = @ARGV;
die "usage: $0 file.pdf pages\n" unless defined $expected_pages;
open my $fh, '<:raw', $file or die "$file: $!";
local $/;
my $pdf = <$fh>;
$pdf =~ /^%PDF-1\.1\n/ or die "PDF 1.1 header missing\n";
$pdf =~ /startxref\n(\d+)\n%%EOF\n\z/ or die "trailer missing\n";
my $xref = $1;
substr($pdf, $xref) =~ /^xref\n0 (\d+)\n0000000000 65535 f \n/ or die "bad xref offset\n";
my $count = $1;
my $tail = substr($pdf, $xref);
my @entries = $tail =~ /^(\d{10}) 00000 n \n/mg;
@entries == $count - 1 or die "xref size mismatch\n";
for my $id (1 .. $#entries + 1) {
    substr($pdf, $entries[$id-1]) =~ /^\Q$id\E 0 obj\n/ or die "object $id offset wrong\n";
}
my $streams = 0;
while ($pdf =~ /\d+ 0 obj\n<< \/Length (\d+) 0 R >>\nstream\n/g) {
    my ($length_id, $start) = ($1, pos($pdf));
    $pdf =~ /^\Q$length_id\E 0 obj\n(\d+)\nendobj\n/m or die "length object missing\n";
    substr($pdf, $start + $1, 10) eq "endstream\n" or die "wrong stream length\n";
    ++$streams;
}
$streams == $expected_pages or die "wrong content stream count: $streams\n";
$pdf =~ /\/Type \/Pages \/Count (\d+) \/Kids \[([^\]]*)\]/ or die "pages missing\n";
my ($pages, $kids) = ($1, $2);
$pages == $expected_pages or die "wrong page count\n";
my @kids = $kids =~ /(\d+) 0 R/g;
@kids == $pages or die "wrong kids count\n";
for my $id (@kids) {
    substr($pdf, $entries[$id-1]) =~ /^\Q$id\E 0 obj\n<< \/Type \/Page / or die "invalid page reference\n";
}
print "$file: $pages pages, xref offsets and indirect stream lengths verified\n";
