#!/usr/bin/env perl
# Integration tests for the Perl host tool. No GEOS or Python runtime needed.
# CVTPCX=/path/to/cvtpcx perl Tools/misc/tokendb/Tests/token.pl
use strict;
use warnings;
use Test::More;
use FindBin;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use JSON::PP;
use Compress::Zlib qw(uncompress);
require "$FindBin::Bin/../tokendb.pl";
my $root = abs_path("$FindBin::Bin/../../../..");
my $temp = tempdir(CLEANUP => 1);
my $fixture = "$root/Installed/ProductFiles/Build/bbxensem/Misc/token_da.000";
my $json = JSON::PP->new->utf8->canonical;
my $tool = $ENV{CVTPCX} ? abs_path($ENV{CVTPCX}) : undef;

sub quiet {
    my ($function, @args) = @_;
    open my $sink, '>', "$temp/diagnostics" or die $!;
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>&', $sink or die $!;
    open STDERR, '>&', $sink or die $!;
    return $function->(@args);
}
sub manifest { return $json->decode(read_file("$_[0]/manifest.json")); }
sub save_manifest { write_file("$_[0]/manifest.json", $json->encode($_[1])); }
sub semantics {
    my ($data) = @_;
    return [map { [substr($_->[0], 0, 6) . substr($_->[0], 10), $_->[1]] } @{tokens(database($data))}];
}
sub rebuilt {
    my ($folder, $target) = @_;
    quiet(\&build_db, $folder, $target, $tool);
    my $data = read_file($target);
    validate_layout($data);
    return database($data);
}
sub dies_like {
    my ($function, $pattern, $name) = @_;
    my $ok = eval { $function->(); 1 };
    ok(!$ok && $@ =~ $pattern, $name) or diag($@ || 'unexpected success');
}
sub validate_layout {
    # Walk physical heaps independently, mirroring VMCheckUsedBlks and
    # LMValidateChunks. Reading selected items alone misses invalid heap gaps.
    my ($data) = @_;
    my ($size, $pos) = unpack('vV', substr($data, 258, 6));
    my $header = substr($data, 256 + $pos, $size);
    my ($used, @extents) = (0);
    for (my $handle = 32; $handle < $size; $handle += 12) {
        my ($memory, $sig, $flags, $uid, $length, $offset) =
            unpack('vCCvvV', substr($header, $handle, 12));
        next unless $sig == 255;
        $used++;
        die 'resident handle stored on disk' if $memory;
        push @extents, [$offset, $offset + $length];
        next unless $uid == 0xff02;
        my $block = substr($data, 256 + $offset, $length);
        my @h = unpack('v10', substr($block, 0, 20));
        die 'bad LMem header' unless $h[1] == 20 && $h[4] == length($block) && $h[6] == 0;
        my %references = map { $_ => 1 } grep { $_ } unpack('v*', substr($block, 20, $h[5] * 2));
        my %pointers;
        my $cursor = 20 + $h[5] * 2;
        while ($cursor < $h[4]) {
            my $n = unpack('v', substr($block, $cursor, 2));
            die 'bad chunk size' if $n < 2;
            $pointers{$cursor + 2} = 1;
            $cursor += ($n + 3) & ~3;
        }
        die 'heap size mismatch' unless $cursor == $h[4];
        die 'chunk reference mismatch' unless join(',', sort {$a <=> $b} keys %references) eq
            join(',', sort {$a <=> $b} keys %pointers);
    }
    die 'used block count mismatch' unless $used == unpack('v', substr($header, 14, 2));
    @extents = sort { $a->[0] <=> $b->[0] } @extents;
    die 'unexpected VM header position' unless $extents[0][0] == 24;
    my $sum = 0;
    for my $i (0 .. $#extents) {
        die 'overlapping or gapped blocks' if $i && $extents[$i-1][1] != $extents[$i][0];
        $sum += $extents[$i][1] - $extents[$i][0];
    }
    die 'file length mismatch' unless $extents[-1][1] + 256 == length($data);
    die 'used size mismatch' unless $sum == unpack('V', substr($header, 24, 4));
    return 1;
}

subtest 'real databases: lossless roundtrip and compact heap validation' => sub {
    my @fixtures = ([$fixture, 90, 395, 77],
        ["$root/Tools/build/product/bbxensem/Images/Windemo/token_da.000", 29, 87, 0]);
    my $index = 0;
    for my $case (@fixtures) {
        my ($path, $count, $graphics, $text) = @$case;
        my $folder = "$temp/fixture" . $index++;
        quiet(\&export_db, $path, $folder);
        my $m = manifest($folder);
        is(scalar(@{$m->{tokens}}), $count, 'token count');
        my @monikers = map { @{$_->{monikers}} } @{$m->{tokens}};
        is(scalar(grep { exists $_->{png} } @monikers), $graphics, 'all graphics exported');
        is(scalar(grep { exists $_->{text_hex} } @monikers), $text, 'text monikers retained');
        is(scalar(grep { exists $_->{unsupported} } @monikers), 0, 'no unsupported fixture graphics');
        my $target = "$folder.000";
        rebuilt($folder, $target);
        is_deeply(semantics(read_file($path)), semantics(read_file($target)), 'metadata and moniker bytes identical');
        is(substr(read_file($target), 0, 256), substr(read_file($path), 0, 256), 'GEOS header retained');
        my $again = "$folder-again";
        quiet(\&export_db, $target, $again);
        my $other = manifest($again);
        is_deeply($other, $m, 're-export identical, including all PNG and raw hashes');
    }
};

