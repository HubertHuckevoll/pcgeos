#!/usr/bin/env perl
# Implemented with ChatGPT Codex, prompted by MeyerK
# perl Tools/misc/cvtpcx/Tests/png.pl /path/to/cvtpcx [old-cvtpcx]
# Requires Perl's Compress::Zlib; no image programs or GEOS runtime needed.
use strict;
use warnings;
use Compress::Zlib qw(compress crc32);
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $tool = abs_path(shift || 'Installed/Tools/misc/cvtpcx/linux.md/cvtpcx.');
my $old = @ARGV ? abs_path(shift) : undef;
my $tmp = tempdir(CLEANUP => 1);
my $checks = 0;
my @palette = (
    [0,0,0], [0,0,170], [0,170,0], [0,170,170],
    [170,0,0], [170,0,170], [170,85,0], [170,170,170],
    [85,85,85], [85,85,255], [85,255,85], [85,255,255],
    [255,85,85], [255,85,255], [255,255,85], [255,255,255]
);

sub check { die "FAIL: $_[1]\n" unless $_[0]; $checks++; }
sub write_file {
    my ($name, $data) = @_;
    open my $f, '>:raw', "$tmp/$name" or die $!;
    print $f $data or die $!;
    close $f or die $!;
}
sub read_file {
    open my $f, '<:raw', $_[0] or die $!;
    local $/;
    return <$f>;
}
sub chunk {
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', crc32($type.$data));
}
sub png {
    my ($w, $h, $depth, $type, $rows, $colors, $alpha, $interlace) = @_;
    my $data = "\x89PNG\r\n\x1a\n" .
               chunk('IHDR', pack('NNCCCCC', $w, $h, $depth, $type, 0, 0, $interlace || 0));
    $data .= chunk('PLTE', pack('C*', map { @$_ } @$colors)) if $colors;
    $data .= chunk('tRNS', $alpha) if defined $alpha;
    return $data . chunk('IDAT', compress($rows)) . chunk('IEND', '');
}
sub indexed_rows {
    my ($w, $h, $depth, $pixels) = @_;
    my $rows = '';
    for my $y (0 .. $h-1) {
        my $bits = join '', map { sprintf('%0*b', $depth, $_) }
                              @$pixels[$y*$w .. ($y+1)*$w-1];
        $bits .= '0' x ((8-length($bits)%8)%8);
        $rows .= "\0" . pack('B*', $bits);
    }
    return $rows;
}
sub pcx {
    my ($w, $h, $depth, $pixels, $colors) = @_;
    my $planes = $depth == 4 ? 4 : 1;
    my $bpl = $depth == 4 ? int(($w+7)/8) : $w;
    $bpl += $bpl % 2;
    my $data = pack('C4v6', 10, 5, 1, $depth == 4 ? 1 : 8,
                    0, 0, $w-1, $h-1, 72, 72) .
               pack('C*', map { @$_ } @$colors[0..15]) .
               pack('CCvv', 0, $planes, $bpl, 1) . ("\0" x 58);
    for my $y (0 .. $h-1) {
        my $line = '';
        for my $plane (0 .. $planes-1) {
            if ($depth == 8) {
                $line .= pack('C*', @$pixels[$y*$w .. ($y+1)*$w-1]) . ("\0" x ($bpl-$w));
            } else {
                my $bits = join '', map { ($_ >> $plane) & 1 }
                                       @$pixels[$y*$w .. ($y+1)*$w-1];
                $line .= pack('B*', $bits . '0' x ($bpl*8-$w));
            }
        }
        $data .= join '', map { $_ >= 192 ? pack('CC', 193, $_) : chr $_ } unpack('C*', $line);
    }
    $data .= chr(12) . pack('C*', map { @$_ } @$colors) if $depth == 8;
    return $data;
}
sub run {
    my ($exe, @args) = @_;
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        open STDERR, '>', "$tmp/diagnostics" or die $!;
        exec {$exe} $exe, @args;
        die "exec: $!";
    }
    waitpid $pid, 0;
    return $?;
}
sub convert {
    my ($name, $w, $h, @args) = @_;
    my $status = run($tool, '-G', '-2', '-g', '-u', '-nTest', "-w$w", "-h$h",
                     @args, "-o$tmp/output.goh", "$tmp/$name");
    die read_file("$tmp/diagnostics") if $status;
    return read_file("$tmp/output.goh");
}
sub payload {
    my ($text) = @_;
    my @bytes = map hex, $text =~ /0x([0-9a-f]{2})/ig;
    splice @bytes, 0, ($text =~ /BMF_4BIT/ ? 48 : 768) if $text =~ /BMT_PALETTE/;
    if ($text =~ /BMC_PACKBITS/) {
        my @decoded;
        while (@bytes) {
            my $n = shift @bytes;
            if ($n < 128) { push @decoded, splice @bytes, 0, $n+1; }
            # GEOS treats control 128 as a 129-byte run, not a TIFF NOP.
            else { push @decoded, (shift @bytes) x (257-$n); }
        }
        @bytes = @decoded;
    }
    return pack('C*', @bytes);
}

