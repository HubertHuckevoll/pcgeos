#!/usr/bin/env perl
# Check the C/driver register boundary in standalone DOS. Author: Codex/MeyerK
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

my $lib = "$FindBin::Bin/..";
my $watcom = $ENV{WATCOM} // die "set WATCOM\n";
my $tmp = tempdir('bsn-driver-XXXXXX', TMPDIR => 1, CLEANUP => !$ENV{KEEP_TESTS});
print "$tmp\n" if $ENV{KEEP_TESTS};
sub read_file {
    open my $in, '<:raw', $_[0] or die $!;
    local $/;
    return <$in>;
}
sub write_file {
    open my $out, '>:raw', $_[0] or die $!;
    print $out $_[1];
    close $out or die $!;
}
sub run { system(@_) == 0 or die "failed: @_\n"; }

write_file("$tmp/check.c", <<'C');
#include <assert.h>
#include <stdio.h>
extern unsigned __watcall RunProbe(void);
int main(void)
{
    assert(RunProbe());
    puts("Driver query return value and preserved C registers: PASS");
    return 0;
}
C

my $source = read_file("$lib/Driver/driverManager.asm");
$source =~ /BSNWASMQUERYDEVICECAPABILITY\s+proc\s+far\s+(?:;[^\n]*\n\s*)*uses\s+([^;\n]+)[^\n]*\n\s*\.enter\s*(.*?)\s*\.leave/s
    or die "missing driver query wrapper\n";
my ($uses, $body) = ($1, $2);
my @registers = $uses =~ /\b(ax|bx|cx|dx|si|di|bp|ds|es)\b/g;
$body =~ s/es:\[bx\]\.DIS_strategy/dword ptr es:[bx]/g;
my $asm = <<'ASM';
.8086
.model large
.data
DriverTable dw offset QueryDriver, seg QueryDriver
driverInfo dw offset DriverTable, seg DriverTable
.code
DRE_SOUND_QUERY_DEVICE_CAPABILITY equ 12
public RunProbe_
RunProbe_ proc far
    push bp
    push si
    push cx
    mov bp,0a55ah
    mov si,5
    mov cx,1234h
    call BSNWASMQUERYDEVICECAPABILITY
    cmp ax,1
    jne failed
    cmp bp,0a55ah
    jne failed
    cmp si,5
    jne failed
    cmp cx,1234h
    jne failed
    jmp probeDone
failed:
    xor ax,ax
probeDone:
    pop cx
    pop si
    pop bp
    ret
RunProbe_ endp
BSNWASMQUERYDEVICECAPABILITY proc far
ASM
$asm .= join('', map { "    push $_\n" } @registers) . $body . "\n";
$asm .= join('', map { "    pop $_\n" } reverse @registers) . <<'ASM';
    ret
BSNWASMQUERYDEVICECAPABILITY endp
; Native query outputs include BP:SI. Both BestSound drivers clear them.
QueryDriver proc far
    mov ax,9
    mov bx,1234h
    mov cx,5678h
    mov dx,1
    mov di,3
    xor bp,bp
    xor si,si
    ret
QueryDriver endp
end
ASM
write_file("$tmp/query.asm", $asm);
run('wasm', '-q', "-fo=$tmp/query.obj", "$tmp/query.asm");
run('wcl', '-q', '-bt=dos', '-ml', '-0', "-i=$watcom/h", "-fo=$tmp/",
    "-fe=$tmp/check.exe", "$tmp/check.c", "$tmp/query.obj");
write_file("$tmp/run.bat", "check.exe >RESULT.TXT\r\nif errorlevel 1 goto fail\r\n" .
    "echo PASS>PASSED.TXT\r\n:fail\r\nexit\r\n");
{
    local $ENV{SDL_VIDEODRIVER} = 'offscreen';
    local $ENV{SDL_AUDIODRIVER} = 'dummy';
    my $pid = fork(); die $! unless defined $pid;
    if (!$pid) {
        open STDOUT, '>', "$tmp/basebox.log" or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        exec 'timeout', '45', 'basebox', '--noprimaryconf', '--nolocalconf', '--noautoexec',
            '--set', 'core=normal', '--set', 'nosound=true', '--exit',
            '-c', "mount c $tmp", '-c', 'c:', '-c', 'call run.bat';
        die $!;
    }
    waitpid($pid, 0); die "DOS driver runner failed\n" if $?;
}
print read_file("$tmp/RESULT.TXT");
-f "$tmp/PASSED.TXT" or die "Driver register check failed\n";
