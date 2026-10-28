#!/usr/bin/env perl
# Standalone DOS only. Never starts PC/GEOS or uses the user's BaseBox config.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Compare qw(compare);

my $repo = abs_path(dirname(__FILE__) . '/../../..');
my $lib = "$repo/Library/MP3Dec";
my $up = abs_path(shift // die "usage: $0 micro-mp3-checkout [vectors]\n");
my $vectors = shift;
my $tmp = tempdir('mp3wat-XXXXXX', TMPDIR => 1, CLEANUP => !$ENV{KEEP_TESTS});
my $watcom = $ENV{WATCOM} // die "set WATCOM\n";
my @core = map { "$lib/$_.c" } qw(mp3frame mp3huff mp3imdct mp3synth mp3quant mp3ster);
my @flags = qw(-q -bt=dos -ml -3 -zp1 -zu -s -ecp -of -of+ -ol -ol+ -ei -zdp -fpc);
sub run { system(@_) == 0 or die "failed: @_\n"; }
sub same { compare($_[0], $_[1]) == 0 or die "target data differs: @_\n"; }
run('gcc', '-std=c89', '-O2', '-fwrapv', '-I', "$lib/core",
    "$lib/Tests/corecheck.c", @core, '-o', "$tmp/host");
run('gcc', '-std=c89', '-O2', '-fwrapv', '-I', "$lib/core",
    "$lib/Tests/dsp.c", "$lib/mp3imdct.c", '-o', "$tmp/hostdsp");
run('gcc', '-std=c89', '-O2', "$lib/Tests/target.c", '-o', "$tmp/hostmath");
my $saved=Cwd::getcwd();chdir $tmp or die $!;
run("$tmp/hostdsp");run("$tmp/hostmath");
rename('dsp.bin','hostdsp.bin') or die $!;
rename('math.pcm','hostmath.pcm') or die $!;
chdir $saved or die $!;
for my $variant ('ec', 'nc') {
    my @options = $variant eq 'nc' ? ('-ox') : ();
    run('wcl', @flags, @options, "-i=$watcom/h", "-i=$lib/core", "-fo=$tmp/",
        "-fe=$tmp/$variant.exe", "$lib/Tests/corecheck.c", @core, "$lib/mp3fxp.c");
}
run('wcl', @flags, '-ox', "-i=$watcom/h", "-i=$lib/core", "-fo=$tmp/",
    "-fe=$tmp/dsp.exe", "$lib/Tests/dsp.c", "$lib/mp3imdct.c", "$lib/mp3fxp.c");
run('wcl', @flags, '-ox', "-i=$watcom/h", "-fo=$tmp/",
    "-fe=$tmp/math.exe", "$lib/Tests/target.c", "$lib/mp3fxp.c");
run('wcl', @flags, '-ox', '-D__GEOS__', '-D__WATCOM__',
    "-i=$watcom/h", "-i=$repo/CInclude", "-fo=$tmp/", "-fe=$tmp/thunk.exe",
    "$lib/Tests/thunk.c");
my @inputs=glob("$up/tests/data/*.mp3");
if (defined $vectors) {
    push @inputs, grep { !/sideinfo|he_free|nonstandard-small|id3v2-only|vbrtag/ }
        (glob("$vectors/l3-*.bit"),glob("$vectors/M2L3_*.bit"),"$vectors/ILL2_layer3.bit");
}
my @batch=('thunk.exe','if errorlevel 1 goto fail','dsp.exe','if errorlevel 1 goto fail','math.exe','if errorlevel 1 goto fail');
my $i=0;
for my $input (@inputs) {
    next unless -f $input;
    copy($input,"$tmp/t$i.mp3") or die $!;
    run("$tmp/host",$input,"$tmp/h$i.pcm");
    push @batch, "ec.exe t$i.mp3 e$i.pcm",'if errorlevel 1 goto fail',
                 "nc.exe t$i.mp3 n$i.pcm",'if errorlevel 1 goto fail';
    $i++;
}
push @batch, 'echo PASS>passed.txt','exit',':fail','echo FAIL>failed.txt','exit';
open my $bat,'>:raw',"$tmp/all.bat" or die $!;
print $bat join("\r\n",@batch),"\r\n";close $bat or die $!;
print "Running $i inputs with both target variants; outputs: $tmp\n";
{
    local $ENV{SDL_VIDEODRIVER}='offscreen';
    local $ENV{SDL_AUDIODRIVER}='dummy';
    my $pid=fork();die $! unless defined $pid;
    if (!$pid) {
        open STDOUT,'>',"$tmp/basebox.log" or die $!;
        open STDERR,'>&',\*STDOUT or die $!;
        exec 'timeout','900','basebox','--noprimaryconf','--nolocalconf','--noautoexec',
             '--set','output=texture','--set','texture_renderer=software',
             '--set','core=normal','--set','cputype=386','--set','cpu_cycles=max',
             '--set','nosound=true','--exit','-c',"mount c $tmp",'-c','c:',
             '-c','call all.bat';
        die $!;
    }
    waitpid($pid,0);die "BaseBox failed; see $tmp/basebox.log\n" if $?;
}
die "DOS checks failed or did not finish\n" unless -f "$tmp/PASSED.TXT";
same("$tmp/hostdsp.bin","$tmp/DSP.BIN");
same("$tmp/hostmath.pcm","$tmp/MATH.PCM");
for my $n (0..$i-1) {
    same("$tmp/h$n.pcm","$tmp/E$n.PCM");
    same("$tmp/h$n.pcm","$tmp/N$n.PCM");
}
print "Watcom EC/NC flags: $i inputs, exact PCM; DSP, Pascal thunk and 6000 products: PASS\n";
