package SwatTestRunner;

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use Fcntl qw(LOCK_EX LOCK_NB);
use File::Basename qw(dirname);
use File::Temp ();
use Getopt::Long qw(GetOptionsFromArray);
use IO::Socket::INET;
use IPC::Open3 qw(open3);
use POSIX qw(WNOHANG _exit);
use Time::HiRes qw(time sleep);

my $windows = $^O eq 'MSWin32';
my $monotonic = eval { Time::HiRes::CLOCK_MONOTONIC() };

# Run embedded Swat Tcl against a configured SDK test target.
# The last Tcl command must return 1 (pass) or 0 (fail).
# Tcl errors and missing results are errors. The transcript goes to stdout.
sub run {
    my ($tcl, @args) = @_;
    my ($normal, $no_window, $help, $timeout) = (0, 0, 0, 60);
    my $valid = GetOptionsFromArray(\@args, 'n' => \$normal,
        'no-window' => \$no_window, 'timeout=i' => \$timeout, 'help' => \$help);
    if (!$valid || @args || $timeout < 1 || $help) {
        print "Usage: perl $0 [-n] [--no-window] [--timeout SECONDS]\n";
        return $valid && !@args && $timeout > 0 ? 0 : 2;
    }

    my $result = eval { run_target($tcl, $normal, $no_window, $timeout) };
    if ($@) {
        print STDERR $@;
        $result = 'ERROR';
    }
    print "\nSwat test: $result\n";
    my %status = (PASS => 0, FAIL => 1, ERROR => 2, TIMEOUT => 124);
    return $status{$result};
}

sub find_command {
    my ($name) = @_;
    for my $dir (split /:/, $ENV{PATH}) {
        my $path = "$dir/$name";
        return $path if -f $path && -x _;
    }
    return;
}

sub watch_transcript {
    my ($dir, $path, $pid) = @_;
    if ($windows) {
        return unless eval { require Win32::Process; 1 };
        my $script = "$dir/watch.pl";
        write_file($script, <<'PERL');
use strict;
use warnings;
use Time::HiRes qw(sleep);
$| = 1;
binmode STDOUT;
my ($path) = @ARGV;
open my $log, '<:raw', $path or exit 1;
my $chunk;
while (1) {
    sysseek($log, 0, 1);
    print $chunk while sysread($log, $chunk, 65536);
    last if -e "$path.done";
    sleep 0.1;
}
PERL
        my $viewer;
        Win32::Process::Create($viewer, $^X, qq{"$^X" "$script" "$path"},
            0, Win32::Process::CREATE_NEW_CONSOLE(), $dir);
        return $viewer;
    }
    return unless $ENV{DISPLAY} || $ENV{WAYLAND_DISPLAY};
    my $tail = find_command('tail') or return;
    my @terminal;
    if (my $ptyxis = find_command('ptyxis')) {
        @terminal = ($ptyxis, '--new-window', '--title', 'Swat test', '--');
    } elsif (my $terminal = find_command('x-terminal-emulator') || find_command('xterm')) {
        @terminal = ($terminal, '-T', 'Swat test', '-e');
    } else {
        return;
    }
    my $viewer = fork();
    if (defined $viewer && !$viewer) {
        open STDIN, '<', '/dev/null' or _exit(1);
        open STDOUT, '>', '/dev/null' or _exit(1);
        open STDERR, '>&', \*STDOUT or _exit(1);
        exec @terminal, $tail, '--pid=' . $pid, '-n', '+1', '-f', '--', $path or _exit(1);
    }
    return $viewer;
}

# Open3 starts an executable on Linux and Windows and returns a child PID.
sub launch {
    my ($dir, $output, @command) = @_;
    my $previous = getcwd();
    chdir $dir or die "Cannot enter $dir: $!\n";
    # Keep input open and empty so a Swat prompt cannot loop on EOF.
    my $input;
    my $pid = eval { open3($input, '>&' . fileno($output), undef, @command) };
    my $error = $@;
    chdir $previous or die "Cannot return to $previous: $!\n";
    die $error if $error;
    return ($pid, $input);
}

sub stop_process {
    my ($pid) = @_;
    return unless $pid && waitpid($pid, WNOHANG) == 0;
    if (!$windows) {
        kill 'TERM', $pid;
        for (1..3) {
            sleep 0.1;
            return if waitpid($pid, WNOHANG) != 0;
        }
    }
    kill 'KILL', $pid;
    waitpid($pid, 0);
}

sub target_port {
    my ($path) = @_;
    open my $file, '<', $path or return;
    while (<$file>) {
        return $1 if /127\.0\.0\.1 from port (\d+)\s*\n/;
    }
    return;
}

sub show_output {
    my ($log) = @_;
    # Clear EOF before reading more bytes from a growing file on Windows.
    sysseek($log, 0, 1) if $windows;
    my $size = sysread($log, my $chunk, 65536) or return;
    $chunk =~ tr/\r//d if $windows;
    print $chunk;
    return $size;
}

sub now {
    return defined $monotonic ? Time::HiRes::clock_gettime($monotonic) : time();
}

