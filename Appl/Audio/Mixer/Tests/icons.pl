#!/usr/bin/perl
# Implemented with ChatGPT Codex, prompted by MeyerK
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

chdir "$FindBin::Bin/../../../.." or die $!;
my $write = @ARGV == 1 && $ARGV[0] eq '--write';
die "Usage: perl icons.pl [--write]\n" if @ARGV && !$write;
my $source = 'Appl/Audio/Mixer/Art/mixer.pcx';
open my $pcx_in, '<:raw', $source or die $!;
my $pcx = do { local $/; <$pcx_in> };
close $pcx_in;
my ($width, $height) = (unpack('v', substr($pcx,8,2))+1,
                        unpack('v', substr($pcx,10,2))+1);
my $stride = unpack('v', substr($pcx,66,2));
ord(substr($pcx,3,1)) == 1 && ord(substr($pcx,65,1)) == 4
    or die "Source must be a four-plane PCX\n";
my @mask = grep { substr($pcx,16+3*$_,3) eq pack('C3',255,0,255) } 0..15;
@mask == 1 or die "Source needs one pure magenta palette entry\n";
my $mask = $mask[0];
my @planes;
my $pos = 128;
while ($pos < length($pcx)) {
    my $value = ord(substr($pcx,$pos++,1));
    my $count = 1;
    if (($value & 0xc0) == 0xc0) {
        $count = $value & 0x3f;
        $pos < length($pcx) or die "Truncated PCX run\n";
        $value = ord(substr($pcx,$pos++,1));
    }
    push @planes, ($value) x $count;
}
@planes == $stride * 4 * $height or die "Wrong PCX payload size\n";
my @pixels;
for my $y (0..$height-1) {
    for my $x (0..$width-1) {
        my $pixel = 0;
        for my $plane (0..3) {
            $pixel |= (($planes[($y*4+$plane)*$stride+int($x/8)]
                >> (7-$x%8)) & 1) << $plane;
        }
        push @pixels, $pixel;
    }
}
my $temp = tempdir(CLEANUP => 1);
# App columns retain the full 8:5 source frame; EGA/HGC/CGA compensate
# for driver pixel shapes. The last three columns use the small image.
my @formats = (
    ['VGA', 48, 30, 0,   'standard', 'icon', 'normal',       0],
    ['HGA', 48, 30, 49,  'standard', 'icon', 'normal',       1],
    ['EGA', 48, 30, 98,  'standard', 'icon', 'squished',     0],
    ['HGC', 48, 30, 147, 'standard', 'icon', 'squished',     1],
    ['CGA', 48, 14, 196, 'tiny',     'icon', 'verySquished', 1],
    ['TC',  15, 15, 245, 'tiny',     'tool', 'normal',       0],
    ['TM',  15, 15, 261, 'tiny',     'tool', 'normal',       1],
    ['TCGA',15, 10, 277, 'tiny',     'tool', 'verySquished', 1]
);
# Frame heights rounded to whole scanlines, based on driver DI_hRes/DI_vRes:
# VGA 64/64, EGA 64/47, HGC 72/49, CGA 64/(200/7).
for my $frame ([0,30,0,64,64], [98,22,4,64,47],
               [147,20,5,72,49], [196,13,0,64,28]) {
    my ($left,$rows,$top,$h_dpi,$v_dpi) = @$frame;
    abs(48 / ($rows * $h_dpi / $v_dpi) - 8/5) < 0.05
        or die "Frame lost its displayed 8:5 proportions\n";
    my $panel_h = $left == 196 ? 14 : 30;
    # The supplied big image is 1586x992; its foreground spans
    # (301,41)..(1309,958). Preserve that placement, within raster rounding.
    my ($min_x,$min_y,$max_x,$max_y) = (48,$panel_h,-1,-1);
    for my $y (0..$panel_h-1) {
        for my $x (0..47) {
            next if $pixels[$y*$width+$left+$x] == $mask;
            $min_x = $x if $x < $min_x;
            $max_x = $x if $x > $max_x;
            $min_y = $y if $y < $min_y;
            $max_y = $y if $y > $max_y;
        }
    }
    abs($min_x-48*301/1586) <= 1.5 &&
    abs($max_x-48*1309/1586) <= 1.5 &&
    abs($min_y-$top-$rows*41/992) <= 1.5 &&
    abs($max_y-$top-$rows*958/992) <= 1.5
        or die "Original landscape composition was cropped or shifted\n";
    for my $y (0..$panel_h-1) {
        next if $y >= $top && $y < $top+$rows;
        for my $x (0..47) {
            $pixels[$y*$width+$left+$x] == $mask
                or die "Artwork exceeds the aspect-corrected frame\n";
        }
    }
}
my $expected = "/* Implemented with ChatGPT Codex, prompted by MeyerK */\n\n";
for my $format (@formats) {
    my ($name, $w, $h, $x, $size, $style, $aspect, $mono) = @$format;
    my $output = "$temp/$name.goh";
    system('cvtpcx', '-G', '-2', '-t', '-R',
        ($mono ? ('-f', '-b') : ("-m$mask")), "-a$aspect", "-s$size",
        "-S$style", "-w$w", "-h$h", "-x$x", "-nMixer$name",
        "-o$output", $source) == 0 or die "cvtpcx failed: $name\n";
    open my $in, '<:raw', $output or die $!;
    my $text = do { local $/; <$in> };
    close $in;
    $expected .= "$text\n";
    $text =~ /cachedSize = $w, $h;/ or die "$name: wrong cached size\n";
    for my $field ("size = $size;", "style = $style;",
                   "aspectRatio = $aspect;", 'color = '.($mono ? 'gray1;' : 'color4;')) {
        index($text, $field) >= 0 or die "$name: wrong metadata\n";
    }
    $text =~ /GS(?:Draw|Fill)BitmapAtCP\((\d+)\),\s*Bitmap\s*\($w,$h,([^,]+),([^\n]+)\),\s*(.*?)GSEndString/s
        or die "$name: missing bitmap\n";
    my ($length, $compression, $type, $data) = ($1, $2, $3, $4);
    my @bytes = map { hex $_ } $data =~ /0x([0-9a-f]+)/g;
    $length == 6 + @bytes or die "$name: incorrect GString bitmap length\n";
    my @raw;
    if ($compression eq 'BMC_PACKBITS') {
        while (@bytes) {
            my $control = shift @bytes;
            next if $control == 128;
            my $count = $control < 128 ? $control + 1 : 257 - $control;
            if ($control < 128) {
                @bytes >= $count or die "$name: truncated literal\n";
                push @raw, splice @bytes, 0, $count;
            } else {
                @bytes or die "$name: truncated run\n";
                push @raw, (shift @bytes) x $count;
            }
        }
    } else {
        @raw = @bytes;
    }
    my $row = int(($w + 7) / 8);
    if (!$mono) {
        $type =~ /BMF_4BIT.*BMT_MASK/ or die "$name: missing color mask\n";
        $row += int(($w + 1) / 2);
    } else {
        $type =~ /BMF_MONO/ or die "$name: not monochrome\n";
    }
    @raw == $row * $h or die "$name: wrong decoded bitmap size\n";
    my $pink = 0;
    for my $y (0..$h-1) {
        for my $col (0..$w-1) {
            my $source_pixel = $pixels[$y*$width+$x+$col];
            my $bit = ($raw[$y*$row+int($col/8)] >> (7-$col%8)) & 1;
            if ($mono) {
                $bit == ($source_pixel == 0)
                    or die "$name: monochrome pixels differ from PCX\n";
            } else {
                $bit == ($source_pixel != $mask)
                    or die "$name: transparency mask differs from PCX\n";
                next unless $bit;
                my $packed = $raw[$y*$row+int(($w+7)/8)+int($col/2)];
                my $pixel = ($packed >> ($col%2 ? 0 : 4)) & 15;
                $pixel == $source_pixel or die "$name: color pixels differ from PCX\n";
                $pink++ if $pixel == 13;
            }
        }
    }
    $mono || $pink or die "$name: visible pink details were lost\n";
}
if ($write) {
    open my $out, '>:raw', 'Appl/Audio/Mixer/token.goh' or die $!;
    print $out $expected;
    close $out or die $!;
}
open my $in, '<:raw', 'Appl/Audio/Mixer/token.goh' or die $!;
my $actual = do { local $/; <$in> };
close $in;
$actual eq $expected or die "token.goh differs from the editable PCX source\n";
print "Mixer icons: eight formats, proportions, masks, pixels and regeneration OK\n";
