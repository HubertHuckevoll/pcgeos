#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

my $tool = "$FindBin::Bin/..";
sub read_file {
    open my $f, '<:raw', $_[0] or die "$_[0]: $!\n";
    local $/;
    return <$f>;
}
my $font = read_file("$tool/DejaVuSC.fnt");
die "wrong font name\n" unless substr($font, 13, 20) eq "DejaVuSC" . ("\0" x 12);
if (my $ttf = shift) {
    my $tmp = tempdir(CLEANUP => 1);
    system('python3', "$tool/make_DejaVuSC.py", $ttf, "$tmp/font.fnt", '--sizes', '10') == 0
        or die "generation failed\n";
    die "generation is not reproducible\n" unless $font eq read_file("$tmp/font.fnt");
}
my $strike = substr($font, unpack('V', substr($font, 47, 4)));
die "expected a 10 pt strike\n" unless unpack('v', substr($font, 43, 2)) == 10;
my ($first, $last) = unpack('CC', substr($strike, 40, 2));
my ($min_x, $min_y, $max_y, $max_x, $height) = unpack('s<s<s<s<v', substr($strike, 58, 10));
my @glyph;
for my $code ($first .. $last) {
    my ($off, $frac, $advance, $flags) = unpack('vCvC', substr($strike, 71 + 8 * ($code - $first), 6));
    if ($flags & 8) {
        die "invalid missing-glyph sentinel at $code\n" unless $off == 0;
        next;
    }
    die "fractional bitmap advance at $code\n" if $frac || !$advance;
    my ($w, $h, $y, $x) = unpack('CCcc', substr($strike, $off, 4));
    my $bits = substr($strike, $off + 4, (($w + 7) >> 3) * $h);
    $glyph[$code] = [$w, $h, $y, $x, $bits];
    next unless $w && $h;
    die "glyph outside declared bounds at $code\n" if
        $x < $min_x || $y < $min_y || $x + $w > $max_x || $y + $h > $max_y;
    my $expected = ($x < 0 ? 64 : 0) | ($y < 0 ? 32 : 0) | ($y + $h > $height ? 16 : 0);
    die "wrong glyph extent flags at $code\n" unless ($flags & 112) == $expected;
}
# Drawing the absent logo must fall back to a valid default glyph.
die "default glyph is missing\n" unless defined $glyph[ord(substr($strike, 42, 1))];
die "expected an absent logo glyph\n" if defined $glyph[0xf0];
# Plain lowercase letters must share a baseline, especially the letter t.
my $baseline = $glyph[ord('n')][2] + $glyph[ord('n')][1];
for my $code (unpack('C*', 'aentx')) {
    die "inconsistent baseline at $code\n" unless $glyph[$code][2] + $glyph[$code][1] == $baseline;
}
# FontBuf metrics must describe the actual raster, without changing its box.
my ($font_height, $accent, $mean, $font_baseline, $descent, $leading, $under, $strike_pos) = map {
    my ($frac, $whole) = unpack('Cv', substr($strike, $_, 3));
    $whole + $frac / 256;
} (13, 16, 19, 25, 28, 31, 43, 49);
die "font pixels were resized\n" unless $glyph[ord('H')][1] == 8 && $glyph[ord('x')][1] == 6;
die "font box changed\n" unless $font_height == 14 && $height == 14 && $leading == 0;
die "incorrect baseline metric\n" unless $font_baseline == $baseline;
die "incorrect ascent or mean metric\n" unless $accent == $glyph[ord('H')][2] && $mean == $glyph[ord('x')][1];
die "incorrect descent metric\n" unless $descent == $font_height - $baseline;
die "incorrect decoration metrics\n" unless $under == $baseline + 1 && $strike_pos == $baseline - int($mean / 2);
# A euro must keep both horizontal bars, not collapse into a C.
my ($w, $h, undef, undef, $bits) = @{$glyph[0xdb]};
die "euro too small\n" unless $w >= 5 && $w <= 8 && $h >= 7;
my @rows = unpack('C*', $bits);
die "euro crossbars missing\n" unless (grep { ($_ & 224) == 224 } @rows) == 2;
# GEOS's y/Y acute slots must contain accented letters, not MacRoman fi/fl.
for my $pair ([0x79, 0xde], [0x59, 0xdf]) {
    my ($plain, $accent) = map { $glyph[$_] } @$pair;
    die "wrong y acute glyph\n" unless $accent->[0] == $plain->[0] &&
        $accent->[1] > $plain->[1] && substr($accent->[4], -length($plain->[4])) eq $plain->[4] &&
        $accent->[2] + $accent->[1] == $plain->[2] + $plain->[1];
}
print "DejaVuSC spacing, baseline, bounds, missing-glyph, euro and accented-letter checks passed\n";
