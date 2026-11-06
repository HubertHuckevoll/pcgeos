#!/usr/bin/env perl
# PC/GEOS 2.x Token Database <-> PNG.
# Implemented with ChatGPT Codex, prompted by MeyerK.
# Format references and editing rules: README.md.
use 5.014;
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin;
use JSON::PP;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(sha256_hex);
use Compress::Zlib qw(compress crc32);
use Getopt::Long qw(GetOptionsFromArray);

my $PALETTE = pack 'H*', join '', qw(
    0000000000aa00aa0000aaaaaa0000aa00aaaa5500aaaaaa5555555555ff55ff5555ffffff5555ff55ffffff55ffffff
    000000111111222222333333444444555555666666777777888888999999aaaaaabbbbbbccccccddddddeeeeeeffffff
    0000000000000000000000000000000000000000000000000000000000330000660000990000cc0000ff003300003333
    0033660033990033cc0033ff0066000066330066660066990066cc0066ff0099000099330099660099990099cc0099ff
    00cc0000cc3300cc6600cc9900cccc00ccff00ff0000ff3300ff6600ff9900ffcc00ffff330000330033330066330099
    3300cc3300ff3333003333333333663333993333cc3333ff3366003366333366663366993366cc3366ff339900339933
    3399663399993399cc3399ff33cc0033cc3333cc6633cc9933cccc33ccff33ff0033ff3333ff6633ff9933ffcc33ffff
    6600006600336600666600996600cc6600ff6633006633336633666633996633cc6633ff666600666633666666666699
    6666cc6666ff6699006699336699666699996699cc6699ff66cc0066cc3366cc6666cc9966cccc66ccff66ff0066ff33
    66ff6666ff9966ffcc66ffff9900009900339900669900999900cc9900ff9933009933339933669933999933cc9933ff
    9966009966339966669966999966cc9966ff9999009999339999669999999999cc9999ff99cc0099cc3399cc6699cc99
    99cccc99ccff99ff0099ff3399ff6699ff9999ffcc99ffffcc0000cc0033cc0066cc0099cc00cccc00ffcc3300cc3333
    cc3366cc3399cc33cccc33ffcc6600cc6633cc6666cc6699cc66cccc66ffcc9900cc9933cc9966cc9999cc99cccc99ff
    cccc00cccc33cccc66cccc99ccccccccccffccff00ccff33ccff66ccff99ccffccccffffff0000ff0033ff0066ff0099
    ff00ccff00ffff3300ff3333ff3366ff3399ff33ccff33ffff6600ff6633ff6666ff6699ff66ccff66ffff9900ff9933
    ff9966ff9999ff99ccff99ffffcc00ffcc33ffcc66ffcc99ffccccffccffffff00ffff33ffff66ffff99ffffccffffff
);
my $JSON = JSON::PP->new->utf8->canonical->pretty;

