#!/usr/bin/env perl
# Host checks. Pass the pinned micro-mp3 checkout, optionally minimp3/vectors.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Compare qw(compare);

my $repo = abs_path(dirname(__FILE__) . '/../../..');
my $lib = "$repo/Library/MP3Dec";
my $up = abs_path(shift // die "usage: $0 micro-mp3-checkout [vectors]\n");
my $vectors = shift;
my $tmp = tempdir('mp3check-XXXXXX', TMPDIR => 1, CLEANUP => !$ENV{KEEP_TESTS});
my $revision = `git -C "$up" rev-parse HEAD`;
chomp $revision;
die "wrong microMP3 revision\n" unless $revision eq '07c18fa2d045b89bcc19aa0c1dc5333ce69b39db';
my @core = map { "$lib/$_.c" } qw(mp3frame mp3huff mp3imdct mp3synth mp3quant mp3ster);
my @flags = qw(-std=c89 -pedantic-errors -Werror=declaration-after-statement -fwrapv -O2);
my @sanitize = $ENV{SANITIZE} ? (qw(-g -O1 -fno-sanitize=shift -fno-omit-frame-pointer), '-fsanitize=address,undefined') : ();
sub run { system(@_) == 0 or die "failed: @_\n"; }
sub same { compare($_[0], $_[1]) == 0 or die "PCM differs: @_\n"; }
sub score_pcm {
    my ($decoded, $reference, $offset) = @_;
    open my $d, '<:raw', $decoded or die $!;
    open my $r, '<:raw', $reference or die $!;
    local $/;
    my @decoded = unpack('s<*', <$d>);
    my @reference = unpack('s<*', <$r>);
    close $d;close $r;
    my $count = @decoded - $offset;
    $count = @reference if @reference < $count;
    die 'no reference overlap' unless $count > 0;
    my ($sum, $peak) = (0, 0);
    for my $i (0..$count-1) {
        my $delta = abs($decoded[$offset+$i] - $reference[$i]);
        $sum += $delta*$delta;
        $peak = $delta if $delta > $peak;
    }
    my $psnr = $sum ? 10*log(32767*32767*$count/$sum)/log(10) : 999;
    die "trusted PCM accuracy failed: PSNR=$psnr peak=$peak" if $psnr < 96 || $peak > 2;
    printf "trusted PCM: %.2f dB, peak %d LSB, overlap %d samples\n", $psnr, $peak, $count;
}
sub write_file { my ($p,$s)=@_;open my $f,'>',$p or die $!;print $f $s;close $f or die $!; }

run('gcc', @flags, "$lib/Tests/fixed.c", '-o', "$tmp/fixed");
run("$tmp/fixed");
run('gcc', @flags, '-I', "$lib/core", "$lib/Tests/corecheck.c", @core, '-o', "$tmp/core");
run('g++', '-O2', '-fwrapv', '-I', "$up/src/opencore-mp3dec", '-x', 'c++',
    "$lib/Tests/corecheck.c", glob("$up/src/opencore-mp3dec/*.cpp"), '-o', "$tmp/original");
run('gcc', @flags, @sanitize, '-DMP3_HOST_TEST', '-I', "$repo/CInclude",
    "$lib/Tests/stream.c", "$lib/mp3api.c", @core, '-o', "$tmp/stream");
run('gcc', @flags, '-I', "$lib/core", "$lib/Tests/dsp.c", "$lib/mp3imdct.c", '-o', "$tmp/dsp");
my $saved = Cwd::getcwd();chdir $tmp or die $!;run("$tmp/dsp");chdir $saved or die $!;

# The real writer compiles against tiny host platform/file shims.
make_path("$tmp/include/Ansi");
write_file("$tmp/include/geos.h", "#include \"$lib/Tests/host.h\"\n");
write_file("$tmp/include/Ansi/string.h", "#include <string.h>\n");
write_file("$tmp/include/file.h", <<'HEADER');
#ifndef HOST_FILE_H
#define HOST_FILE_H
#include <geos.h>
typedef word FileHandle;
#define FALSE 0
#define FILE_POS_START 0
word FileWrite(FileHandle file, const void *dataP, word size, word flags);
dword FilePos(FileHandle file, dword offset, word mode);
#endif
HEADER
my $app = "$repo/Appl/MP3Wav";
my @includes = ('-I', "$tmp/include", '-I', "$repo/CInclude");
run('gcc', @flags, @includes, "$app/Tests/wavcheck.c", "$app/wavwriter.c", '-o', "$tmp/wavcheck");
run("$tmp/wavcheck", "$tmp/test.wav");
run('gcc', @flags, @sanitize, @includes, '-DMP3_HOST_TEST', '-DMP3_HEAP_ONLY',
    "$app/Tests/convert.c", "$app/wavwriter.c", "$lib/Tests/stream.c",
    "$lib/mp3api.c", @core, '-o', "$tmp/convert");
run('gcc', @flags, @sanitize, '-DMP3_HOST_TEST', '-DMP3_HEAP_ONLY', '-I', "$repo/CInclude",
    "$lib/Tests/malformed.c", "$lib/Tests/stream.c", "$lib/mp3api.c", @core, '-o', "$tmp/malformed");
run("$tmp/malformed", "$up/tests/data/sine_stereo_44100.mp3",
    "$up/tests/data/sine_mono_44100_crc.mp3");
my @samples = glob("$up/tests/data/*.mp3");
die "no sample corpus\n" unless @samples == 8;
for my $sample (@samples) {
    run("$tmp/original", $sample, "$tmp/reference.pcm");
    run("$tmp/core", $sample, "$tmp/core.pcm");
    same("$tmp/reference.pcm", "$tmp/core.pcm");
    for my $chunk (1, 3, 7, 127, 2048, 65535) {
        run("$tmp/stream", $sample, "$tmp/stream.pcm", $samples[3], "$tmp/other.pcm", $chunk, 511);
        same("$tmp/reference.pcm", "$tmp/stream.pcm");
    }
    run("$tmp/convert", $sample, "$tmp/converted.wav");
    open my $wav, '<:raw', "$tmp/converted.wav" or die $!;
    read($wav, my $header, 44) == 44 or die 'short WAV';
    local $/;my $pcm = <$wav>;close $wav;
    open my $raw, '<:raw', "$tmp/reference.pcm" or die $!;my $expected = <$raw>;close $raw;
    die 'WAV PCM differs' unless $pcm eq $expected;
    die 'WAV lengths differ' unless unpack('V',substr($header,4,4)) == length($pcm)+36 &&
                                    unpack('V',substr($header,40,4)) == length($pcm);
    print basename($sample), ": exact core, streaming, and WAV PCM\n";
}
if (defined $vectors) {
    for my $input (glob("$vectors/l3-*.bit"), glob("$vectors/M2L3_*.bit"), "$vectors/ILL2_layer3.bit") {
        next unless -f $input;
        next if $input =~ /he_free|nonstandard-small|id3v2-only|vbrtag-oob-read/;
        my $reference_status = system("$tmp/original", $input, "$tmp/reference.pcm");
        if ($reference_status == (2 << 8)) {
            die "adapted core emitted unexpected PCM" unless
                system("$tmp/core", $input, "$tmp/core.pcm") == (2 << 8);
            print basename($input), ": both cores reject/no PCM\n";
            next;
        }
        die "reference decoder failed" if $reference_status;
        run("$tmp/core", $input, "$tmp/core.pcm");
        same("$tmp/reference.pcm", "$tmp/core.pcm");
        # Recovery after corruption intentionally clears core state. Only
        # vectors with trusted PCM references enter the streaming accuracy gate.
        next if $input =~ /sideinfo|vbrtag/ || !-f ($input =~ s/\.bit$/.pcm/r);
        run("$tmp/stream", $input, "$tmp/stream.pcm", $samples[3], "$tmp/other.pcm", 7, 511);
        same("$tmp/reference.pcm", "$tmp/stream.pcm");
        (my $trusted = $input) =~ s/\.bit$/.pcm/;
        score_pcm("$tmp/stream.pcm", $trusted, basename($input) eq 'l3-sin1k0db.bit' ? 4608 : 0);
        if ($input =~ /nonstandard-(?:apetag|id3v1|id3v2)\.bit$/) {
            run("$tmp/convert", $input, "$tmp/metadata.wav");
        }
        print basename($input), ": exact reference core and streaming PCM\n";
    }
}
print "All host checks passed (temporary outputs: $tmp).\n";
