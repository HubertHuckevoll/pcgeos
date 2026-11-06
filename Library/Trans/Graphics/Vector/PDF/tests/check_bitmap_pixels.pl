#!/usr/bin/env perl
# Independent rendered-pixel oracle: RGB channel order, row order, stencil
# polarity, transparent zero bits, and a width not divisible by eight.
use strict;use warnings;
open my $f,'<:raw',$ARGV[0] or die "$ARGV[0]: $!";
local $/;my $ppm=<$f>;
$ppm =~ s/\AP6\s+(\d+)\s+(\d+)\s+255\r?\n// or die "expected binary PPM\n";
my ($width,$height)=($1,$2);
length($ppm)==$width*$height*3 or die "PPM size mismatch\n";
sub pixel {
 my ($x,$y,@expected)=@_;
 my @got=unpack 'C3',substr($ppm,3*($y*$width+$x),3);
 "@got" eq "@expected" or die "pixel ($x,$y): @got; expected @expected\n";
}
pixel(80,80,255,0,0);pixel(140,80,0,255,0);
pixel(80,140,0,0,255);pixel(140,140,255,255,0);
pixel(55,205,255,0,0);pixel(65,205,0,0,255);pixel(135,205,255,0,0);
pixel(55,215,0,0,255);pixel(65,215,255,0,0);pixel(145,205,255,255,255);
print "bitmap rendered pixels: RGB/row order, stencil polarity and transparency verified\n";
