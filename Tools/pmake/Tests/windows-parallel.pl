#!/usr/bin/env perl
# Native Windows pmake regression tests. Linux checks preserve its current rules.
use strict;
use warnings;
sub subtest;
sub skip;
our $TODO;
BEGIN {
    if (!@ARGV || $ARGV[0] !~ /^--(?:worker|native-fixtures)$/) {
        require Test::More;
        Test::More->import;
    }
}
use Cwd qw(abs_path getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Fcntl qw(:flock);
use IPC::Open3;
use POSIX qw(WNOHANG);
use Symbol qw(gensym);
use Time::HiRes qw(time sleep);

sub WriteFile {
    my ($name, $text) = @_;
    open my $file, '>', $name or die "$name: $!\n";
    print {$file} $text or die "$name: $!\n";
    close $file or die "$name: $!\n";
}

sub ReadFile {
    my ($name) = @_;
    open my $file, '<', $name or die "$name: $!\n";
    local $/;
    return <$file>;
}

sub WaitFor {
    my ($condition, $description) = @_;
    my $deadline = time + 12;
    until ($condition->()) {
        die "Timeout: $description\n" if time >= $deadline;
        sleep 0.02;
    }
}

sub Event {
    my ($event, $id) = @_;
    open my $file, '>>', 'events' or die "events: $!\n";
    flock $file, LOCK_EX or die "flock: $!\n";
    print {$file} "$event $id\n" or die "events: $!\n";
    close $file or die "events: $!\n";
}

# Workers use marker handshakes. A scheduler that drains all jobs will time out.
if (@ARGV && $ARGV[0] eq '--worker') {
    shift @ARGV;
    my ($mode, @args) = @ARGV;
    if ($mode eq 'hold' || $mode eq 'descendant') {
        $SIG{INT} = 'IGNORE';
        WriteFile("pid-$$", '');
        WriteFile($args[0], 'partial');
        if ($mode eq 'descendant') {
            system($^X, abs_path($0), '--worker', 'hold', "$args[0]-leaf");
        } else {
            sleep 300;
            WriteFile("survived-$$", '');
        }
    } elsif ($mode eq 'pool') {
        my ($id, $limit, $group) = @args;
        $group //= '';
        WaitFor(sub { -e 'peer-started' }, 'parent peer') if $group eq 'child';
        Event('start', $id);
        WriteFile("started-$group-$id", '');
        WaitFor(sub { scalar(() = glob("started-$group-*")) >= $limit }, 'initial pool');
        Event('end', $id);
    } elsif ($mode eq 'peer') {
        Event('start', 'peer');
        WriteFile('peer-started', '');
        WaitFor(sub { scalar(() = glob('started-child-*')) >= 2 }, 'recursive workers');
        Event('end', 'peer');
    } elsif ($mode eq 'slow') {
        WriteFile('slow-started', '');
        WaitFor(sub { -e 'replacement' }, 'replacement while slow job runs');
        WriteFile('slow-done', '');
    } elsif ($mode eq 'short') {
        WaitFor(sub { -e 'slow-started' }, 'slow start');
        WriteFile('short-done', '');
    } elsif ($mode eq 'replacement') {
        die "Dependency or refill order is wrong\n" unless -e 'short-done' && !-e 'slow-done';
        WriteFile('replacement', '');
    } elsif ($mode eq 'touch') {
        WriteFile($args[0], '');
    } elsif ($mode eq 'require') {
        die "Missing dependency $args[0]\n" unless -e $args[0];
        WriteFile($args[1], '');
    } elsif ($mode eq 'fail') {
        exit $args[0];
    } elsif ($mode eq 'flags') {
        WriteFile('flags', $ENV{PMAKE} // '');
    } elsif ($mode eq 'env') {
        die "Recipe environment was lost\n" unless ($ENV{PMAKE_TEST_VALUE} // '') eq 'kept';
        WriteFile('env-ok', '');
    } elsif ($mode eq 'output') {
        print "stdout-marker\n";
        print STDERR "stderr-marker\n";
    } elsif ($mode eq 'args') {
        die "Quoted argument was lost\n" unless $args[0] eq 'two words';
        WriteFile('args-ok', '');
    } else {
        die "Unknown worker mode: $mode\n";
    }
    exit 0;
}

# Make persistent inputs for the manual Windows cancellation and handle checks.
if (@ARGV && $ARGV[0] eq '--native-fixtures') {
    shift @ARGV;
    my $directory = shift @ARGV // die "A new fixture directory is required\n";
    mkdir $directory or die "$directory: $!\n";
    my $self = abs_path($0);
    chdir $directory or die "chdir: $!\n";
    my $command = qq{"$^X" "$self" --worker};
    WriteFile('Cancel.mk', "all: recursive partial precious\n.PRECIOUS: precious\n" .
        "recursive:\n\t\@\"\$(.PMAKE)\" -r -f Child.mk\n" .
        "partial:\n\t\@$command descendant partial\n" .
        "precious:\n\t\@$command descendant precious\n");
    WriteFile('Child.mk', "child:\n\t\@$command descendant child-partial\n");
    my $soak = 'all: ' . join(' ', map { "job$_" } 1 .. 1000) . "\n";
    $soak .= "job$_:\n\t\@$command pool $_ 8\n" for 1 .. 1000;
    WriteFile('Soak.mk', $soak);
    print "Created Cancel.mk, Child.mk and Soak.mk in " . getcwd() . "\n";
    exit 0;
}

my $windows = $^O eq 'MSWin32';
my $pmake = abs_path(shift @ARGV // die "Usage: perl $0 path-to-pmake\n");
die "Cannot find pmake\n" unless defined $pmake && -f $pmake;
my $script = abs_path($0);
my $original = getcwd();
my $root = tempdir('pmake-parallel-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $case = 0;
my $worker = qq{"$^X" "$script" --worker};
# The active Watcom backends use -u for command preview.

sub NewCase {
    chdir $root or die "chdir: $!\n";
    my $name = 'Case' . ++$case;
    mkdir $name or die "mkdir: $!\n";
    chdir $name or die "chdir: $!\n";
}

sub Run {
    my ($makefile, @options) = @_;
    WriteFile('Test.mk', $makefile);
    my $log = File::Spec->catfile(getcwd(), 'output');
    open my $out, '>', $log or die "$log: $!\n";
    my $input = gensym;
    local $ENV{TEMP} = getcwd() if $windows;
    local $ENV{TMP} = getcwd() if $windows;
    my $pid = open3($input, '>&' . fileno($out), '>&' . fileno($out),
                    $pmake, '-r', '-f', 'Test.mk', @options);
    close $input;
    my $deadline = time + 18;
    my $timedOut = 0;
    while (waitpid($pid, WNOHANG) == 0) {
        if (time >= $deadline) {
            $timedOut = 1;
            kill 9, $pid;
            waitpid($pid, 0);
            last;
        }
        sleep 0.02;
    }
    my $status = $?;
    close $out;
    my $output = ReadFile('output');
    diag($output) if $timedOut;
    is(scalar(() = glob('PMA*')), 0, 'temporary command files were removed') if $windows;
    return ($status, $output, $timedOut);
}

sub Peak {
    my $active = 0;
    my $peak = 0;
    for my $event (split /\n/, ReadFile('events')) {
        $active += $event =~ /^start / ? 1 : -1;
        $peak = $active if $active > $peak;
    }
    is($active, 0, 'all workers completed');
    return $peak;
}

sub Pool {
    my ($limit, @options) = @_;
    NewCase();
    my $count = $limit < 8 ? 8 : $limit;
    my @targets = map { "job$_" } 1 .. $count;
    my $makefile = 'all: ' . join(' ', @targets) . "\n";
    for my $id (1 .. $count) {
        $makefile .= "job$id:\n\t\@$worker pool $id $limit\n";
    }
    my ($status, $output, $timeout) = Run($makefile, @options);
    is($status, 0, 'pool build succeeded') or diag($output);
    ok(!$timeout, 'pool did not time out');
    is(Peak(), $limit, 'effective concurrency');
}

local $ENV{PMAKE} = '';
local $ENV{MAKEFLAGS} = '';
local $ENV{MFLAGS} = '';

subtest 'job limits' => sub {
    Pool(1);
    Pool(1, '-J', 1, '-L', 1);
    Pool(8, '-J', 8, '-L', 8);
    Pool(2, '-J', 8, '-L', 2);
    Pool(2, '-J', 2, '-L', 8);
    Pool(1, '-J', 8);
    Pool(1, '-J', 1, '-L', 8);
};

SKIP: {
    skip 'Windows value validation and wait boundary', 1 unless $windows;
    subtest 'Windows values' => sub {
        for my $option ('-J', '-L') {
            for my $value ('', '0', '-1', '+1', '1x', 'x', '1.0', ' 1', '1 ',
                           '64', '2147483648', '4294967297', '999999999999999999999999') {
                NewCase();
                my ($status, $output) = Run("all:\n", $option, $value);
                isnt($status, 0, "$option rejects '$value'");
                like($output, qr/1.*63/, 'error gives the valid range');
            }
        }
        Pool(63, '-J', 63, '-L', 63);
        Pool(2, '-J', '0002', '-L', '02');
    };
}

subtest 'serial compatibility modes' => sub {
    for my $mode ('-B', '-M') {
        NewCase();
        my ($status, $output) = Run("all:\n\t\@$worker touch first\n" .
            "\t\@$worker require first second\n", $mode);
        is($status, 0, "$mode runs all recipe lines") or diag($output);
        ok(-e 'second', "$mode preserves command order");
    }
};

subtest 'refill and dependencies' => sub {
    NewCase();
    my ($status, $output) = Run("all: slow replacement\nslow:\n\t\@$worker slow\n" .
        "short:\n\t\@$worker short\nreplacement: short\n\t\@$worker replacement\n",
        '-J', 2, '-L', 2);
    is($status, 0, 'short completion admits replacement before slow completion') or diag($output);
    ok(-e 'replacement' && -e 'slow-done', 'both handshakes completed');
};

subtest 'recursive limits' => sub {
    NewCase();
    WriteFile('Child.mk', "all: a b c flags\na:\n\t\@$worker pool a 2 child\n" .
        "b:\n\t\@$worker pool b 2 child\nc:\n\t\@$worker pool c 2 child\nflags:\n\t\@$worker flags\n");
    my ($status, $output) = Run("all: child peer\nchild:\n\t\@\"\$(.PMAKE)\" -r -f Child.mk\n" .
        "peer:\n\t\@$worker peer\n", '-J', 3, '-L', 2);
    is($status, 0, 'recursive build can run its own children') or diag($output);
    like(ReadFile('flags'), qr/-J\s+3/, 'child inherits J');
    like(ReadFile('flags'), qr/-L\s+2/, 'child inherits L');
    is(Peak(), 3, 'parent peer overlaps two recursive workers');
};

subtest 'failures and ignored errors' => sub {
    for my $options ([], ['-k'], ['-i']) {
        NewCase();
        my ($status, $output) = Run("all: dependent independent\n" .
            "bad:\n\t\@$worker fail 7\n\t\@$worker touch after-bad\n" .
            "dependent: bad\n\t\@$worker touch dependent\n" .
            "independent:\n\t\@$worker touch independent\n", @$options, '-J', 2, '-L', 2);
        if (@$options && $options->[0] eq '-i') {
            is($status, 0, '-i succeeds');
            ok(-e 'after-bad' && -e 'dependent', '-i continues commands and dependents');
        } else {
            {
                local $TODO = 'Linux -k status is unchanged' if !$windows && @$options;
                isnt($status, 0, 'failure returns a nonzero status');
            }
            ok(!-e 'after-bad' && !-e 'dependent', 'failed command blocks recipe and dependents');
        }
        ok(-e 'independent', 'independent work completes') if @$options;
    }
    NewCase();
    my ($status, $output) = Run("all:\n\t-\@$worker fail 7\n\techo after-ignore\n" .
                              "\t\@$worker touch after-ignore\n");
    is($status, 0, 'command-level ignore succeeds') or diag($output);
    ok(-e 'after-ignore', 'ignored failure permits later commands');
    NewCase();
    ($status, $output) = Run("all:\n\t\@$worker fail 7\n", '-k');
    {
        local $TODO = 'Linux -k status is unchanged' unless $windows;
        isnt($status, 0, 'a failed root target also fails with -k');
    }
    SKIP: {
        skip 'Windows full-width exit codes', 8 unless $windows;
        for my $code ('259', '-1073741819') {
            for my $command ("exit $code", "$worker fail $code") {
                NewCase();
                ($status, $output) = Run("all:\n\t$command\n\t\@$worker touch unexpected\n");
                isnt($status, 0, "$command fails without a wait loop");
                ok(!-e 'unexpected', 'later command did not run');
            }
        }
    }
};

subtest 'preview and query' => sub {
    NewCase();
    # -u is accepted by both active Watcom backends.
    my $makefile = ".BEGIN:\n\t\@$worker touch begin\nall:\n\t\@$worker touch all\n.END:\n\t\@$worker touch end\n";
    my ($status, $output) = Run($makefile, '-u');
    is($status, 0, 'preview succeeds') or diag($output);
    like($output, qr/--worker touch all/, 'preview prints recipe');
    ok(!-e 'all' && !-e 'begin' && !-e 'end', 'preview runs no commands');
    ($status, $output) = Run($makefile, '-q');
    is($status >> 8, 1, 'query reports an out-of-date target');
    ok(!-e 'begin' && !-e 'end', 'query skips BEGIN and END');
    WriteFile('all', '');
    ($status, $output) = Run($makefile, '-q');
    is($status, 0, 'query reports a current target');
};

subtest 'shell state and quoting' => sub {
    NewCase();
    mkdir 'Quoted path' or die "mkdir: $!\n";
    copy($script, 'Quoted path/Worker.pl') or die "copy: $!\n";
    my $env = $windows ? 'set PMAKE_TEST_VALUE=kept' : 'PMAKE_TEST_VALUE=kept; export PMAKE_TEST_VALUE';
    my ($status, $output) = Run("all:\n\tcd \"Quoted path\"\n\t$env\n" .
        "\t\@$worker env\n\t\@\"$^X\" \"Worker.pl\" --worker args \"two words\"\n" .
        "\t\@$worker output > redirected 2> errors\n");
    is($status, 0, 'directory, environment, quoting and redirection succeed') or diag($output);
    ok(-e 'Quoted path/env-ok' && -e 'Quoted path/args-ok', 'state persists across recipe lines');
    like(ReadFile('Quoted path/redirected'), qr/stdout-marker/, 'stdout redirection');
    like(ReadFile('Quoted path/errors'), qr/stderr-marker/, 'stderr redirection');
    SKIP: {
        skip 'Windows batch calls and NC flags', 7 unless $windows;
        WriteFile('child.bat', "\@echo off\r\nset PMAKE_TEST_VALUE=kept\r\nexit /b 0\r\n");
        ($status, $output) = Run("all:\n\tcall child.bat\n\t\@$worker env\n");
        is($status, 0, 'batch call returns to recipe');
        ok(-e 'env-ok', 'batch environment remains in the target shell');
        for my $flag ('-n', '-N') {
            unlink 'nc-ran';
            ($status, $output) = Run("all:\n\t\@$worker touch nc-ran\n", $flag);
            is($status, 0, "$flag succeeds");
            ok(-e 'nc-ran', "$flag still executes commands");
        }
        ($status, $output) = Run("all:\n\t\@$worker touch upper-preview\n", '-U');
        ok($status == 0 && !-e 'upper-preview', '-U remains preview');
    }
};

SKIP: {
    skip 'Windows unresolved targets', 1 unless $windows;
    subtest 'unresolved targets' => sub {
        for my $target ('all', 'missing') {
            NewCase();
            my ($status, $output) = Run("all: missing\n", '-k', $target);
            isnt($status, 0, 'unresolved graph fails with -k');
        }
        NewCase();
        my ($status, $output) = Run("all: a\na: b\nb: a\n");
        isnt($status, 0, 'a dependency cycle fails');
    };
}

SKIP: {
    skip 'Windows shell selection', 1 unless $windows;
    subtest 'Windows shell selection' => sub {
        NewCase();
        my $shell = $ENV{COMSPEC} // "$ENV{SystemRoot}/System32/cmd.exe";
        mkdir 'Quoted shell' or die "mkdir: $!\n";
        copy($shell, 'Quoted shell/cmd.exe') or die "copy cmd.exe: $!\n";
        my $quotedShell = abs_path('Quoted shell/cmd.exe');
        {
            local $ENV{COMSPEC} = $quotedShell;
            my ($status, $output) = Run("all:\n\t\@$worker touch comspec\n");
            is($status, 0, 'COMSPEC path with spaces works') or diag($output);
            ok(-e 'comspec', 'COMSPEC shell ran the recipe');
        }
        {
            local $ENV{COMSPEC};
            delete $ENV{COMSPEC};
            my ($status, $output) = Run("all:\n\t\@$worker touch fallback\n");
            is($status, 0, 'cmd.exe fallback works') or diag($output);
        }
        {
            local $ENV{COMSPEC} = 'Missing-pmake-test-shell.exe';
            my ($status, $output) = Run("all:\n\t\@$worker touch unexpected\n");
            isnt($status, 0, 'failed shell creation fails the build');
            ($status, $output) = Run(".SHELL: path=\"$quotedShell\"\nall:\n" .
                "\t\@$worker touch custom\n");
            is($status, 0, 'explicit shell path overrides COMSPEC') or diag($output);
            ok(-e 'custom', 'explicit shell ran the recipe');
        }
    };
}

SKIP: {
    skip 'Windows BEGIN/END execution; the Linux END wait is unchanged', 1 unless $windows;
    subtest 'BEGIN and END' => sub {
        NewCase();
        my ($status, $output) = Run(".BEGIN:\n\t\@$worker touch begin\nall:\n" .
            "\t\@$worker require begin all\n.END:\n\t\@$worker require all end\n");
        is($status, 0, 'BEGIN, main target, END succeed in order') or diag($output);
        ok(-e 'end', 'END ran');
        NewCase();
        ($status, $output) = Run(".BEGIN:\n\t\@$worker fail 7\nall:\n" .
            "\t\@$worker touch all\n.END:\n\t\@$worker touch end\n", '-k');
        isnt($status, 0, 'BEGIN failure fails the build');
        ok(!-e 'all' && !-e 'end', 'BEGIN failure blocks main work and END');
    };
}

chdir $original or die "chdir: $!\n";
done_testing();
