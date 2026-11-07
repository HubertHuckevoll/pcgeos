#!/usr/bin/env perl
##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     PDF Host Regression Tests
# FILE:       check_path_pixels.pl
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# ROUTINES:
#     main - Check representative path and clipping pixel samples
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Verify holes, clipping and path transform behavior in rendered pages.
#     Use interior pixels away from antialiasing edges.
#
##############################################################################

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
   [50,150,0,0,255],[100,150,255,255,255],
   [130,150,0,0,255],[160,150,255,255,255],
   [401,203,0,0,255],[403,206,255,255,255],
   [408,203,0,0,255],[410,206,255,255,255],[420,203,255,255,255],
   [460,460,0,0,255],[485,485,255,255,255],[485,510,255,255,255],
   [495,510,0,0,255],[535,510,0,0,255],[545,510,255,255,255],
   [460,491,0,0,255],[460,492,0,0,255]) :
   ([160,110,0,0,255],[160,70,255,255,255],[160,180,255,255,255]);
 for my $check (@checks) {
  my ($x,$y,@expected)=@$check;
  my @got=unpack 'C3',substr($ppm,3*($y*$w+$x),3);
  "@got" eq "@expected" or die "page $page pixel ($x,$y): @got expected @expected\n";
 }
}
print "Path pixels: holes, inherited replacement, window/app clips and transforms verified\n";