# Odd row widths exercise PNG's packed indices across scanline boundaries.
my @pixels = map { $_ % 16 } 0..26;
write_file('four.png', png(9, 3, 4, 3, indexed_rows(9,3,4,\@pixels), \@palette));
write_file('four.pcx', pcx(9,3,4,\@pixels,\@palette));
my $four = convert('four.png',9,3);
check(payload($four) eq pack('C*',0x01,0x23,0x45,0x67,0x80,
                                  0x9a,0xbc,0xde,0xf0,0x10,
                                  0x23,0x45,0x67,0x89,0xa0), '4-bit packing');
check(payload($four) eq payload(convert('four.pcx',9,3)), 'equivalent PCX and PNG');
check(payload(convert('four.png',9,3,'-E')) eq payload($four), 'ESP output');
check(run($tool,'-2','-g','-u','-nTest','-w9','-h3',"-o$tmp/output.ui","$tmp/four.png") == 0 &&
      payload(read_file("$tmp/output.ui")) eq payload($four), 'UIC output');
check(run($tool,'-G','-2','-u','-nTest','-w9','-h3',"-o$tmp/moniker.goh","$tmp/four.png") == 0 &&
      read_file("$tmp/moniker.goh") =~ /\@visMoniker TestMoniker/, 'GOH moniker wrapper');
check(payload(convert('four.png',9,3,'-c8')) eq pack('C*',@pixels), 'explicit 8-bit output');
for my $depth (1,2) {
    my @p = map { $_ % (1 << $depth) } 0..26;
    my @colors = @palette[0..(1 << $depth)-1];
    write_file('packed.png', png(9,3,$depth,3,indexed_rows(9,3,$depth,\@p),\@colors));
    check(length(payload(convert('packed.png',9,3))) == 15, "$depth-bit indexed PNG");
}

my @colors = (@palette, map { [$_, 255-$_, $_] } 16..255);
my @eight = (255,1,0,17,128,254);
write_file('eight.png', png(3,2,8,3,indexed_rows(3,2,8,\@eight),\@colors));
write_file('eight.pcx', pcx(3,2,8,\@eight,\@colors));
my $eight = convert('eight.png',3,2);
check($eight =~ /BMF_8BIT/ && $eight =~ /BMT_PALETTE/, 'custom 8-bit palette');
my @palette_bytes = map hex, $eight =~ /0x([0-9a-f]{2})/ig;
check(pack('C*',@palette_bytes[0..767]) eq pack('C*',map { @$_ } @colors),
      '8-bit palette colors retained');
check(payload($eight) eq pack('C*',@eight), '8-bit indices retained');
check(payload($eight) eq payload(convert('eight.pcx',3,2)), '8-bit PCX equivalence');

write_file('rgba.png', png(5,1,8,6,"\0" . pack('C*',
    0,0,0,255, 255,255,255,255, 0,0,0,127, 0,0,0,128, 255,255,255,0)));
check(payload(convert('rgba.png',5,1)) eq pack('C*',0xd0,0x0f,0,0), 'RGBA alpha threshold');
check(payload(convert('rgba.png',5,1,'-b')) eq pack('C*',0xd0,0x90), 'masked monochrome');
check(payload(convert('rgba.png',5,1,'-B')) eq pack('C*',0xd0,0x90), 'inverse monochrome');
my @same = ([170,0,0], [170,0,0], [0,0,170], [255,255,255]);
my @keys = (0,1,2,3,0);
write_file('alpha.png', png(5,1,4,3,indexed_rows(5,1,4,\@keys),\@same,pack('C*',255,0,127,128)));
check(payload(convert('alpha.png',5,1)) eq pack('C*',0x98,0x40,0x0f,0x40),
      'same RGB can be opaque and transparent');