sub db_error { die "tokendb: $_[0]\n"; }
sub take {
    my ($data, $offset, $size) = @_;
    db_error("out-of-bounds data: offset $offset, size $size")
        if $offset < 0 || $size < 0 || $offset + $size > length($data);
    return substr($data, $offset, $size);
}
sub word { return unpack('v', take($_[0], $_[1], 2)); }
sub words { return unpack('v*', take($_[0], $_[1], 2 * $_[2])); }
sub align4 { return ($_[0] + 3) & ~3; }
sub b64 { return encode_base64($_[0], ''); }
sub from_b64 {
    my ($value) = @_;
    db_error('invalid base64') unless defined($value) &&
        $value =~ /\A(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?\z/;
    return decode_base64($value);
}
sub read_file {
    my ($path, $limit) = @_;
    $limit //= 128 * 1024 * 1024;
    open my $file, '<:raw', $path or db_error("cannot read $path: $!");
    my $size = -s $file;
    db_error("file exceeds $limit bytes: $path") if $size > $limit;
    local $/;
    my $data = <$file>;
    close $file or db_error("cannot close $path: $!");
    return $data // '';
}
sub write_file {
    my ($path, $data) = @_;
    open my $file, '>:raw', $path or db_error("cannot write $path: $!");
    print {$file} $data or db_error("cannot write $path: $!");
    close $file or db_error("cannot close $path: $!");
}
sub safe_file {
    my ($root, $relative, $writing) = @_;
    db_error('manifest paths must be relative') if !defined($relative) ||
        File::Spec->file_name_is_absolute($relative) || $relative =~ /\0/;
    my $path = File::Spec->catfile($root, $relative);
    my $resolved = abs_path($path);
    if (!defined($resolved) && $writing) {
        my $parent = abs_path(dirname($path));
        db_error("missing parent directory: $path") unless defined $parent;
        $resolved = File::Spec->catfile($parent, (File::Spec->splitpath($path))[2]);
    }
    db_error("missing file: $path") unless defined $resolved;
    my $back = File::Spec->abs2rel($resolved, $root);
    db_error('manifest path escapes the export directory')
        if File::Spec->file_name_is_absolute($back) || $back =~ /^\.\.(?:[\\\/]|$)/;
    return $resolved;
}
sub uint16 {
    my ($value) = @_;
    db_error('expected an unsigned 16-bit integer') unless defined($value) &&
        !ref($value) && $value =~ /\A\d+\z/ && $value <= 65535;
    return 0 + $value;
}
sub pwords { return pack('v*', map { uint16($_) } @_); }
sub signed_word { my $v = word(@_); return $v >= 32768 ? $v - 65536 : $v; }

sub database {
    my ($data) = @_;
    db_error('expected a GEOS 2.x GEAS file') unless take($data, 0, 4) eq "\xc7E\xc1S";
    db_error('not a VM file') unless word($data, 256) == 0xadeb;
    my ($size, $pos) = unpack('vV', take($data, 258, 6));
    my $header = take($data, 256 + $pos, $size);
    db_error('invalid VM header signature') unless word($header, 0) == 0xfb;
    my $limit = word($header, 8);
    db_error('invalid VM handle table') if $limit > $size || $limit < 44 || ($limit - 32) % 12;
    my %blocks;
    for (my $h = 32; $h < $limit; $h += 12) {
        next unless ord(substr($header, $h + 2, 1)) == 255;
        my ($n, $p) = unpack('vV', take($header, $h + 6, 6));
        $blocks{$h} = take($data, 256 + $p, $n);
    }
    my $db = {blocks => \%blocks, file_header => take($data, 0, 256)};
    my $dbmap = block($db, word($header, 30));
    $db->{map} = item($db, words($dbmap, 4, 2));
    db_error('token map must contain 24-byte TokenEntry records')
        unless length($db->{map}) && length($db->{map}) % 24 == 0;
    return $db;
}
sub block {
    my ($db, $h) = @_;
    db_error(sprintf('invalid VM block handle %#x', $h)) unless exists $db->{blocks}{$h};
    return $db->{blocks}{$h};
}
sub item {
    my ($db, $g, $i) = @_;
    my $group = block($db, $g);
    my ($info, $chunk) = words($group, $i, 2);
    my $block = block($db, word($group, $info + 2));
    my ($table, $count) = (word($block, 2), word($block, 10));
    db_error('invalid LMem chunk handle') if $chunk < $table ||
        $chunk >= $table + $count * 2 || ($chunk - $table) % 2;
    my $offset = word($block, $chunk);
    return take($block, $offset, word($block, $offset - 2) - 2);
}
sub tokens {
    my ($db) = @_;
    my @tokens;
    for (my $off = 24; $off < length($db->{map}); $off += 24) {
        my $entry = take($db->{map}, $off, 24);
        my $list = item($db, words($entry, 6, 2));
        db_error('invalid moniker list length') if length($list) % 6;
        my @monikers;
        for (my $p = 0; $p < length($list); $p += 6) {
            my ($type, $group, $item) = words($list, $p, 3);
            push @monikers, [$type, item($db, $group, $item)];
        }
        push @tokens, [$entry, \@monikers];
    }
    return \@tokens;
}

sub unpackbits {
    my ($data, $expected) = @_;
    my ($out, $pos) = ('', 0);
    while (length($out) < $expected) {
        my $n = ord(take($data, $pos++, 1));
        if ($n < 128) {
            $out .= take($data, $pos, $n + 1);
            $pos += $n + 1;
        } else {
            # GEOS's 0x80 repeats 129 bytes; it is not a Mac PackBits no-op.
            $out .= take($data, $pos++, 1) x (257 - $n);
        }
        db_error('PackBits data exceeds bitmap size') if length($out) > $expected;
    }
    db_error('trailing PackBits data') if $pos != length($data);
    return $out;
}
sub bitmap_image {
    my ($data, $fill_color, $fill) = @_;
    $fill_color //= "\0\0\0";
    my ($w, $h, $compact, $type) = unpack('vvCC', take($data, 0, 6));
    my $fmt = $type & 7;
    db_error('invalid or excessive bitmap dimensions') if !$w || !$h || $w * $h > 16_000_000;
    db_error(sprintf('unsupported bitmap type %#x', $type)) if $fmt > 3 || $type & 0x20;
    my ($start, $palette) = (6, $PALETTE);
    if ($type & 8) {
        db_error('sliced complex bitmap is not supported')
            unless word($data, 6) == 0 && word($data, 8) == $h;
        $start = word($data, 12);
        db_error('complex bitmap data overlaps header') if $start < 20;
        if ($type & 0x40) {
            my $offset = word($data, 14);
            my $count = word($data, $offset);
            db_error('invalid palette size') if !$count || $count > 256;
            $palette = take($data, $offset + 2, $count * 3);
        }
    }
    my $bpp = (1, 4, 8, 24)[$fmt];
    my $stride = int(($w * $bpp + 7) / 8);
    my $mask_stride = $type & 16 ? int(($w + 7) / 8) : 0;
    my $expected = ($stride + $mask_stride) * $h;
    my $pixels = take($data, $start, length($data) - $start);
    $pixels = unpackbits($pixels, $expected) if $compact == 1;
    db_error("unsupported bitmap compression $compact") if $compact > 1;
    db_error('bitmap byte count does not match dimensions') if length($pixels) != $expected;
    my $rgba = '';
    for my $y (0 .. $h - 1) {
        my $row = substr($pixels, $y * ($stride + $mask_stride), $stride + $mask_stride);
        my $mask = substr($row, 0, $mask_stride, '');
        for my $x (0 .. $w - 1) {
            my $color;
            my $bit = 128 >> ($x % 8);
            my $set = $fmt == 0 ? ord(substr($row, int($x / 8), 1)) & $bit : 0;
            if ($fmt == 0) {
                $color = $set ? ($fill ? $fill_color : "\0\0\0") : "\xff\xff\xff";
            } elsif ($fmt == 1 || $fmt == 2) {
                my $index = $fmt == 1 ?
                    (ord(substr($row, int($x / 2), 1)) >> ($x % 2 ? 0 : 4)) & 15 :
                    ord(substr($row, $x, 1));
                $color = take($palette, $index * 3, 3);
            } else {
                $color = take($row, $x * 3, 3);
            }
            my $alpha = !$mask_stride || (ord(substr($mask, int($x / 8), 1)) & $bit) ? 255 : 0;
            $alpha = 0 if $fill && $fmt == 0 && !$set;
            $rgba .= $color . chr($alpha);
        }
    }
    return {width => $w, height => $h, rgba => $rgba};
}
sub render_moniker {
    my ($raw) = @_;
    return undef unless ord(take($raw, 0, 1)) & 0x40;
    my ($w, $h) = words($raw, 1, 2);
    db_error('invalid moniker dimensions') if !$w || !$h || $w * $h > 16_000_000;
    my $canvas = "\0" x ($w * $h * 4);
    my ($pos, $seen, $cx, $cy, $fill_color) = (5, 0, 0, 0, "\0\0\0");
    while (1) {
        my $op = ord(take($raw, $pos++, 1));
        if ($op == 0) {
            db_error('invalid end of bitmap GString') if !$seen || $pos != length($raw);
            return {width => $w, height => $h, rgba => $canvas};
        }
        next if $op == 2;
        if ($op == 0x62) {
            db_error('unsupported mix mode') unless take($raw, $pos++, 1) eq "\1";
            next;
        }
        if ($op == 0x79) {
            $fill_color = take($PALETTE, ord(take($raw, $pos++, 1)) * 3, 3);
            next;
        }
        if ($op == 0x75) { $fill_color = take($raw, $pos, 3); $pos += 3; next; }
        if ($op == 0x63) {
            ($cx, $cy) = (signed_word($raw, $pos), signed_word($raw, $pos + 2));
            $pos += 4; next;
        }
        if ($op == 0x64) {
            my ($dx, $dy) = unpack('l<l<', take($raw, $pos, 8));
            db_error('fractional current position is not supported') if $dx % 65536 || $dy % 65536;
            $cx += $dx / 65536; $cy += $dy / 65536; $pos += 8; next;
        }
        if ($op == 0x4c || $op == 0x50) {
            ($cx, $cy) = (signed_word($raw, $pos), signed_word($raw, $pos + 2));
            $pos += 4;
        } elsif ($op != 0x4d && $op != 0x51) {
            db_error(sprintf('unsupported GString opcode %#x at %d', $op, $pos - 1));
        }
        my $size = word($raw, $pos); $pos += 2;
        my $image = bitmap_image(take($raw, $pos, $size), $fill_color, $op == 0x4c || $op == 0x4d);
        $pos += $size;
        for my $y (0 .. $image->{height} - 1) {
            next if $cy + $y < 0 || $cy + $y >= $h;
            for my $x (0 .. $image->{width} - 1) {
                next if $cx + $x < 0 || $cx + $x >= $w;
                my $pixel = substr($image->{rgba}, ($y * $image->{width} + $x) * 4, 4);
                next unless ord(substr($pixel, 3, 1));
                substr($canvas, (($cy + $y) * $w + $cx + $x) * 4, 4) = $pixel;
            }
        }
        $seen = 1;
    }
}
sub image_hash {
    my ($image) = @_;
    return sha256_hex(pwords($image->{width}, $image->{height}) . $image->{rgba});
}
sub png_chunk {
    my ($type, $data) = @_;
    return pack('N', length($data)) . $type . $data . pack('N', crc32($type . $data));
}
sub png_bytes {
    my ($image) = @_;
    my $rows = '';
    for my $y (0 .. $image->{height} - 1) {
        $rows .= "\0" . substr($image->{rgba}, $y * $image->{width} * 4, $image->{width} * 4);
    }
    my $z = compress($rows);
    db_error('PNG compression failed') unless defined $z;
    return "\x89PNG\r\n\x1a\n" .
        png_chunk('IHDR', pack('NNCCCCC', $image->{width}, $image->{height}, 8, 6, 0, 0, 0)) .
        png_chunk('IDAT', $z) . png_chunk('IEND', '');
}

sub export_db {
    my ($source, $directory) = @_;
    my $db = database(read_file($source));
    db_error("export directory already exists: $directory") if -e $directory;
    make_path($directory);
    my $root = abs_path($directory);
    my $manifest = {format => 'pcgeos-token-db', version => 1,
        file_header => b64($db->{file_header}), dummy_entry => b64(substr($db->{map}, 0, 24)), tokens => []};
    my ($count, $unsupported, $index) = (0, 0, 0);
    for my $record (@{tokens($db)}) {
        my ($entry, $monikers) = @$record;
        my $chars = substr($entry, 0, 4);
        (my $label = $chars) =~ s/[^A-Za-z0-9]/_/g;
        my ($manufacturer, $flags) = (word($entry, 4), word($entry, 10));
        my $folder = sprintf('%04d_%s_%04x', $index++, $label, $manufacturer);
        make_path(File::Spec->catdir($root, $folder));
        my $token = {token_hex => unpack('H*', $chars), manufacturer => $manufacturer,
            flags => $flags, release => [words($entry, 12, 4)], protocol => [words($entry, 20, 2)], monikers => []};
        my $number = 0;
        for my $pair (@$monikers) {
            my ($type, $raw) = @$pair;
            my $name = sprintf('%s/%02d_%04x', $folder, $number++, $type);
            write_file(safe_file($root, "$name.bin", 1), $raw);
            my $moniker = {type => $type, raw => "$name.bin", raw_sha256 => sha256_hex($raw)};
            my $image;
            my $ok = eval { $image = render_moniker($raw); 1 };
            if (!$ok) {
                (my $message = $@) =~ s/\s+\z//;
                $moniker->{unsupported} = $message;
                warn "$name: $message\n"; $unsupported++;
            } elsif ($image) {
                my $png = png_bytes($image);
                write_file(safe_file($root, "$name.png", 1), $png);
                $moniker->{png} = "$name.png";
                $moniker->{pixel_sha256} = image_hash($image);
                $moniker->{png_sha256} = sha256_hex($png);
                $count++;
            } else {
                $moniker->{text_hex} = unpack('H*', substr($raw, 4));
            }
            push @{$token->{monikers}}, $moniker;
        }
        push @{$manifest->{tokens}}, $token;
    }
    write_file(File::Spec->catfile($root, 'manifest.json'), $JSON->encode($manifest));
    printf "Exported %d tokens, %d PNGs; %d unsupported graphics preserved as raw data.\n",
        scalar(@{$manifest->{tokens}}), $count, $unsupported;
}

# cvtpcx writes a narrowly defined GOC bitmap initializer. Parse only that
# grammar, never eval generated source or invoke a compiler/shell to read it.
sub parse_cvtpcx {
    my ($source) = @_;
    $source =~ s{/\*.*?\*/}{}sg;
    $source =~ s/\A\s*\@chunk\s+byte\s+TokenMoniker\[\]\s*=\s*\{\s*//
        or db_error('unexpected cvtpcx chunk declaration');
    $source =~ s/\ABitmap\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*0\s*,\s*(\([^()]*\)|[A-Z0-9_]+)\s*\)\s*,//
        or db_error('unexpected cvtpcx bitmap header');
    my ($w, $h, $expression) = ($1, $2, $3);
    my %constants = (BMF_MONO => 0, BMF_4BIT => 1, BMF_8BIT => 2,
                     BMT_MASK => 16, BMT_COMPLEX => 8, BMT_PALETTE => 64);
    $expression =~ tr/()//d;
    my $type = 0;
    for my $name (split /\|/, $expression) {
        $name =~ s/\s+//g;
        db_error("unexpected cvtpcx bitmap constant: $name") unless exists $constants{$name};
        $type |= $constants{$name};
    }
    $source =~ s/\s*\};\s*\z// or db_error('unexpected cvtpcx chunk end');
    my @bytes;
    while ($source =~ s/\A\s*(0x[0-9a-fA-F]+|\d+)\s*,//) {
        my $literal = $1;
        my $n = $literal =~ /^0x/ ? hex($literal) : 0 + $literal;
        db_error('cvtpcx byte out of range') if $n > 255;
        push @bytes, $n;
    }
    db_error('unexpected cvtpcx bitmap data') if $source =~ /\S/;
    my $bitmap = pwords($w, $h) . pack('CC', 0, $type) . pack('C*', @bytes);
    bitmap_image($bitmap); # Validate header, palette and raster length.
    return $bitmap;
}
sub find_cvtpcx {
    my ($requested) = @_;
    my @candidates = defined($requested) ? ($requested) :
        ($ENV{CVTPCX} // (), File::Spec->catfile($FindBin::Bin, '../../../Installed/Tools/misc/cvtpcx/linux.md/cvtpcx.'),
         File::Spec->catfile($FindBin::Bin, '../../../Installed/Tools/misc/cvtpcx/win32.md/cvtpcx.exe'), 'cvtpcx');
    for my $candidate (@candidates) {
        next unless defined $candidate && length $candidate;
        if ($candidate =~ m{[/\\]}) {
            return abs_path($candidate) if -f $candidate && -x $candidate;
        } else {
            for my $dir (File::Spec->path()) {
                my $path = File::Spec->catfile($dir, $candidate);
                return abs_path($path) if -f $path && -x $path;
            }
        }
    }
    db_error('PNG import needs PNG-capable cvtpcx: use --cvtpcx PATH or CVTPCX');
}
sub encode_png {
    my ($path, $type, $tool) = @_;
    db_error('PNG moniker type must have the graphics and moniker-list bits set') if ($type & 0xc0) != 0xc0;
    my $png = read_file($path, 64 * 1024 * 1024);
    db_error('expected PNG image') unless take($png, 0, 8) eq "\x89PNG\r\n\x1a\n" &&
        take($png, 12, 4) eq 'IHDR';
    my ($w, $h) = unpack('NN', take($png, 16, 8));
    db_error('invalid or excessive PNG dimensions') if !$w || !$h || $w > 32767 || $h > 32767 || $w * $h > 16_000_000;
    my $temp = tempdir(CLEANUP => 1);
    my $output = File::Spec->catfile($temp, 'bitmap.goh');
    my $class = $type & 15;
    my @depth = $class <= 1 ? ('-b') : ($class <= 6 ? ('-c4') : ('-c8'));
    # A list-form system call avoids shell expansion, including spaces in paths.
    my $status = system {$tool} $tool, '-G', '-2', '-g', '-u', '-nToken',
        "-w$w", "-h$h", @depth, "-o$output", $path;
    db_error("cvtpcx failed (status $status)") if $status != 0;
    my $bitmap = parse_cvtpcx(read_file($output));
    db_error('GEOS bitmap exceeds single-item size') if length($bitmap) > 64991;
    return pack('C', ($type & 0x7f) | 0x40) . pwords($w, $h) . "\x51" .
        pwords(length($bitmap)) . $bitmap . "\0";
}

