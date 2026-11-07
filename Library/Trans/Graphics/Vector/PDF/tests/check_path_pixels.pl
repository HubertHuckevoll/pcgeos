#!/usr/bin/env perl
# One interior sample per visible path/clip behavior, away from antialias edges.
use strict;use warnings;
for my $page (1,2) {
 open my $f,'<:raw',$ARGV[$page-1] or die "$ARGV[$page-1]: $!";
 local $/;my $ppm=<$f>;
 $ppm =~ s/\AP6\s+(\d+)\s+(\d+)\s+255\r?\n// or die "expected PPM\n";
 my ($w,$h)=($1,$2);length($ppm)==$w*$h*3 or die "PPM size\n";
 my @checks=$page==1 ? ([30,30,0,0,255],[60,60,255,255,255],[20,50,255,0,0],
   [170,30,0,0,255],[230,30,0,0,255],[210,30,255,255,255],
   [310,60,0,0,255],[350,60,255,255,255],[281,21,255,255,255],
   [50,150,0,0,255],[100,150,255,255,255]) :
   ([55,40,0,0,255],[35,40,255,255,255],[90,40,255,255,255]);
 for my $check (@checks) {
  my ($x,$y,@expected)=@$check;
  my @got=unpack 'C3',substr($ppm,3*($y*$w+$x),3);
  "@got" eq "@expected" or die "page $page pixel ($x,$y): @got expected @expected\n";
 }
}
print "Path pixels: holes, inherited replacement, window/app clips and transforms verified\n";