write_file('key255.png', png(3,1,8,3,indexed_rows(3,1,8,[255,1,0]),\@colors,pack('C*',255,0)));
check(payload(convert('key255.png',3,1)) eq pack('C*',0xa0,255,0,0), 'opaque index 255');
check(payload(convert('key255.png',3,1,'-m255')) eq pack('C*',0x20,0,0,0), 'mask index 255');
check(payload(convert('four.png',2,2,'-x-1','-y-1')) eq pack('C*',0,0,0x40,0),
      'negative offsets pad with transparency');
check(payload(convert('four.png',2,1,'-x20')) eq pack('C*',0,0), 'crop outside source');
write_file('rgb.png', png(3,1,8,2,"\0".pack('C*',0,0,0, 255,255,255, 0,0,170)));
check(payload(convert('rgb.png',3,1,'-c8')) eq pack('C*',0,15,1), 'RGB maps to GEOS 256 colors');
write_file('gray16.png', png(3,1,16,0,"\0".pack('n*',0,65535,0)));
check(payload(convert('gray16.png',3,1,'-b')) eq pack('C*',0xa0), '16-bit grayscale');
write_file('adam7.png', png(1,1,8,6,"\0".pack('C*',0,0,170,255),undef,undef,1));
check(payload(convert('adam7.png',1,1)) eq chr(0x10), 'Adam7 PNG');
my $adam7 = '';
for my $pass ([0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],
              [0,2,2,4],[1,0,2,2],[0,1,1,2]) {
    my ($sx,$sy,$dx,$dy) = @$pass;
    next if $sx >= 9;
    for (my $y=$sy; $y<3; $y+=$dy) {
        my @p;
        for (my $x=$sx; $x<9; $x+=$dx) { push @p, $pixels[$y*9+$x]; }
        $adam7 .= indexed_rows(scalar(@p),1,4,\@p);
    }
}
write_file('adam7-palette.png', png(9,3,4,3,$adam7,\@palette,undef,1));
check(payload(convert('adam7-palette.png',9,3)) eq payload($four), 'all Adam7 passes');

# Compression must reconstruct the same rows, including mask rows.
write_file('runs.png', png(64,8,8,6,scalar(("\0".(pack('C*',0,0,170,255) x 64)) x 8)));
my $runs = convert('runs.png',64,8);
check(run($tool,'-G','-2','-g','-nTest','-w64','-h8',"-o$tmp/packed.goh","$tmp/runs.png") == 0,
      'compressed conversion succeeds');
my $packed = read_file("$tmp/packed.goh");
check($packed =~ /BMC_PACKBITS/ && payload($packed) eq payload($runs), 'PackBits round trip');
write_file('long-run.png',png(258,1,8,2,"\0".(pack('C*',0,0,170) x 258)));
check(run($tool,'-G','-2','-g','-nTest','-w258','-h1',"-o$tmp/packed.goh","$tmp/long-run.png") == 0 &&
      payload(read_file("$tmp/packed.goh")) eq (chr(0x11) x 129), '129-byte GEOS PackBits run');

check(run($tool,'-G','-g','-u','-w3','-h2','-nOne',"-o$tmp/one.goh","$tmp/eight.png",
          '-nTwo',"-o$tmp/two.goh","$tmp/four.png",
          '-nThree',"-o$tmp/three.goh","$tmp/four.pcx") == 0, 'mixed input batch');
check(read_file("$tmp/one.goh") =~ /BMF_8BIT/ &&
      read_file("$tmp/two.goh") =~ /BMF_4BIT/ &&
      read_file("$tmp/three.goh") =~ /BMF_4BIT/, 'per-file depth and palette reset');
