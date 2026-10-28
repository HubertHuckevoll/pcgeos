#!/usr/bin/env perl
# Instrument a temporary copy only; the shipped library has no timing hooks.
# Standalone DOS; never boots PC/GEOS. CPU/CYCLES select an emulator scenario.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Compare qw(compare);
my $lib = abs_path(dirname(__FILE__).'/..');
my $input = abs_path(shift // die "usage: $0 input.mp3\n");
my $tmp = tempdir('mp3prof-XXXXXX',TMPDIR=>1,CLEANUP=>!$ENV{KEEP_TESTS});
my $watcom = $ENV{WATCOM} // die 'set WATCOM';
make_path("$tmp/core");
for my $source (glob("$lib/*.c"),glob("$lib/*.h"),glob("$lib/core/*")) {
    next unless -f $source;
    (my $relative=$source)=~s/^\Q$lib\E\///;
    copy($source,"$tmp/$relative") or die $!;
}
sub read_file { open my $f,'<',$_[0] or die $!;local $/;return <$f>; }
sub write_file { open my $f,'>',$_[0] or die $!;print $f $_[1];close $f or die $!; }
sub run { system(@_) == 0 or die "failed: @_\n"; }
my $source=read_file("$tmp/core/pvmp3_framedecoder.inc");
my $start=index($source,'ERROR_CODE pvmp3_framedecoder(');
substr($source,$start,0)=<<'PROFILE';
#include <stdio.h>
#include <time.h>
static unsigned long profileTicks[8];
void Mp3ProfileReport(void)
{
    FILE *f=fopen("profile.txt","w");
    unsigned i;
    fprintf(f,"ticks_per_second %lu\n",(unsigned long)CLOCKS_PER_SEC);
    for(i=0;i<8;i++) fprintf(f,"%u %lu\n",i,profileTicks[i]);
    fclose(f);
}
PROFILE
$start=index($source,'ERROR_CODE pvmp3_framedecoder(');
my $brace=index($source,'{',$start);
substr($source,$brace+1,0)="\n    clock_t stamp, totalStamp;\n";
my $first=index($source,'    pVars->inputStream.pBuffer',$brace);
substr($source,$first,0)="    totalStamp=clock();\n";
my @functions=qw(pvmp3_huffman_parsing pvmp3_dequantize_sample pvmp3_stereo_proc
                 pvmp3_reorder pvmp3_alias_reduction pvmp3_imdct_synth pvmp3_poly_phase_synthesis);
for my $i (0..$#functions) {
    for my $name ($functions[$i],$i==2 ? 'pvmp3_mpeg2_stereo_proc' : ()) {
        my $at=index($source,"$name(",$brace);
        my $line=rindex($source,"\n",$at)+1;
        my $end=index($source,';',$at)+1;
        substr($source,$end,0)="\nprofileTicks[$i]+=(unsigned long)(clock()-stamp);\n";
        substr($source,$line,0)="stamp=clock();\n";
    }
}
my $end=index($source,'    return errorCode;',index($source,'    pExt->inputBufferUsedLength ='));
substr($source,$end,0)="    profileTicks[7]+=(unsigned long)(clock()-totalStamp);\n";
write_file("$tmp/core/pvmp3_framedecoder.inc",$source);
my $harness=read_file("$lib/Tests/corecheck.c");
$harness=~s/int main\(/void Mp3ProfileReport(void);\nint main(/;
$harness=~s/    return 0;/    Mp3ProfileReport();\n    return 0;/;
write_file("$tmp/bench.c",$harness);
my @core=map {"$tmp/$_.c"} qw(mp3frame mp3huff mp3imdct mp3synth mp3quant mp3ster);
my @asm = $ENV{MP3_ASM_OBJECT} ? ('-DMP3_386_DSP', $ENV{MP3_ASM_OBJECT}) : ();
run('wcl',qw(-q -bt=dos -ml -3 -zp1 -zu -s -ecp -of -of+ -ol -ol+ -ei -zdp -fpc -ox),
    "-i=$watcom/h","-i=$tmp/core","-fo=$tmp/","-fe=$tmp/bench.exe",
    "$tmp/bench.c",@core,"$tmp/mp3fxp.c",@asm);
run('gcc','-std=c89','-O2','-fwrapv','-I',"$lib/core","$lib/Tests/corecheck.c",
    map({"$lib/$_.c"} qw(mp3frame mp3huff mp3imdct mp3synth mp3quant mp3ster)), '-o',"$tmp/host");
run("$tmp/host",$input,"$tmp/host.pcm");
copy($input,"$tmp/input.mp3") or die $!;
my $cpu=$ENV{CPU}//'386';my $cycles=$ENV{CYCLES}//'15000';
my $pid=fork();die $! unless defined $pid;
if (!$pid) {
    $ENV{SDL_VIDEODRIVER}='offscreen';$ENV{SDL_AUDIODRIVER}='dummy';
    open STDOUT,'>',"$tmp/basebox.log" or die $!;open STDERR,'>&',\*STDOUT or die $!;
    exec 'timeout','300','basebox','--noprimaryconf','--nolocalconf','--noautoexec',
        '--set','output=texture','--set','texture_renderer=software','--set','nosound=true',
        '--set','core=normal','--set',"cputype=$cpu",'--set',"cpu_cycles=$cycles",'--exit',
        '-c',"mount c $tmp",'-c','c:','-c','bench input.mp3 output.pcm';
    die $!;
}
waitpid($pid,0);die 'BaseBox failed' if $?;
compare("$tmp/host.pcm","$tmp/OUTPUT.PCM")==0 or die 'profile PCM differs';
print "CPU=$cpu cycles=$cycles; exact PCM; results: $tmp\n",read_file("$tmp/PROFILE.TXT");
