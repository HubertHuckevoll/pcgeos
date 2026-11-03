#!/usr/bin/perl
# Implemented with ChatGPT Codex, prompted by MeyerK
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

sub read_file {
    open my $in, '<:raw', $_[0] or die "$_[0]: $!";
    return do { local $/; <$in> };
}
my $root = "$FindBin::Bin/../../../..";
my $source = read_file("$FindBin::Bin/../Main/mixer.goc");
# GenCopyTree locks its destination on the template's owner thread.
my $gp = read_file("$FindBin::Bin/../mixer.gp");
for my $resource ('Templates', 'Interface', 'AdvancedResource') {
    $gp =~ /^resource\s+$resource\s+ui-object\s*$/m
        or die "$resource must run on the UI thread for tree copying\n";
}
my $header = read_file("$root/CInclude/mixlib.goh");
my $lib = read_file("$root/Library/Audio/MixLib/Main/mixlib.goc");
my $code = "#include <assert.h>\n#include <stdlib.h>\n#include <stdio.h>\n";
$code .= "#define _pascal\n#define FALSE 0\n#define TRUE 1\n";
$code .= "typedef unsigned short word;\ntypedef unsigned char byte;\n";
$code .= "typedef int Boolean;\ntypedef unsigned long optr;\n";
$code .= join("\n", $header =~ /^(#define (?:BSMX_TOKEN_|VAL_TYPE_)\w+\s+\d+).*$/mg);
$code .= "\n" . join("\n", $source =~ /^(#define MIXER_\w+\s+\d+).*$/mg);
$header =~ /(typedef struct \{[^}]+\} MixerValue;)/s or die "Missing MixerValue\n";
$code .= "\n$1\n";
my @fields = $source =~ /^\@instance ([^;]+);/mg;
$code .= 'typedef struct {'.join(';', @fields).';} TestControl;' . "\n";
my @helpers = $source =~ /^(static (?:word|int|Boolean) _pascal Mixer\w+\([^;]*?\)\n\{.*?^\})/msg;
@helpers == 4 or die "Expected four arithmetic/descriptor helpers\n";
$code .= join("\n", @helpers);
$code .= <<'C';
static word written, rawValue, writeCount;
static void BSMixerSetValue(word token, byte type, byte left, byte right)
{
    assert(token && type == 2);
    written = left | ((word)right << 8);
    writeCount++;
}
static word BSMixerGetValue(word token, byte type)
{
    assert(token && type == 3);
    return rawValue;
}
#define WWFixedToInt(value) ((short)((value) >> 16))
C
my $handlers = 0;
while ($source =~ /^\@method MixerControlClass, (MSG_MIXER_(?:VOLUME|MUTE|ITEM|SWITCHES)_CHANGED)\n\{(.*?)^\}/msg) {
    my ($name, $body) = ($1, $2);
    $body =~ s/    \@call oself::MSG_MIXER_CONTROL_UPDATE\(\);\n//g;
    $code .= "\nstatic void $name(TestControl *pself, unsigned long value, " .
             "word selection, word selectedBooleans)\n{$body}\n";
    $handlers++;
}
$handlers == 4 or die "Missing control handlers\n";
$code .= "static void check_tables(void)\n{\n";
for my $driver ('BSD16', 'BSD8ST') {
    my $asm = read_file("$root/Driver/Sound/$driver/bsmixer.asm");
    for my $table (['1745',16], ['1345',9], ['1335',4]) {
        my ($chip, $expected) = @$table;
        $asm =~ /valTab$chip:\s*(.*?)subTab$chip:/s or die "Missing table\n";
        my $table_source = $1;
        $code .= "{ unsigned visible = 0; MixerValue d;\n";
        while ($table_source =~ /word\s+(\d+)[^\n]*\n\s*word\s+(\d+)[^\n]*\n\s*byte\s+(\d+),(\d+),(\d+)[^\n]*\n\s*byte\s+([0-9a-f]+)h/gi) {
            my ($token,$range,$type,$pos,$target,$flags) = ($1,$2,$3,$4,$5,hex($6));
            $code .= "d.valToken=$token; d.valRange=$range; d.valType=$type; " .
                     "d.valPos=$pos; d.valTarget=$target; " .
                     'd.valVisible='.($flags & 128).'; d.valStereoFlag='.($flags & 64).";\n" .
                     'assert(MixerDescribe(&d)=='.($flags & 128 ? 1 : 0)."); visible+=MixerDescribe(&d);\n";
        }
        $code .= "assert(visible==$expected); }\n";
    }
}
$code .= "}\n";
for my $label ($lib =~ /^\@chunk\s+char\s+bsmText\d+\[\]\s*=\s*"([^"]*)"/mg) {
    length($label) < 32 or die "MixLib label exceeds the application's buffer\n";
}
$code .= <<'C';
int main(void)
{
    unsigned l, r, volume, levels, peak, percent;
    TestControl c = {0};
    MixerValue d = {0};
    check_tables();
    assert(MixerToPercent(0)==0 && MixerToPercent(255)==100);
    assert(MixerFromPercent(0)==0 && MixerFromPercent(100)==255);
    assert(MixerFromPercent(65535)==255 && MixerToPercent(65535)==100);
    for (percent=0; percent<=100; percent++) {
        volume=MixerFromPercent(percent);
        assert(MixerToPercent(volume)==percent);
        assert(abs((int)(volume*100)-(int)(percent*255))<=50);
    }
    for (volume=0; volume<=255; volume++) {
        assert(abs((int)(MixerToPercent(volume)*255)-(int)(volume*100))<=127);
    }
    for (l=0; l<=255; l++) {
        for (r=0; r<=255; r++) {
            levels=l|(r<<8);
            peak=MixerPeak(levels);
            assert(peak==(l>r ? l : r));
        }
    }
    c.MCI_token=1; c.MCI_range=255; c.MCI_volume=192;
    MSG_MIXER_MUTE_CHANGED(&c,0,0,1);
    assert(written==0 && c.MCI_volume==192);
    MSG_MIXER_MUTE_CHANGED(&c,0,0,0);
    assert(written==0xc0c0);
    for (percent=0; percent<=100; percent++) {
        volume=MixerFromPercent(percent);
        MSG_MIXER_VOLUME_CHANGED(&c,(unsigned long)percent<<16,0,0);
        assert(written==volume*257 && c.MCI_muted==!volume);
        if (volume) {
            assert(c.MCI_volume==volume);
        }
        MSG_MIXER_MUTE_CHANGED(&c,0,0,1);
        assert(!written);
        MSG_MIXER_MUTE_CHANGED(&c,0,0,0);
        assert(written==c.MCI_volume*257);
    }
    MSG_MIXER_VOLUME_CHANGED(&c,0,0,0);
    assert(!written && c.MCI_volume==255);
    MSG_MIXER_MUTE_CHANGED(&c,0,0,0);
    assert(written==0xffff);
    writeCount=0;
    c.MCI_range=4; c.MCI_mask=0x0e;
    MSG_MIXER_ITEM_CHANGED(&c,0,0,0);
    MSG_MIXER_ITEM_CHANGED(&c,0,65535,0);
    assert(!writeCount);
    MSG_MIXER_ITEM_CHANGED(&c,0,2,0);
    assert(writeCount==1 && written==2);
    rawValue=0x81; c.MCI_mask=0x1f;
    MSG_MIXER_SWITCHES_CHANGED(&c,0,0,0x12);
    assert(written==0x92);
    d.valVisible=1; d.valToken=1; d.valTarget=1;
    d.valType=VAL_TYPE_SLIDER; d.valRange=255;
    assert(MixerDescribe(&d));
    d.valRange=256; assert(!MixerDescribe(&d));
    d.valRange=255; d.valToken=65535; assert(!MixerDescribe(&d));
    d.valToken=1; d.valTarget=0; assert(!MixerDescribe(&d));
    d.valTarget=1; d.valType=VAL_TYPE_BOOL; d.valRange=9;
    assert(!MixerDescribe(&d));
    puts("Mixer: driver tables, percentages, centered stereo levels, mute and routing OK");
    return 0;
}
C
$code =~ s{//[^\r\n]*}{}g;
my $temp = tempdir(CLEANUP => 1);
open my $out, '>:raw', "$temp/volume.c" or die $!;
print $out $code;
close $out or die $!;
system($ENV{CC} || 'cc', '-std=c89', '-pedantic-errors', '-O2',
       "$temp/volume.c", '-o', "$temp/volume") == 0 or die "C check compilation failed\n";
system("$temp/volume") == 0 or die "Mixer self-check failed\n";
