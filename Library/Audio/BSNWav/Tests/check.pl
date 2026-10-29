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
print $out "/* Host types are declared by pcm.c. */\n";
close $out or die $!;
my @flags = qw(-std=gnu89 -Werror=declaration-after-statement -O2);
system('gcc', @flags, '-I', $tmp, '-I', "$lib/../../../CInclude",
       "$lib/Tests/pcm.c", '-o', "$tmp/pcm") == 0 or die 'compile failed';
system("$tmp/pcm") == 0 or die 'PCM checks failed';
