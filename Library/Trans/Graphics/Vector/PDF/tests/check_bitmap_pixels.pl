#!/usr/bin/env perl
##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     PDF Host Regression Tests
# FILE:       check_bitmap_pixels.pl
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# ROUTINES:
#     pixel - Compare one expected pixel against a rendered PPM
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Check rendered bitmap color channels, rows and transparency.
#     Read sample positions from the generated PPM image.
#
##############################################################################

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
pixel(75,310,255,0,0);pixel(125,310,0,255,0);pixel(175,310,0,0,255);
pixel(60,360,255,0,0);pixel(85,360,0,255,0);pixel(110,360,0,0,255);pixel(135,360,255,255,0);
pixel(55,405,255,0,0);pixel(65,405,0,0,255);pixel(135,405,255,0,0);
pixel(55,415,0,0,255);pixel(65,415,255,0,0);pixel(135,415,0,0,255);
pixel(55,425,0,0,255);pixel(145,405,0,0,255);
pixel(65,460,255,0,0);pixel(95,460,0,0,255);pixel(125,460,0,255,0);
pixel(55,505,255,0,0);pixel(65,505,0,0,255);pixel(135,505,255,0,0);
pixel(281,405,255,0,0);pixel(285,405,255,0,0);pixel(287,405,0,0,255);
print "bitmap rendered pixels: RGB/row order, stencil polarity and transparency verified\n";
