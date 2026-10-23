#!/usr/bin/env perl
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use FindBin;

# Optional arguments: output directory, then an exact baseline directory.
die "usage: $0 [font-directory [reference-directory]]\n" if @ARGV > 2;
my $directory = shift // "$FindBin::Bin/../../Installed/FontData";
my $reference = shift;
my @fonts = qw(Berkeley Bison Esquire LED Universi DejaVuSC);
my %inventory = (
    Berkeley => [0x0202, 'Berkeley', [9, 10, 12, 14, 18]],
    Bison => [0x0a00, 'Bison', [9, 12, 14, 13]],
    Esquire => [0x022b, 'Esquire', [10, 12, 14, 18, 9, 12, 10, 14, 18, 9]],
    LED => [0x0600, 'LED', [18]],
    Universi => [0x0201, 'University', [10, 12, 14, 18, 24, 9]],
    DejaVuSC => [0x022c, 'DejaVuSC', [9, 10, 12, 14, 18]],
);
my %hash = (
    Berkeley => '85591ad95ca0bc48232a61a1731e3d8d81fd7548912efdf0693975041df26b10',
    Bison => '90d08aa4fe62bf4fb413fcff0e6b467561b2410818ab321838c016b1f3ea3f25',
    Esquire => 'bd00580f4b089aa3646f667f3f5294e47b70b47d29b431157e19e8760cc75b5f',
    LED => '7af1561fbd88bc8c98935c2b5348853ac586809355fd3daf49e0626e96bbf0ca',
    Universi => '862bf7ef3946863e1743ea147edaa666d5515cac7b2e663308d74a755913408c',
    DejaVuSC => 'c4d2118f39492cddf76616513fbe3d4fec5788e8e2961bd52cec93fb3f2d0f27',
);
# All Berkeley metrics (except data size) and all non-Euro glyph definitions
# from master, excluding only relocated glyph offsets. Includes the 14 pt ?down.
my %unchanged = (
    9 => '5f4e69fd3adef87a8e627fa252be79752b10009b64fada108e1ed37cca9ed27e',
    10 => 'e0ae2faad275000a57bf088cef2a8bb1a8840742afbb8c2f7226d03d42109021',
    12 => '073ecb573a8ef8e218c8331f7a5128f52644ad4c4ea56a6761f99bea3721858c',
    14 => '01678dda646db58b795506634db8ea79245899c89938c19399f26697439c507d',
    18 => '7b672d557ac7195dfdda31dcd8ea0bf8a09dba958521824c126c07d919704412',
);
# Advance/flags/usage, followed by CharData, from the newer mkuc Euro glyphs.
my %euro = (
    9 => '000600000000050702003048f0c0f04830',
    10 => '000600000000050802003048f0c0f0c04830',
    12 => '00080000000006090301382440f040f0402438',
    14 => '000900000000070a04013c3c62c0f8c0c0f8623c',
    18 => '000b00000000090e04011f001f003080600060006000fc006000fc0060006000600030801f00',
);

sub read_file
{
    open my $file, '<:raw', $_[0] or die "$_[0]: $!\n";
    local $/;
    return <$file>;
}

sub u16 { return unpack('v', substr($_[0], $_[1], 2)); }
sub u32 { return unpack('V', substr($_[0], $_[1], 4)); }