my @grid = map { $_ % 16 } 0..(400*42-1);
write_file('grid.png',png(400,42,4,3,indexed_rows(400,42,4,\@grid),\@palette));
my $grid = convert('grid.png',48,30,'-l');
check(scalar(() = $grid =~ /Bitmap\s*\(/g) == 6, 'all standard grid formats');

# Decode/size failures must leave an existing destination unchanged.
my $bad = read_file("$tmp/rgba.png");
substr($bad,-1,1) = chr(ord(substr($bad,-1,1)) ^ 1);
write_file('bad.png',$bad);
write_file('short.png',substr($bad,0,40));
write_file('invalid-index.png',png(1,1,8,3,"\0\1",[[0,0,0]]));
write_file('large.png',png(32768,1,8,6,''));
for my $case (['bad.png'],['short.png'],['invalid-index.png'],['large.png'],
              ['rgba.png','-w32767','-h32767'],['rgba.png','-w0'],
              ['rgba.png','-w999999999999999999999'],['rgba.png','-xjunk'],['rgba.png','-c7']) {
    write_file('keep.goh','keep');
    my ($input,@opts) = @$case;
    check(run($tool,'-G','-nTest',@opts,"-o$tmp/keep.goh","$tmp/$input") != 0,
          "reject $input @opts");
    check(read_file("$tmp/keep.goh") eq 'keep', 'failed conversion preserves output');
}
my $original = read_file("$tmp/four.png");
check(run($tool,"-o$tmp/four.png","$tmp/four.png") != 0 &&
      read_file("$tmp/four.png") eq $original, 'cannot overwrite input');
write_file('renamed.pcx', $original);
check(payload(convert('renamed.pcx',9,3)) eq payload($four), 'signature detection');

# Custom 4-bit palettes preserve colors and indices instead of mapping to EGA.
my @custom = map { [17+$_*7, 23+$_*5, 31+$_*3] } 0..15;
write_file('custom.png',png(9,3,4,3,indexed_rows(9,3,4,\@pixels),\@custom));
write_file('custom.pcx',pcx(9,3,4,\@pixels,\@custom));
my $custom = convert('custom.png',9,3,'-p');
check($custom =~ /BMF_4BIT/ && $custom =~ /BMT_PALETTE/ &&
      $custom =~ /BMT_COMPLEX/ && $custom !~ /BMT_MASK/, 'custom 4-bit header without mask');
check($custom =~ /0,0, 3,0, 0,0, 70,0, 20,0, 72,0, 72,0,/ &&
      $custom =~ /16,0, \/\* palette length/, '4-bit palette offsets and count');
my @custom_bytes = map hex, $custom =~ /0x([0-9a-f]{2})/ig;
check(pack('C*',@custom_bytes[0..47]) eq pack('C*',map { @$_ } @custom),
      'custom RGB palette retained');
check(payload($custom) eq payload($four), 'custom PNG indices retained');
check(payload(convert('custom.pcx',9,3,'-p')) eq payload($custom), 'custom PCX indices retained');
my $mapped = convert('custom.png',9,3);
check($mapped !~ /BMT_PALETTE/ && payload($mapped) ne payload($custom), 'default still maps to GEOS colors');
my $esp = convert('custom.png',9,3,'-p','-E');
check($esp =~ /CBitmap <<9,3,0,BMF_4BIT or mask BMT_PALETTE or mask BMT_COMPLEX>, 0, 3, 0, 70, 20, 72, 72>/ &&
      $esp =~ /word\s+16\b/ && payload($esp) eq payload($custom), 'ESP custom palette');
check(run($tool,'-p','-g','-u','-nTest','-w9','-h3',"-o$tmp/palette.ui","$tmp/custom.pcx") == 0 &&
      read_file("$tmp/palette.ui") =~ /CBitmap <<9,3,0,BMF_4BIT/,
      'UIC custom PCX palette');
check(run($tool,'-G','-p','-u','-nTest','-w9','-h3',"-o$tmp/palette.goh","$tmp/custom.png") == 0,
      'custom moniker conversion');
my $moniker = read_file("$tmp/palette.goh");
check($moniker =~ /color = color8;/ && $moniker =~ /style = icon;/ &&
      $moniker =~ /GSDrawBitmapAtCP\(85\)/ && payload($moniker) eq payload($custom),
      'custom moniker display class, implied -2 and bitmap byte count');
my $alpha = convert('alpha.png',5,1,'-p');
check($alpha =~ /BMT_MASK/ && payload($alpha) eq pack('C*',0x98,0,0x03,0),
      'palette alpha is independent of RGB mapping');
check(payload(convert('custom.png',9,3,'-p','-m1')) =~ /^\xbf\x80/,
      'custom PNG source index mask');
check(payload(convert('custom.pcx',9,3,'-p','-m1')) =~ /^\xbf\x80/,
      'custom PCX source index mask');
my $mono = convert('custom.png',9,3,'-p','-b');
check($mono =~ /BMF_MONO/ && $mono !~ /BMT_PALETTE/, 'monochrome has no palette');
write_file('small-palette.png',png(3,1,1,3,indexed_rows(3,1,1,[0,1,0]),[[@{$custom[0]}],[@{$custom[1]}]]));
my @small = map hex, convert('small-palette.png',3,1,'-p') =~ /0x([0-9a-f]{2})/ig;
check(pack('C*',@small[0..47]) eq pack('C*',@{$custom[0]},@{$custom[1]},(0)x42),
      'short palettes padded to 16 entries');
write_file('byte-indices.png',png(9,3,8,3,indexed_rows(9,3,8,\@pixels),\@custom));
check(payload(convert('byte-indices.png',9,3,'-p')) eq payload($custom),
      '8-bit PNG indices with a 16-entry palette');
my @tall = (0) x 300;
write_file('tall.png',png(1,300,1,3,indexed_rows(1,300,1,\@tall),[[17,23,31]]));
check(convert('tall.png',1,300,'-p') =~ /0,0, 44,1, 0,0, 70,0, 20,0,/,
      'complex header splits 16-bit scan count into bytes');
my @solid = (1) x (64*8);
write_file('palette-runs.png',png(64,8,4,3,indexed_rows(64,8,4,\@solid),\@custom));
check(run($tool,'-G','-p','-g','-nTest','-w64','-h8',"-o$tmp/palette.goh","$tmp/palette-runs.png") == 0 &&
      read_file("$tmp/palette.goh") =~ /BMC_PACKBITS/ &&
      payload(read_file("$tmp/palette.goh")) eq (chr(0x11) x (32*8)), 'custom palette PackBits');
check(run($tool,'-G','-p','-g','-m1','-nTest','-w64','-h8',"-o$tmp/palette.goh","$tmp/palette-runs.png") == 0 &&
      read_file("$tmp/palette.goh") =~ /BMT_MASK/ &&
      read_file("$tmp/palette.goh") =~ /BMC_PACKBITS/ &&
      payload(read_file("$tmp/palette.goh")) eq (chr(0) x (40*8)), 'compressed custom palette mask');
my $pgrid = convert('grid.png',48,30,'-l','-p');
check(scalar(() = $pgrid =~ /BMF_4BIT/g) == 2 &&
      scalar(() = $pgrid =~ /BMT_PALETTE/g) == 2 &&
      scalar(() = $pgrid =~ /BMF_MONO/g) == 4, 'palette state resets between grid formats');
check(run($tool,'-G','-p','-g','-u','-nOne','-w9','-h3',"-o$tmp/one.goh","$tmp/custom.png",
          '-nTwo',"-o$tmp/two.goh","$tmp/custom.pcx") == 0 &&
      payload(read_file("$tmp/one.goh")) eq payload(read_file("$tmp/two.goh")),
      'custom PNG and PCX palette state in one batch');
write_file('seventeen.png',png(1,1,8,3,"\0\0",[@custom,[0,0,0]]));
for my $case (['rgb.png'],['rgba.png'],['gray16.png'],['eight.pcx'],['seventeen.png'],
              ['custom.png','-c8'],['custom.pcx','-c8'],['custom.png','-N'],['custom.pcx','-N'],
              ['custom.pcx','-w32767','-h32767']) {
    write_file('keep.goh','keep');
    my ($input,@opts) = @$case;
    check(run($tool,'-G','-p','-nTest',@opts,"-o$tmp/keep.goh","$tmp/$input") != 0 &&
          read_file("$tmp/keep.goh") eq 'keep', "reject unsupported palette input $input @opts");
}

if ($old) {
    for my $input ('four.pcx','eight.pcx','custom.png','four.png','eight.png','rgba.png') {
        for my $mode ('-G','-E') {
            for my $option ('-u','-b','-B','-m1') {
                for my $exe ($old,$tool) {
                    check(run($exe,$mode,'-2','-g','-nTest','-w9','-h3',$option,
                              "-o$tmp/compare.goh","$tmp/$input") == 0, 'legacy conversion');
                    my $text = read_file("$tmp/compare.goh");
                    if ($exe eq $old) { write_file('reference.goh',$text); }
                    else { check($text eq read_file("$tmp/reference.goh"), 'default output unchanged'); }
                }
            }
        }
    }
}
print "cvtpcx PNG/PCX checks passed ($checks assertions)\n";