sub run_target {
    my ($tcl, $normal, $no_window, $timeout) = @_;
    my $root = abs_path(dirname(__FILE__) . '/../..');
    my $local = abs_path($ENV{LOCAL_ROOT} || $ENV{HOME} || $ENV{USERPROFILE} || '.');
    my $type = $normal ? 'nec' : 'ec';
    my $target = $ENV{TARGET} || 'nt';
    my $profile = "$local/.bbxxip/.bbxxip.$target.$type";
    open my $config, '<', $profile or die "Cannot open target profile $profile: $!\n";
    my ($destination) = map { /^destdir=(.*?)[\r\n]*\z/ } <$config>;
    close $config;
    die "The target profile has no destdir.\n" unless defined $destination && length $destination;
    my $target_dir = "$destination/localpc";
    die "The target at $target_dir is not built.\n" unless
        -f "$target_dir/ENSEMBLE/ENSEMBLE.BAT" || -f "$target_dir/ENSEMBLE/SETUP.BAT";
    my $swat = "$root/bin/" . ($windows ? 'swat.exe' : 'swat');
    die "Cannot find $swat. Build the SDK debugger.\n" unless -f $swat;
    open my $lock, '>>', "$local/.bbxxip/swat-test.lock" or die "Cannot open the target lock: $!\n";
    flock $lock, LOCK_EX | LOCK_NB or die "Another test is using this target.\n";
    # bin/basebox.conf uses this port. An interactive target can hold it.
    my $port = IO::Socket::INET->new(LocalPort => 8079, Proto => 'udp')
        or die "Cannot use UDP port 8079: $!\n";
    close $port;
    my $ipx_status = "$target_dir/IPX_STAT.TXT";
    if (-e $ipx_status) {
        unlink $ipx_status or die "Cannot remove $ipx_status: $!\n";
    }

    my $temp = File::Temp->newdir('SwatTest.XXXXXX', DIR => "$local/.bbxxip");
    my $dir = abs_path("$temp");
    write_file("$dir/test.tcl", $tcl);
    # Swat's quit command exits with zero. Write the test result separately.
    write_file("$dir/swat.rc", <<'TCL');
if {[catch {
    ensure-swat-attached
    var passed [source ${file-init-dir}/test.tcl]
    ensure-swat-attached
    if {[string c $passed 1] == 0} {
        var result PASS
    } elif {[string c $passed 0] == 0} {
        var result FAIL
    } else {
        error {The test must return 1 or 0.}
    }
} why]} {
    echo [format {Test error: %s} $why]
    var result ERROR
}
flush-output
var out [stream open ${file-init-dir}/result w]
if {[null $out]} {error {Cannot open the test result file.}}
stream write $result $out
stream close $out
quit leave
TCL
    my $path = "$dir/transcript";
    open my $output, '>:raw', $path or die "Cannot write $path: $!\n";
    open my $log, '<:raw', $path or die "Cannot read $path: $!\n";
    open my $basebox_output, '>:raw', "$dir/basebox.log" or die "Cannot open the emulator log: $!\n";
    my $interrupted;
    local $SIG{INT} = local $SIG{TERM} = sub { $interrupted = 1 };
    local $SIG{PIPE} = 'IGNORE';
    my $basebox = $ENV{BASEBOX} || 'dosbox';
    my @options = ('-conf', "$root/bin/basebox.conf");
    push @options, '-conf', "$local/basebox_user.conf" if -f "$local/basebox_user.conf";
    push @options, '-noconsole' if $windows;
    my ($emulator, $emulator_input, $debugger, $debugger_input, $viewer, $swat_status);
    my $deadline = now() + $timeout;
    local $| = 1;
    eval {
        ($emulator, $emulator_input) = launch($target_dir, $basebox_output, $basebox, @options);
        $viewer = watch_transcript($dir, $path, $emulator) unless $no_window;
        while (!$interrupted && now() < $deadline) {
            show_output($log);
            if ($debugger) {
                if (waitpid($debugger, WNOHANG) != 0) {
                    $swat_status = $?;
                    $debugger = undef;
                    last;
                }
            } elsif (my $ipx_port = target_port($ipx_status)) {
                local $ENV{ROOT_DIR} = $root;
                local $ENV{LOCAL_ROOT} = $local;
                local $ENV{HOME} = $dir;
                local $ENV{TERM} = 'dumb';
                local $ENV{SWAT_BATCH} = 1;
                local $ENV{CUSTOM_TCL_LOCATION} = "$dir/swat.rc";
                my $address = sprintf '00000000:7F000001%04X:003F', $ipx_port;
                ($debugger, $debugger_input) = launch($dir, $output, $swat,
                    '-c', "$root/bin/swat.conf", '-net', $address);
            }
            if (waitpid($emulator, WNOHANG) != 0) {
                my $status = $?;
                $emulator = undef;
                die "The emulator exited during the test (wait status $status).\n";
            }
            sleep 0.1;
        }
    };
    my $error = $@;
    stop_process($debugger);
    stop_process($emulator);
    1 while show_output($log);
    if ($viewer && $windows) {
        write_file("$path.done", '');
        if (!$viewer->Wait(1000)) {
            $viewer->Kill(0);
            $viewer->Wait(1000);
        }
    } elsif ($viewer) {
        waitpid($viewer, WNOHANG);
    }
    if (!$interrupted && !defined $swat_status && open my $basebox_log, '<:raw', "$dir/basebox.log") {
        1 while show_output($basebox_log);
    }
    close $log;
    close $output;
    close $basebox_output;
    die "Test interrupted.\n" if $interrupted;
    die $error if $error;
    return 'TIMEOUT' unless defined $swat_status;
    die "Swat exited with wait status $swat_status.\n" if $swat_status;
    open my $result_file, '<', "$dir/result" or die "Swat did not report a test result.\n";
    my $result = do { local $/; <$result_file> };
    die "Swat reported an invalid test result.\n" unless defined $result && $result =~ /\A(?:PASS|FAIL|ERROR)\z/;
    return $result;
}

sub write_file {
    my ($path, $text) = @_;
    open my $file, '>', $path or die "Cannot write $path: $!\n";
    print {$file} $text or die "Cannot write $path: $!\n";
    close $file or die "Cannot close $path: $!\n";
}

1;
