#!/usr/bin/env perl
# Exercise the actual globe policy and visibility update without GEOS.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

sub read_source {
    open my $file, '<:raw', $_[0] or die $!;
    local $/;
    my $text = <$file>;
    $text =~ s/\r\n/\n/g;
    return $text;
}

my $operations = read_source("$FindBin::Bin/../htmlview/HTMLViewOperation.goc");
$operations =~ /\@extern method HTMLVApplicationClass, MSG_HMLVA_UPDATE_GLOBE\n(\{.*?^})/ms
    or die "Missing globe update handler\n";
my $update = $1;
$update =~ s/\@call SpinningLogo::MSG_GEN_GET_USABLE\(\)/globeUsable/g;
$update =~ s/\@send SpinningLogo::MSG_GLBANIM_AUTO_RUN\((.*?)\)/SetAutoRun($1)/g;

$operations =~ /\@extern method HTMLVApplicationClass, MSG_HMLVA_START_OPERATION\n\{(.*?)^}/ms
    or die "Missing operation start\n";
my $start = $1;
$start =~ /\@ifndef COMPILE_OPTION_TURN_OFF_LOGO\n(.*?)\@endif/s
    or die "Missing globe startup\n";
$start = $1;
$start =~ s/\@send self::MSG_HMLVA_UPDATE_GLOBE\(\)/UpdateGlobe(\&app)/g;

my $options = read_source("$FindBin::Bin/../htmlview/HTMLViewOptions.goc");
$options =~ /^(void UpdateGlobeInSimpleButtonToolbar\(Boolean enabled\)\n\{.*?^})/ms
    or die "Missing visibility update\n";
my $toggle = $1;
$toggle =~ s/\@SpinningLogo/1/g;
$toggle =~ s/\@send application::MSG_HMLVA_UPDATE_GLOBE\(\)/UpdateGlobe(\&app)/g;

my $tmp = tempdir(CLEANUP => 1);
open my $test, '>', "$tmp/check.c" or die $!;
print $test <<'C';
#include <assert.h>
#include <stdio.h>
typedef int Boolean;
typedef struct { unsigned short HVAI_operationLevel; } Application;
static Application app;
static int globeUsable, autoRun;
static void SetAutoRun(Boolean enabled) { autoRun = enabled; }
static void UsableOrNot(int obj, Boolean enabled)
{
    assert(obj == 1);
    globeUsable = enabled;
}
C
print $test "static void UpdateGlobe(Application *pself)\n$update\n$toggle\n";
print $test "static void StartGlobe(void)\n{\n$start}\n";
print $test <<'C';
int main(void)
{
    int level, visible;
    for (level = 0; level <= 2; level++) {
        app.HVAI_operationLevel = (unsigned short)level;
        for (visible = 0; visible <= 1; visible++) {
            globeUsable = visible;
            autoRun = -1;
            StartGlobe();
            assert(autoRun == (level != 0 && visible));
            UpdateGlobeInSimpleButtonToolbar(0);
            assert(!autoRun && !globeUsable);
            StartGlobe();
            assert(!autoRun);
            UpdateGlobeInSimpleButtonToolbar(1);
            assert(globeUsable && autoRun == (level != 0));
            app.HVAI_operationLevel = 0;
            UpdateGlobeInSimpleButtonToolbar(0);
            UpdateGlobeInSimpleButtonToolbar(1);
            assert(!autoRun);
            app.HVAI_operationLevel = (unsigned short)level;
        }
    }
    puts("Globe startup, hide/show and nested load checks passed.");
    return 0;
}
C
close $test or die $!;
system('cc', '-std=c89', '-Wall', '-Wextra', '-Werror',
       "$tmp/check.c", '-o', "$tmp/check") == 0 or die "Host compilation failed\n";
system("$tmp/check") == 0 or die "Globe check failed\n";
