#!/usr/bin/env perl
# Run the real clear routines in standalone DOS. Do not start PC/GEOS.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);

my $repo = abs_path(dirname(__FILE__).'/../../../..');
my $tmp = tempdir('bsnisr-XXXXXX', TMPDIR=>1, CLEANUP=>!$ENV{KEEP_TESTS});
my $watcom = $ENV{WATCOM} // die "set WATCOM\n";
sub run { system(@_) == 0 or die "failed: @_\n"; }
sub write_file {
    my ($path, $text) = @_;
    open my $out, '>:raw', $path or die $!;
    print $out $text;
    close $out or die $!;
}

write_file("$tmp/check.c", <<'C');
#include <assert.h>
#include <dos.h>
#include <stdio.h>
#include <string.h>
unsigned bufferO2, bufferSegment;
unsigned char bsOptions, bsRecBits, bsRecDataFlag, bsRecDataHalf;
static unsigned char data[24000];
extern void __cdecl RunISR(void);
int main(void)
{
    static unsigned sizes[] = {0, 1, 2, 3, 7, 8, 255, 256, 257,
                               2940, 5880, 8192, 11768, 11769};
    unsigned size, option, half, bits, i, start, end, offset;
    unsigned char expected;
    /* The driver uses segment:0. Keep guards before and after its block. */
    offset = 16 - (FP_OFF(data) & 15);
    bufferSegment = FP_SEG(data) + (FP_OFF(data) + offset) / 16;
    assert(sizeof(unsigned) == 2);
    for (size=0; size<sizeof(sizes)/sizeof(sizes[0]); size++) {
        for (option=0; option<4; option++) {
            for (half=0; half<2; half++) {
                for (bits=8; bits<=DRIVER_BITS; bits+=8) {
                    memset(data, 0xa5, sizeof(data));
                    bufferO2 = sizes[size]; bsOptions = option;
                    bsRecBits = bits; bsRecDataHalf = half;
                    bsRecDataFlag = 255;
                    RunISR();
                    assert(bsRecDataFlag == 0 && bsRecDataHalf == (half^1));
                    start = offset + half * bufferO2;
                    end = start + ((option & 1) ? bufferO2 : 0);
                    for (i=0; i<sizeof(data); i++) {
                        expected = (i>=start && i<end) ?
                                   (bits==16 ? 0 : 0x80) : 0xa5;
                        assert(data[i] == expected);
                    }
                }
            }
        }
    }
    puts("ISR silence, options, odd lengths, guards, counter wrap: PASS");
    return 0;
}
C

for my $driver ('BSD16', 'BSD8ST') {
    open my $in, '<', "$repo/Driver/Sound/$driver/bsnwav.asm" or die $!;
    my $source = do { local $/; <$in> };
    $source =~ /BSNWISR\s+proc\s+far.*?\.enter\s*(.*?)\s*\.leave/s
        or die "missing $driver ISR";
    my $body = $1;
    # Expand only the ESP macros; keep the driver's actual instructions.
    $body =~ s/\btst\s+ds:\[bufferO2\]/cmp word ptr ds:[bufferO2],0/g;
    $body =~ s/\btst\s+al\b/or al,al/g;
    $body =~ s/\bclr\s+ax\b/xor ax,ax/g;
    my $asm = <<'ASM';
.8086
.model large,c
.data
extrn bufferO2:word, bufferSegment:word
extrn bsOptions:byte, bsRecBits:byte, bsRecDataFlag:byte, bsRecDataHalf:byte
.code
public RunISR
RunISR proc far
    push ax
    push cx
    push ds
    push di
    push es
    cld
ASM
    # The hardware handler also clears DF before it calls BSNWISR.
    $asm .= $body . <<'ASM';

    pop es
    pop di
    pop ds
    pop cx
    pop ax
    ret
RunISR endp
end
ASM
    write_file("$tmp/$driver.asm", $asm);
    run('wasm', '-q', "-fo=$tmp/$driver.obj", "$tmp/$driver.asm");
    my $bits = $driver eq 'BSD16' ? 16 : 8;
    run('wcl', '-q', '-bt=dos', '-ml', '-0', "-DDRIVER_BITS=$bits",
        "-i=$watcom/h", "-fo=$tmp/", "-fe=$tmp/$driver.exe",
        "$tmp/check.c", "$tmp/$driver.obj");
}

write_file("$tmp/all.bat", "BSD16.EXE >16.TXT\r\nif errorlevel 1 goto fail\r\n".
    "BSD8ST.EXE >8.TXT\r\nif errorlevel 1 goto fail\r\necho PASS>PASSED.TXT\r\n".
    "exit\r\n:fail\r\necho FAIL>FAILED.TXT\r\nexit\r\n");
{
    local $ENV{SDL_VIDEODRIVER} = 'offscreen';
    local $ENV{SDL_AUDIODRIVER} = 'dummy';
    my $pid = fork(); die $! unless defined $pid;
    if (!$pid) {
        open STDOUT, '>', "$tmp/basebox.log" or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        exec 'timeout', '60', 'basebox', '--noprimaryconf', '--nolocalconf', '--noautoexec',
            '--set', 'core=normal', '--set', 'cputype=386', '--set', 'cpu_cycles=max',
            '--set', 'nosound=true', '--exit', '-c', "mount c $tmp", '-c', 'c:',
            '-c', 'call all.bat';
        die $!;
    }
    waitpid($pid, 0); die "DOS ISR runner failed: $tmp/basebox.log\n" if $?;
}
die "ISR checks failed: $tmp\n" unless -f "$tmp/PASSED.TXT";
print "BSD16/BSD8ST ISR silence, options, odd lengths, guards, counter wrap: PASS\n";
