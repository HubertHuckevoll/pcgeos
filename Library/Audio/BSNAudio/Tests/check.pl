#!/usr/bin/env perl
# Exercise the actual PCM routines with a synchronous DMA/GEOS host shim.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
my $lib = abs_path(dirname(__FILE__).'/..');
my $tmp = tempdir('bsnpcm-XXXXXX', TMPDIR=>1, CLEANUP=>!$ENV{KEEP_TESTS});
open my $in, '<', "$lib/PCM/pcm.goc" or die $!;
my $source = do { local $/; <$in> };
$source =~ s/\@ifndef BSNWAV_NO_UI\b.*?\@endif\s*//sg;
open my $out, '>', "$tmp/pcm.inc" or die $!;
$source =~ /(typedef word _pascal BSNPcmReadCall\(.*?;)/s or die 'missing callback type';
print $out "$1\n";
for my $name (qw(BSNWReadPCM BSNWLoadCache BSNWFillSilence BSNWKonvertData BSNWLoadData BSNWPlay)) {
    $source =~ /^([^\n;{}]*\b$name\([^;]*?\)\n\{.*?^\})/ms
        or die "missing $name";
    print $out "$1\n";
}
print $out "#ifdef BSN_INTEGRATION_TEST\n";
for my $name (qw(BSNWDetermineSecondaryBufferLength BSNWPrepare BSNWRunPCM BSNPcmPlay)) {
    my $definition = $source;
    $definition =~ /^([^\n;{}]*\b$name\([^;]*?\)\n\{.*?^\})/ms
        or die "missing $name";
    print $out "$1\n";
}
open my $helpers, '<', "$lib/Main/subcode.goc" or die $!;
my $helper_source = do { local $/; <$helpers> };
$helper_source =~ /^(void _pascal BSNWInsertSample\([^;]*?\)\n\{.*?^\})/ms
    or die 'missing toggle insertion';
print $out "$1\n";
print $out "#endif\n";
close $out or die $!;
# geos.h is replaced only in this host check; production uses the real header.
open $out, '>', "$tmp/geos.h" or die $!;
print $out <<'HEADER';
#ifndef BSN_HOST_GEOS
#define BSN_HOST_GEOS
#include <stdint.h>
typedef uint8_t byte;
typedef uint16_t word;
typedef uint32_t dword;
typedef int Boolean;
typedef word MemHandle;
typedef dword optr;
#define _pascal
#define _export
#define FALSE 0
#define TRUE 1
#endif
HEADER
close $out or die $!;
open $out, '>', "$tmp/file.h" or die $!;
print $out <<'HEADER';
#ifndef BSN_HOST_FILE
#define BSN_HOST_FILE
#include <geos.h>
typedef word FileHandle;
#define FILE_POS_START 0
extern dword FileSize(FileHandle file);
extern dword FilePos(FileHandle file, dword offset, word mode);
extern word FileRead(FileHandle file, void *destP, word count, word flags);
#endif
HEADER
close $out or die $!;
my @flags = qw(-std=gnu89 -Werror=declaration-after-statement -O2);
system('gcc', @flags, '-I', $tmp, '-I', "$lib/../../../CInclude",
       "$lib/Tests/pcm.c", '-o', "$tmp/pcm") == 0 or die 'compile failed';
system("$tmp/pcm") == 0 or die 'PCM checks failed';

system('gcc', @flags, '-I', $tmp, '-I', "$lib/../../../CInclude", '-x', 'c',
       "$lib/WAV/wav.goc", "$lib/Tests/wav.c", '-o', "$tmp/wav") == 0
    or die 'WAV compile failed';
system("$tmp/wav", "$tmp/input.wav") == 0 or die 'WAV checks failed';

# Optional decoder-to-playback integration using the same actual PCM routines.
if (@ARGV) {
    my ($up, $reference_dir) = @ARGV;
    my $mp3 = "$lib/MP3Dec";
    my @core = map { "$mp3/$_.c" } qw(mp3frame mp3huff mp3imdct mp3synth mp3quant mp3ster);
    system('gcc', @flags, '-fwrapv', '-I', $tmp, '-I', $mp3,
        '-I', "$lib/../../../CInclude", '-DMP3_HOST_TEST', '-DMP3_HEAP_ONLY',
        '-DBSN_INTEGRATION_TEST', '-x', 'c', "$lib/Tests/pcm.c",
        "$mp3/Tests/stream.c", "$mp3/mp3api.c", "$mp3/mp3reader.goc",
        "$lib/WAV/wav.goc", @core, '-o', "$tmp/play") == 0 or die 'integration compile failed';
    for my $input (glob("$up/tests/data/*.mp3")) {
        (my $name = $input) =~ s|.*/||;
        for my $mode ('mp3', 'mp3-toggle') {
            system("$tmp/play", $mode, $input, "$tmp/play.pcm") == 0 or die 'playback failed';
            if (defined $reference_dir) {
                open my $ref, '<:raw', "$reference_dir/$name.pcm" or die $!;
                open my $played, '<:raw', "$tmp/play.pcm" or die $!;
                my $expected = do { local $/; <$ref> };
                my $actual = do { local $/; <$played> };
                my $skip = $mode eq 'mp3-toggle' ? 2 : 0;
                die 'playback PCM differs' unless substr($actual, $skip, length($expected)) eq $expected;
            }
        }
    }
    for my $bits (8, 16) {
        for my $channels (1, 2) {
            my $align = $channels * ($bits / 8);
            my $payload = pack('C*', 0..255);
            open my $wave, '>:raw', "$tmp/native.wav" or die $!;
            print $wave pack('a4Va4a4VvvVVvva4V', 'RIFF', 292, 'WAVE', 'fmt ', 16,
                            1, $channels, 44100, 44100*$align, $align, $bits,
                            'data', 256), $payload;
            close $wave or die $!;
            system("$tmp/play", 'wav', "$tmp/native.wav", "$tmp/wavplay.pcm") == 0
                or die 'WAV playback failed';
            open my $played, '<:raw', "$tmp/wavplay.pcm" or die $!;
            read($played, my $actual, 256) == 256 or die 'short WAV playback';
            die 'WAV playback PCM differs' unless $actual eq $payload;
        }
    }
    open my $wav, '>:raw', "$tmp/rate.wav" or die $!;
    print $wav pack('a4Va4a4VvvVVvva4V', 'RIFF', 40, 'WAVE', 'fmt ', 16,
                    1, 1, 48000, 96000, 2, 16, 'data', 4), "\0" x 4;
    close $wav or die $!;
    system("$tmp/play", 'wav', "$tmp/rate.wav", "$tmp/wavplay.pcm") == 0
        or die '48kHz rejection failed';
}