subtest 'PNG output is valid RGBA with correct CRC and rows' => sub {
    my $pixels = pack('C*', 255, 0, 0, 255, 0, 0, 0, 0);
    my $png = png_bytes({width => 2, height => 1, rgba => $pixels});
    is(substr($png, 0, 8), "\x89PNG\r\n\x1a\n", 'signature');
    my $pos = 8;
    my $idat = '';
    while ($pos < length($png)) {
        my ($length, $type) = unpack('Na4', substr($png, $pos, 8));
        my $body = substr($png, $pos + 8, $length);
        is(unpack('N', substr($png, $pos + 8 + $length, 4)), Compress::Zlib::crc32($type . $body), "$type CRC");
        $idat .= $body if $type eq 'IDAT';
        $pos += 12 + $length;
    }
    is(uncompress($idat), "\0" . $pixels, 'unfiltered RGBA row');
};

subtest 'mono fill/draw, complex palette, PackBits and positioning' => sub {
    my $bitmap = pwords(2, 1) . "\0\0\x80";
    my $base = "\x41" . pwords(2, 1);
    my $fill = render_moniker($base . "\x79\x04\x4d" . pwords(length($bitmap)) . $bitmap . "\0");
    is($fill->{rgba}, pack('C*', 170, 0, 0, 255, 0, 0, 0, 0), 'FillBitmap uses area color and transparent zero bits');
    my $draw = render_moniker($base . "\x79\x04\x51" . pwords(length($bitmap)) . $bitmap . "\0");
    is($draw->{rgba}, pack('C*', 0, 0, 0, 255, 255, 255, 255, 255), 'DrawBitmap ignores area color');
    is(unpackbits("\x80\xaa", 129), "\xaa" x 129, 'GEOS PackBits 0x80 means 129 copies');
    dies_like(sub { unpackbits("\xff\0", 1) }, qr/exceeds/, 'oversized run rejected');
    my $complex = pwords(3, 1) . pack('CC', 0, 0x59) . pwords(0, 1, 0, 28, 20, 72, 72) .
        pwords(2) . pack('C*', 17, 33, 55, 77, 99, 111, 0xa0, 0x01, 0x00);
    is(bitmap_image($complex)->{rgba}, pack('C*', 17,33,55,255, 77,99,111,0, 17,33,55,255), 'complex palette/mask and odd width');
    my $rgb = pwords(1, 1) . pack('C*', 0, 3, 17, 34, 51);
    my $raw = "\x48" . pwords(3, 3) . "\x63" . pwords(1, 1) .
        "\x64" . pack('l<l<', 65536, 0) . "\x51" . pwords(length($rgb)) . $rgb . "\0";
    is(substr(render_moniker($raw)->{rgba}, (3 + 2) * 4, 4), pack('C*', 17,34,51,255), 'MoveTo/RelMoveTo and RGB24');
};

subtest 'raw preservation, manifest validation and atomic failure' => sub {
    my $folder = "$temp/edit";
    quiet(\&export_db, $fixture, $folder);
    my $m = manifest($folder);
    my $unknown = "\x41" . pwords(10, 10) . "\x2c" . pwords(0, 0, 9, 9) . "\0";
    write_file("$folder/unknown.bin", $unknown);
    push @{$m->{tokens}[0]{monikers}}, {type => 0x04c1, raw => 'unknown.bin'};
    save_manifest($folder, $m);
    my $db = rebuilt($folder, "$temp/raw.000");
    is(tokens($db)->[0][1][-1][1], $unknown, 'unknown GString bytes retained');
    quiet(\&export_db, "$temp/raw.000", "$temp/unknown");
    like(manifest("$temp/unknown")->{tokens}[0]{monikers}[-1]{unsupported}, qr/opcode/, 'unsupported graphics reported');
    push @{$m->{tokens}}, $m->{tokens}[0];
    save_manifest($folder, $m);
    write_file("$temp/keep.000", 'keep me');
    dies_like(sub { quiet(\&build_db, $folder, "$temp/keep.000") }, qr/unique/, 'duplicate tokens rejected');
    is(read_file("$temp/keep.000"), 'keep me', 'failed build leaves target intact');
    pop @{$m->{tokens}};
    $m->{tokens}[0]{monikers}[0]{png} = '../outside.png';
    write_file("$temp/outside.png", 'outside');
    save_manifest($folder, $m);
    dies_like(sub { quiet(\&build_db, $folder, "$temp/keep.000") }, qr/escapes/, 'path traversal rejected');
    for my $data ('bad', substr(read_file($fixture), 0, 280), substr(read_file($fixture), 0, 1000)) {
        dies_like(sub { database($data) }, qr/tokendb:/, 'corrupt database rejected');
    }
    $m->{tokens} = [];
    save_manifest($folder, $m);
    is_deeply(tokens(rebuilt($folder, "$temp/empty.000")), [], 'empty database supported');
    dies_like(sub { parse_cvtpcx('system("bad")') }, qr/unexpected/, 'converter output is parsed, never evaluated');
};

