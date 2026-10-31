#!/usr/bin/env perl
# Execute the semaphore call/branch flow from wav.asm with kernel/audio stubs.
# No GEOS runtime: deliberately delay the worker until after the caller returns.
use strict;
use warnings FATAL => 'all';
use File::Basename qw(dirname);

sub read_file {
    open my $f, '<', $_[0] or die "$!: $_[0]";
    local $/; return <$f>;
}
my $lib = dirname(__FILE__).'/..';
my $source = read_file($ARGV[0] // "$lib/wav.asm");
$source =~ s/;[^\n]*//g;
my (%code, %labels);
for my $name (qw(WavPlayFile WavPlaySoundAndDestroyThread
                 WavPlayFromWavFilePathBlock PlaySoundFromFile)) {
    $source =~ /^\Q$name\E\s+proc\b(.*?)^\Q$name\E\s+endp/ms
        or die "missing $name\n";
    my (@ops, %targets);
    for (split /\n/, $1) {
        $targets{$1} = @ops if /^\s*(\w+):/;
        push @ops, [$1, $2] if /^\s*(call|jc|jnc|jmp)\s+(\w+)/;
        push @ops, ['ret', ''] if /^\s*ret\b/;
    }
    $code{$name} = \@ops; $labels{$name} = \%targets;
}
# The audio stub covers either backend; neither may acquire the lock again.
for my $name (qw(PlaySoundFromFileLow ProcessRIFFFile)) {
    $source =~ /^\Q$name\E\s+proc\b(.*?)^\Q$name\E\s+endp/ms
        or die "missing $name\n";
    die "nested playback lock in $name\n" if $1 =~ /call\s+Wav(?:Un)?lockExclusive/i;
}
my $ui = read_file("$lib/../User/User/userMain.asm");
$ui =~ /; If there was a shutdown sound playing,(.*?)endif/s
    or die "missing shutdown wait\n";
$code{wait} = [map { ['call', $_] } $1 =~ /call\s+(\w+)/g];
push @{$code{wait}}, ['ret', ''];
my ($sem, $blocks, $failure, $audio, @workers);
sub task { return { stack => [[$_[0], 0]], cf => 0 }; }
sub run {
    my ($t) = @_;
    for (1..200) {
        return 'done' unless @{$t->{stack}};
        my $frame = $t->{stack}[-1];
        my ($name, $pc) = @$frame;
        my ($op, $arg) = @{$code{$name}[$pc] // die "fell off $name\n"};
        if ($op eq 'call') {
            if ($arg eq 'WavLockExclusive') {
                return 'blocked' unless $sem;
                $sem = 0;
            } elsif ($arg eq 'WavUnlockExclusive') {
                die "unbalanced unlock\n" if $sem;
                $sem = 1;
            } elsif ($arg eq 'MemAllocSetOwner') {
                $t->{cf} = $failure eq 'alloc';
                ++$blocks unless $t->{cf};
            } elsif ($arg eq 'MemFree') {
                die "double free\n" if --$blocks < 0;
            } elsif ($arg eq 'ThreadCreate') {
                die "worker published before reservation\n" if $sem;
                $t->{cf} = $failure eq 'create';
                push @workers, task('WavPlaySoundAndDestroyThread') unless $t->{cf};
            } elsif ($arg eq 'MemLock' || $arg eq 'FileSetCurrentPath' || $arg eq 'FileOpen') {
                my %errors = (MemLock => 'lock', FileSetCurrentPath => 'path', FileOpen => 'open');
                $t->{cf} = $failure eq $errors{$arg};
            } elsif ($arg eq 'PlaySoundFromFileLow') {
                die "playback outside reservation\n" if $sem;
                return 'playing' if $audio ne 'muted' && !$t->{played}++;
            } elsif (exists $code{$arg}) {
                ++$frame->[1];
                push @{$t->{stack}}, [$arg, 0];
                next;
            }
        } elsif ($op eq 'ret') {
            pop @{$t->{stack}}; next;
        } elsif ($op eq 'jmp' && $arg eq 'ThreadDestroy') {
            $t->{stack} = []; return 'done';
        } elsif ($op eq 'jmp' || ($op eq 'jc' && $t->{cf}) ||
                 ($op eq 'jnc' && !$t->{cf})) {
            $frame->[1] = $labels{$name}{$arg} // die "unknown label $arg\n";
            next;
        }
        ++$frame->[1];
    }
    die "control-flow loop\n";
}
for my $fail_case ('', qw(alloc create lock path open)) {
    for my $audio_case (qw(bestsound fallback muted)) {
        ($failure, $audio) = ($fail_case, $audio_case);
        ($sem, $blocks, @workers) = (1, 0);
        die "caller blocked\n" unless run(task('WavPlayFile')) eq 'done';
        my $wait = task('wait');
        if (@workers) {
            die "wait overtook delayed worker\n" unless run($wait) eq 'blocked';
            my $worker = shift @workers;
            my $state = run($worker);
            if ($state eq 'playing') {
                die "wait overtook playback\n" unless run($wait) eq 'blocked';
                die "worker blocked\n" unless run($worker) eq 'done';
            } else { die "worker blocked\n" unless $state eq 'done'; }
        }
        die "completion or cleanup failed: $failure/$audio\n"
            unless run($wait) eq 'done' && $sem == 1 && $blocks == 0;
    }
}
$failure = ''; $audio = 'bestsound';
($sem, $blocks, @workers) = (1, 0);
my $direct = task('PlaySoundFromFile');
die "direct playback failed\n" unless run($direct) eq 'playing';
my $queued = task('WavPlayFile');
die "overlapping playback\n" unless run($queued) eq 'blocked';
die "direct completion failed\n" unless run($direct) eq 'done';
die "queued request failed\n" unless run($queued) eq 'done';
die "queued playback failed\n" unless run($workers[0]) eq 'playing';
die "queued completion failed\n" unless run($workers[0]) eq 'done';
die "leaked reservation or request\n" unless $sem == 1 && $blocks == 0;
print "WAV completion: delayed worker, playback, direct/queued calls and failure cleanup pass\n";
