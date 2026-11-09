#!/usr/bin/env perl
# Check the real driver token lookup in standalone DOS. Author: Codex/MeyerK
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

my $root = "$FindBin::Bin/../../../..";
my $tmp = tempdir('mixer-tokens-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $watcom = $ENV{WATCOM} // die "set WATCOM\n";
chdir $tmp or die $!;
sub write_file {
    open my $out, '>:raw', $_[0] or die $!;
    print $out $_[1];
    close $out or die $!;
}
sub run { system(@_) == 0 or die "failed: @_\n"; }

write_file("$tmp/check.c", <<'C');
#include <assert.h>
#include <stdio.h>
#include <string.h>
extern void __cdecl RunToken(char *destP, unsigned token);
int main(void)
{
    static unsigned char buffer[40];
    unsigned long token;
    unsigned i;
    char *expectedP;

    for (token = 0; token <= 65535UL; token++) {
        expectedP = token == 50 ? "Input Source" :
                    token == 51 ? "token51" : "unknown";
        memset(buffer, 0xa5, sizeof(buffer));
        RunToken((char *)buffer + 4, (unsigned)token);
        assert(!strcmp((char *)buffer + 4, expectedP));
        for (i = 0; i < 4; i++) {
            assert(buffer[i] == 0xa5 && buffer[36 + i] == 0xa5);
        }
    }
    puts("All 65536 mixer tokens and buffer guards: PASS");
    return 0;
}
C

for my $driver ('BSD16', 'BSD8ST') {
    open my $in, '<:raw', "$root/Driver/Sound/$driver/bsmixer.asm" or die $!;
    my $source = do { local $/; <$in> };
    $source =~ s/\r\n/\n/g;
    $source =~ /BSMixerTokenToText\s+proc\s+far.*?\.enter\s*(.*?)\s*\.leave/s
        or die "missing $driver token lookup\n";
    my $body = $1;
    # Expand the ESP register-test macro; retain the actual lookup code.
    $body =~ s/\btst\s+(ax|al)\b/or $1,$1/g;
    $source =~ /^(tokenToTextList\b.*?^notfoundText\s+char[^\n]*)/ms
        or die "missing $driver token tables\n";
    my $tables = $1;
    $tables =~ s/\bchar\b/byte/g;
    write_file("$tmp/$driver.asm", <<'ASM' . $body . <<'END' . $tables . "\nend\n");
.8086
.model large,c
.code
public RunToken
RunToken proc far
    push bp
    mov bp,sp
    push ax
    push bx
    push cx
    push dx
    push es
    push si
    push di
    mov bx,ss:[bp+6]
    mov ax,ss:[bp+8]
    mov cx,ss:[bp+10]
ASM

    pop di
    pop si
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret
RunToken endp
END
    run('wasm', '-q', "-fo=$tmp/$driver.obj", "$tmp/$driver.asm");
    run('wcl', '-q', '-bt=dos', '-ml', '-0', "-i=$watcom/h",
        "-fo=$tmp/", "-fe=$tmp/$driver.exe", "$tmp/check.c", "$tmp/$driver.obj");
}
write_file("$tmp/all.bat", "BSD16.EXE >16.TXT\r\nif errorlevel 1 goto fail\r\n" .
    "BSD8ST.EXE >8.TXT\r\nif errorlevel 1 goto fail\r\necho PASS>PASSED.TXT\r\n" .
    "exit\r\n:fail\r\necho FAIL>FAILED.TXT\r\nexit\r\n");
{
    local $ENV{SDL_VIDEODRIVER} = 'offscreen';
    local $ENV{SDL_AUDIODRIVER} = 'dummy';
    my $pid = fork(); die $! unless defined $pid;
    if (!$pid) {
        open STDOUT, '>', "$tmp/basebox.log" or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        exec 'timeout', '45', 'basebox', '--noprimaryconf', '--nolocalconf', '--noautoexec',
            '--set', 'core=normal', '--set', 'cputype=386', '--set', 'cpu_cycles=max',
            '--set', 'nosound=true', '--exit', '-c', "mount c $tmp", '-c', 'c:',
            '-c', 'call all.bat';
        die $!;
    }
    waitpid($pid, 0); die "DOS token runner failed\n" if $?;
}
-f "$tmp/PASSED.TXT" or die "Mixer token checks failed\n";
print "BSD16/BSD8ST: all 65536 token values and buffer guards passed\n";