subtest 'PNG import via cvtpcx' => sub {
    plan skip_all => 'set CVTPCX to test PNG import' unless $tool;
    my $folder = "$temp/import with spaces";
    quiet(\&export_db, $fixture, $folder);
    my $m = manifest($folder);
    my $png = $m->{tokens}[0]{monikers}[0]{png};
    my $pixels = pack('C*', 170,0,0,255, 0,0,0,0, 0,0,170,255, 255,255,255,255) x 6;
    write_file("$folder/$png", png_bytes({width => 4, height => 6, rgba => $pixels}));
    my $after = tokens(rebuilt($folder, "$temp/changed.000"));
    my $image = render_moniker($after->[0][1][0][1]);
    is_deeply([$image->{width}, $image->{height}], [4, 6], 'PNG dimension changes imported');
    is($image->{rgba}, $pixels, 'color pixels and transparency imported');
    my $before = tokens(database(read_file($fixture)));
    is_deeply($after->[0][1][1], $before->[0][1][1], 'other monikers remain byte-identical');
    my $new = {token_hex => unpack('H*', 'TEST'), manufacturer => 16431,
        monikers => [{type => 0x04c6, png => 'new.png'}, {type => 0x04c1, png => 'mono.png'},
                     {type => 0x04c7, png => 'eight.png'}]};
    write_file("$folder/new.png", png_bytes({width => 4, height => 6, rgba => $pixels}));
    write_file("$folder/eight.png", png_bytes({width => 4, height => 6, rgba => $pixels}));
    my $mono = pack('C*', 0,0,0,255, 255,255,255,255, 0,0,0,0);
    write_file("$folder/mono.png", png_bytes({width => 3, height => 1, rgba => $mono}));
    $m->{tokens} = [reverse @{$m->{tokens}}[0 .. $#{$m->{tokens}} - 1]];
    push @{$m->{tokens}}, $new;
    save_manifest($folder, $m);
    $after = tokens(rebuilt($folder, "$temp/added.000"));
    is(scalar(@$after), 90, 'remove and add token');
    is(substr($after->[-1][0], 0, 6), 'TEST' . pwords(16431), 'new token and manufacturer');
    is(render_moniker($after->[-1][1][0][1])->{rgba}, $pixels, 'PNG-only 4-bit moniker');
    is(render_moniker($after->[-1][1][1][1])->{rgba}, $mono, 'PNG-only masked monochrome');
    is(render_moniker($after->[-1][1][2][1])->{rgba}, $pixels, 'PNG-only 8-bit complex bitmap');
    my $indexed = "\x89PNG\r\n\x1a\n" .
        png_chunk('IHDR', pack('NNCCCCC', 2, 1, 8, 3, 0, 0, 0)) .
        png_chunk('PLTE', pack('C*', 17,33,55, 77,99,111)) .
        png_chunk('IDAT', Compress::Zlib::compress("\0\0\1")) . png_chunk('IEND', '');
    write_file("$folder/eight.png", $indexed);
    $after = tokens(rebuilt($folder, "$temp/indexed.000"));
    is(render_moniker($after->[-1][1][2][1])->{rgba}, pack('C*', 17,33,55,255, 77,99,111,255),
        'indexed 8-bit PNG retains custom palette colors');
    $m->{tokens}[-1]{monikers}[0]{type} = 0x80;
    save_manifest($folder, $m);
    dies_like(sub { quiet(\&build_db, $folder, "$temp/bad.000", $tool) }, qr/bits set/, 'PNG cannot have text moniker type');

    # The first manifest version used pixel hashes but no file hashes.
    my $legacy = manifest("$temp/fixture0");
    my $original = tokens(database(read_file($fixture)))->[0][1][0][1];
    $legacy->{tokens} = [$legacy->{tokens}[0]];
    $legacy->{tokens}[0]{monikers} = [$legacy->{tokens}[0]{monikers}[0]];
    delete $legacy->{tokens}[0]{monikers}[0]{png_sha256};
    delete $legacy->{tokens}[0]{monikers}[0]{raw_sha256};
    save_manifest("$temp/fixture0", $legacy);
    is(tokens(rebuilt("$temp/fixture0", "$temp/legacy.000"))->[0][1][0][1], $original,
        'old manifest and unchanged pixels retain original compressed moniker');
};

done_testing();