sub builder { return {blocks => [[0xadeb, 0, '']], groups => {}, group_order => []}; }
sub alloc_block {
    my ($b, $uid, $flags) = @_;
    my $handle = 32 + 12 * @{$b->{blocks}};
    db_error('VM handle table exceeds 64K') if $handle + 12 > 65535;
    push @{$b->{blocks}}, [$uid, $flags // 0, ''];
    return $handle;
}
sub put_block {
    my ($b, $handle, $data) = @_;
    db_error('VM block exceeds 64K') if length($data) > 65535;
    $b->{blocks}[($handle - 32) / 12][2] = $data;
}
sub add_item {
    my ($b, $type, $data) = @_;
    db_error('DB item exceeds 65000 bytes') if length($data) > 65000;
    my $g = $b->{groups}{$type};
    if (!$g || (@{$g->{items}} && $g->{size} + align4(length($data) + 2) + 2 > 8192)) {
        $g = new_group($b, $type);
    }
    my $item = 16 + 4 * @{$g->{items}};
    db_error('DB group exceeds 64K') if $item + 10 > 65535;
    push @{$g->{items}}, $data;
    $g->{size} += align4(length($data) + 2) + 2;
    return ($g->{handle}, $item);
}
sub new_group {
    my ($b, $type) = @_;
    my $group = {handle => alloc_block($b, 0xff01), block => alloc_block($b, 0xff02, 1),
                 items => [], size => 20};
    $b->{groups}{$type} = $group;
    push @{$b->{group_order}}, $group;
    return $group;
}
sub finish_groups {
    my ($b) = @_;
    for my $g (@{$b->{group_order}}) {
        my $items = $g->{items};
        my $info = 16 + 4 * @$items;
        my $group = pwords($g->{handle}, 0, 0, $info, 0, 0, $info + 6, 0);
        $group .= pwords($info, 20 + 2 * $_) for 0 .. $#$items;
        $group .= pwords(0, $g->{block}, scalar(@$items));
        put_block($b, $g->{handle}, $group);
        # Even handle count: the heap starts on a four-byte boundary.
        my $nhandles = (@$items + 1) & ~1;
        my $body = "\0" x (20 + 2 * $nhandles);
        for my $i (0 .. $#$items) {
            substr($body, 20 + 2 * $i, 2) = pwords(length($body) + 2);
            $body .= pwords(length($items->[$i]) + 2) . $items->[$i];
            $body .= "\0" x ((-length($body)) & 3);
        }
        substr($body, 0, 20) = pwords(0, 20, 0x100, 0, length($body), $nhandles, 0, 0, $g->{block}, $info);
        put_block($b, $g->{block}, $body);
    }
}
sub write_database {
    my ($b, $file_header, $map, $dbmap) = @_;
    finish_groups($b);
    my $size = 32 + 12 * @{$b->{blocks}};
    my $used = $size;
    $used += length($_->[2]) for @{$b->{blocks}};
    my $header = pwords(0xfb, 0, 0, 0, $size, 0, 0, scalar(@{$b->{blocks}}), 0, 0, $map, 70) .
        pack('V', $used) . pwords(0, $dbmap);
    my $pos = 24 + $size;
    for my $i (0 .. $#{$b->{blocks}}) {
        my ($uid, $flags, $data) = @{$b->{blocks}[$i]};
        my ($length, $offset) = $i ? (length($data), $pos) : ($size, 24);
        $header .= pack('vCCvvV', 0, 255, $flags, $uid, $length, $offset);
        $pos += $length if $i;
    }
    return $file_header . pwords(0xadeb, $size) . pack('V', 24) . ("\0" x 16) . $header .
        join('', map { $_->[2] } @{$b->{blocks}}[1 .. $#{$b->{blocks}}]);
}
sub build_db {
    my ($directory, $target, $requested_tool) = @_;
    my $root = abs_path($directory);
    db_error("missing directory: $directory") unless defined $root && -d $root;
    my $m = $JSON->decode(read_file(File::Spec->catfile($root, 'manifest.json')));
    db_error('unsupported manifest format/version') unless ($m->{format} // '') eq 'pcgeos-token-db' &&
        ($m->{version} // 0) == 1 && ref($m->{tokens}) eq 'ARRAY';
    my $builder = builder();
    # GetGroup assumes an initial moniker-list entry even in an empty DB.
    new_group($builder, 0xffff);
    my $entries = from_b64($m->{dummy_entry} // b64("\0" x 24));
    db_error('dummy entry must be 24 bytes') unless length($entries) == 24;
    my (%seen, $tool);
    for my $token (@{$m->{tokens}}) {
        db_error('token must have four hex-encoded bytes') unless ($token->{token_hex} // '') =~ /\A[0-9a-fA-F]{8}\z/;
        my $chars = pack('H*', $token->{token_hex});
        my $manufacturer = uint16($token->{manufacturer});
        my $key = $chars . pwords($manufacturer);
        db_error('token/manufacturer pairs must be unique') if $seen{$key}++;
        db_error('each token needs at least one moniker') unless ref($token->{monikers}) eq 'ARRAY' && @{$token->{monikers}};
        my $list = '';
        for my $moniker (@{$token->{monikers}}) {
            my $type = uint16($moniker->{type});
            my $raw = defined($moniker->{raw}) ? read_file(safe_file($root, $moniker->{raw})) : undef;
            if (defined $moniker->{png}) {
                db_error('PNG moniker type must have the graphics and moniker-list bits set')
                    if ($type & 0xc0) != 0xc0;
                my $path = safe_file($root, $moniker->{png});
                my $png = read_file($path, 64 * 1024 * 1024);
                # Fast lossless path. Both files must still match the export.
                my $unchanged = defined($raw) &&
                    ($moniker->{png_sha256} // '') eq sha256_hex($png) &&
                    ($moniker->{raw_sha256} // '') eq sha256_hex($raw);
                if (!$unchanged) {
                    $tool //= find_cvtpcx($requested_tool);
                    my $converted = encode_png($path, $type, $tool);
                    # Also accept old manifests without file hashes and PNGs
                    # resaved without pixel changes. Ignore invisible RGB bytes.
                    my $original = defined($raw) ? eval { render_moniker($raw) } : undef;
                    my $new = render_moniker($converted);
                    $raw = $converted unless $original && image_hash($original) eq image_hash($new);
                }
            }
            db_error('each moniker needs a raw file or PNG') unless defined $raw;
            $list .= pwords($type, add_item($builder, $type, $raw));
        }
        my @ref = add_item($builder, 0xffff, $list);
        my $release = $token->{release} // [0, 0, 0, 0];
        my $protocol = $token->{protocol} // [0, 0];
        db_error('release/protocol need four/two words') unless ref($release) eq 'ARRAY' && @$release == 4 &&
            ref($protocol) eq 'ARRAY' && @$protocol == 2;
        $entries .= $chars . pwords($manufacturer, @ref, $token->{flags} // 0, @$release, @$protocol);
    }
    my @map_ref = add_item($builder, 'token-map', $entries);
    my $map_handle = alloc_block($builder, 0);
    my @types = sort { ($a != 0xffff) <=> ($b != 0xffff) || $a <=> $b }
        grep { /^\d+$/ } keys %{$builder->{groups}};
    my $map_size = 4 + 4 * @types;
    put_block($builder, $map_handle, pwords($map_size, $map_size) .
        join('', map { pwords($_, $builder->{groups}{$_}{handle}) } @types));
    my $dbmap_handle = alloc_block($builder, 0xff00);
    put_block($builder, $dbmap_handle, pwords($dbmap_handle, 0, @map_ref, 0, 0));
    my $file_header = from_b64($m->{file_header});
    db_error('invalid GEOS file header') unless length($file_header) == 256 && substr($file_header, 0, 4) eq "\xc7E\xc1S";
    my $result = write_database($builder, $file_header, $map_handle, $dbmap_handle);
    my $rebuilt = database($result);
    db_error('internal error rebuilding token map') unless @{tokens($rebuilt)} == @{$m->{tokens}};
    my $parent = dirname($target);
    make_path($parent) unless -d $parent;
    my ($file, $temporary) = tempfile('.tokendb-XXXXXX', DIR => $parent, UNLINK => 1);
    binmode $file;
    print {$file} $result or db_error("cannot write $temporary: $!");
    close $file or db_error("cannot close $temporary: $!");
    rename $temporary, $target or db_error("cannot replace $target: $!");
    printf "Built %d tokens: %s (%d bytes)\n", scalar(@{$m->{tokens}}), $target, length($result);
}
sub main {
    my @args = @_;
    my $tool;
    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case', 'permute');
    GetOptionsFromArray(\@args, 'cvtpcx=s' => \$tool) or db_error('invalid options');
    my $command = shift(@args) // '';
    db_error("usage: perl tokendb.pl export DATABASE DIRECTORY\n       perl tokendb.pl build DIRECTORY DATABASE [--cvtpcx PATH]")
        unless @args == 2 && ($command eq 'export' || $command eq 'build');
    if ($command eq 'export') { export_db(@args); }
    else { build_db(@args, $tool); }
    return 0;
}
unless (caller) {
    my $ok = eval { main(@ARGV); 1 };
    unless ($ok) { print STDERR $@; exit 1; }
}
1;