sub parse_font
{
    my ($name, $data) = @_;
    my ($id, $face, $sizes) = @{$inventory{$name}};
    die "$name: truncated header\n" if length($data) < 41;
    die "$name: signature/version\n" unless substr($data, 0, 6) eq "BSWF\0\1";
    die "$name: ID/maker/name\n" unless u16($data, 8) == $id &&
        u16($data, 10) == 0 && substr($data, 13, 20) eq $face . ("\0" x (20 - length($face)));
    my $end = 41 + 10 * @$sizes;
    die "$name: directory\n" unless u16($data, 33) == 35 &&
        u16($data, 35) + 6 == $end && $end <= length($data) &&
        u16($data, 37) == 0 && u16($data, 39) == 0;
    # The original Esquire header size includes the eight-byte BSWF prefix.
    die "$name: header size\n" unless u16($data, 6) == $end - ($name eq 'Esquire' ? 0 : 8);
    my @strikes;
    my $previous_end = $end;
    for my $i (0 .. $#$sizes) {
        my $at = 41 + 10 * $i;
        my ($style, $fraction, $point, $size, $offset) = unpack('CCvvV', substr($data, $at, 10));
        die "$name: point size/style\n" unless $point == $sizes->[$i] && !$fraction &&
            $style == ($name eq 'Esquire' && $i >= 5 ? 0x20 : 0);
        die "$name: strike bounds\n" unless $size >= 71 && $offset == $previous_end &&
            $offset + $size <= length($data);
        $previous_end = $offset + $size;
        my $s = substr($data, $offset, $size);
        # Preserve the original ISUI2000 10 pt strike, including all metrics.
        if ($name eq 'DejaVuSC' && $point == 10) {
            die "DejaVuSC 10: original strike changed\n" unless sha256_hex($s) eq
                '05fe2293b0ebc01dd341e9e06d9dae64212d21aa63c2162d545a296c4bedbe43';
        }
        die "$name: strike header\n" unless u16($s, 0) == $size && u16($s, 2) == 0 &&
            u16($s, 34) == 0 && u16($s, 36) <= $size && u16($s, 38) <= $size &&
            !(ord(substr($s, 68, 1)) & 0x18);
        my ($first, $last, $default) = unpack('CCC', substr($s, 40, 3));
        my ($want_first, $want_last, $want_default) =
            $name eq 'Bison' ? ($point == 13 ? (42, 42, 42) : (0, 255, 46)) :
            $name eq 'Esquire' ? (0, 255, 46) :
            $name eq 'LED' ? (32, 94, 48) :
            $name eq 'DejaVuSC' ? (32, 255, 63) : (32, 255, 46);
        die "$name: character range/default\n" unless
            $first == $want_first && $last == $want_last && $default == $want_default;
        my $table_end = 71 + ($last - $first + 1) * 8;
        die "$name: character table bounds\n" if $table_end > $size;
        my @glyphs;
        my %records;
        my $empty_records = 0;
        for my $c ($first .. $last) {
            my $entry = 71 + 8 * ($c - $first);
            my ($pos, $frac, $width, $flags, $usage) = unpack('vCvCv', substr($s, $entry, 8));
            my $payload = '';
            if ($pos == 0) {
                die "$name: absent glyph flags\n" unless $flags & 8;
            } else {
                die "$name: glyph header bounds\n" if $pos < $table_end || $pos + 4 > $size;
                my ($w, $rows, $y, $x) = unpack('CCcc', substr($s, $pos, 4));
                my $end = $pos + 4 + int(($w + 7) / 8) * $rows;
                die "$name: bitmap bounds\n" if $end > $size;
                $payload = substr($s, $pos, $end - $pos);
                $records{$pos} = $end;
                if ($flags & 8) {
                    die "$name: nonempty no-data record\n" if $w || $rows;
                    ++$empty_records;
                }
            }
            die "$name: absent default\n" if $c == $default && $flags & 8;
            $glyphs[$c] = substr($s, $entry + 2, 6) . $payload;
        }
        die "$name: no-data records\n" unless $empty_records == ($name eq 'Esquire' ? 36 : 0);
        my $record_end = $table_end;
        for my $pos (sort {$a <=> $b} keys %records) {
            die "$name: overlapping glyph records\n" if $pos < $record_end;
            $record_end = $records{$pos};
        }
        push @strikes, [$point, substr($s, 2, 69), \@glyphs, $first, $last];
    }
    die "$name: trailing file data\n" unless $previous_end == length($data);
    return \@strikes;
}

my $count = 0;
for my $name (@fonts) {
    my $data = read_file("$directory/$name/$name.fnt");
    my $strikes = parse_font($name, $data);
    $count += @$strikes;
    if (defined $reference) {
        die "$name: baseline differs\n" unless $data eq read_file("$reference/$name.fnt");
    } else {
        die "$name: committed font hash differs\n" unless sha256_hex($data) eq $hash{$name};
        if ($name eq 'Berkeley') {
            for my $strike (@$strikes) {
                my ($point, $metrics, $glyphs, $first, $last) = @$strike;
                die "Berkeley $point: mkuc Euro differs\n" unless
                    unpack('H*', $glyphs->[0xdb]) eq $euro{$point};
                my $unmodified = $metrics . join('', map {$glyphs->[$_]} grep {$_ != 0xdb} $first .. $last);
                die "Berkeley $point: unrelated glyph/metric change\n" unless
                    sha256_hex($unmodified) eq $unchanged{$point};
            }
        }
    }
    print "$name: ", scalar(@$strikes), " strikes, ", sha256_hex($data), "\n";
}
die "wrong total strike count\n" unless $count == 31;

# Exercise rejection before hashes, without creating malformed font files.
my $good = read_file("$directory/Berkeley/Berkeley.fnt");
my @bad = (substr($good, 0, 40));
my $bad = $good;
substr($bad, 47, 4) = pack('V', length($good));
push @bad, $bad;
$bad = $good;
my $strike_offset = u32($good, 47);
substr($bad, $strike_offset + 71, 2) = pack('v', 0xffff);
push @bad, $bad;
$bad = $good;
my $default_entry = $strike_offset + 71 + 8 * (46 - 32);
substr($bad, $default_entry + 5, 1) = pack('C', 8);
push @bad, $bad;
for my $data (@bad) {
    eval { parse_font('Berkeley', $data); };
    die "malformed font accepted\n" unless $@;
}
print "Six fonts, 31 strikes, exact comparisons and malformed-input checks passed.\n";
