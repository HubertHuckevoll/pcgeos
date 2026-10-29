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
