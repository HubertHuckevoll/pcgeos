#!/usr/bin/env perl
# Link real OMF locals sharing public segments, checking relocated targets.
use strict;
use warnings;
use Cwd qw(abs_path);
use FindBin;
use File::Temp qw(tempdir);

my $glue = abs_path($ARGV[0] || "$FindBin::Bin/../../../bin/glue") or die "No Glue\n";
my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;
sub write_file {
    my ($name, $data) = @_;
    open my $file, '>:raw', $name or die $!;
    print $file $data;
    close $file or die $!;
}
sub counted { return pack('C', length($_[0])) . $_[0]; }
sub record {
    my ($type, $data) = @_;
    my $bytes = pack('Cv', $type, length($data) + 1) . $data;
    my $sum = 0;
    $sum += $_ for unpack('C*', $bytes);
    return $bytes . pack('C', -$sum & 255);
}
sub definition {
    my ($type, $seg, $name, $offset) = @_;
    return record($type, pack('C2', 0, $seg) . counted($name) . pack('vC', $offset, 0));
}
sub object {
    my ($suffix, $tag, $scope, $reference) = @_;
    my $data = record(0x80, counted($suffix));
    $data .= record(0x96, join('', map { counted($_) } qw(_DATA DATA SHARED_TEXT CODE DGROUP)));
    $data .= record(0x98, pack('CvCCC', 0x48, 2, 1, 2, 0));
    $data .= record(0x98, pack('CvCCC', 0x48, 16, 3, 4, 0));
    $data .= record(0x9a, pack('C3', 5, 255, 1));
    $data .= definition(0x90, 2, "Caller$suffix", 4);
    $data .= definition($scope ? 0xb6 : 0x90, 2, 'Helper', 0) if $scope != 2;
    $data .= definition(0xb6, 1, 'LocalData', 0);
    # Local externals refer to this object's locals, with global fallback.
    $data .= record($reference ? 0xb4 : 0x8c, counted('Helper') . "\0");
    $data .= record(0xb4, counted('LocalData') . "\0");
    $data .= record(0xa0, pack('Cv', 1, 0) . pack('v', $tag));
    my $code = pack('CvC', 0xb8, $tag, 0xc3) . "\xe8\0\0\xc3\xb8\0\0\xc3" . "\x90" x 4;
    $data .= record(0xa0, pack('Cv', 2, 0) . $code);
    # PC-relative word at 5 targets Helper; segment-relative word at 9 targets LocalData.
    $data .= record(0x9c, pack('C8', 0x84, 5, 0x56, 1, 0xc4, 9, 0x56, 2));
    return $data . record(0x8a, "\0");
}
sub link_objects {
    my ($name, $success, @objects) = @_;
    write_file("$name.gp", "name $name.lib\ntype library, single\ntokenchars \"TST0\"\ntokenid 0\n" .
        ($name eq 'cviews' ? "export _CallerA\nexport _CallerB\n" : ''));
    open my $log, '>', "$name.log" or die $!;
    open my $stdout, '>&', \*STDOUT or die $!;
    open my $stderr, '>&', \*STDERR or die $!;
    open STDOUT, '>&', $log or die $!;
    open STDERR, '>&', $log or die $!;
    my $result = system($glue, '-G', '2', '-Og', "$name.gp", '-o', "$name.geo", @objects);
    open STDOUT, '>&', $stdout or die $!;
    open STDERR, '>&', $stderr or die $!;
    if ($result == -1 || ($result & 127) || ($result == 0) != $success) {
        open my $file, '<', "$name.log" or die $!;
        print STDERR <$file>;
        die "$name: unexpected Glue status $result\n";
    }
    return unless $success;
    open my $file, '<:raw', "$name.geo" or die $!;
    local $/;
    my $data = <$file>;
    return $data if $name eq 'cviews';
    my ($resources, $libraries, $exports) = unpack('v3', substr($data, 264, 6));
    $resources == 3 && !$libraries && !$exports or die "$name: unexpected resources\n";
    my $table = 344;
    my $code_offset = 256 + unpack('V', substr($data, $table + 2 * $resources + 8, 4));
    return substr($data, $code_offset, 32);
}

for my $scopes ([1, 1], [1, 0], [0, 1]) {
    write_file('a.obj', object('A', 0x1111, $scopes->[0], 1));
    # Similar filenames must still denote separate local scopes.
    write_file('a.obj.extra', object('B', 0x2222, $scopes->[1], 1));
    for my $reverse (0, 1) {
        my @objects = $reverse ? ('a.obj.extra', 'a.obj') : ('a.obj', 'a.obj.extra');
        my $code = link_objects('locals', 1, @objects);
        for my $i (0, 1) {
            my $tag = $objects[$i] eq 'a.obj' ? 0x1111 : 0x2222;
            my $expected = pack('CvC', 0xb8, $tag, 0xc3) .
                "\xe8\xf9\xff\xc3\xb8" . pack('v', 2 * $i) . "\xc3" . "\x90" x 4;
            substr($code, 16 * $i, 16) eq $expected
                or die "locals: call or data reference bound to the wrong object\n";
        }
    }
}
# A local external with no definition must not bind to another object's local.
write_file('a.obj', object('A', 0x1111, 1, 1));
write_file('b.obj', object('B', 0x2222, 2, 1));
link_objects('missing', 0, 'a.obj', 'b.obj');
# A global external must likewise reject a file-local definition.
write_file('b.obj', object('B', 0x2222, 2, 0));
link_objects('global', 0, 'a.obj', 'b.obj');
# A local external without a local definition can bind to a real global.
write_file('a.obj', object('A', 0x1111, 0, 1));
write_file('b.obj', object('B', 0x2222, 2, 1));
my $code = link_objects('fallback', 1, 'a.obj', 'b.obj');
unpack('s<', substr($code, 21, 2)) == -23 or die "Global fallback target changed\n";
# Exercise Watcom's CodeView static procedures as well as raw LPUBDEF records.
for my $suffix ('A', 'B') {
    my $tag = $suffix eq 'A' ? 0x1111 : 0x2222;
    write_file("cv$suffix.c", "static int _near Helper(void) { return $tag; }\n" .
        "int _near Caller$suffix(void) { return Helper(); }\n");
    system('wcc', '-zq', '-bt=dos', '-ecc', '-ml', '-d2', '-hc', '-od', '-s', '-zl',
        '-nt=SHARED_TEXT', "-fo=cv$suffix.obj", "cv$suffix.c") == 0
        or die "Cannot compile the CodeView fixture\n";
}
for my $reverse (0, 1) {
    my @objects = $reverse ? ('cvB.obj', 'cvA.obj') : ('cvA.obj', 'cvB.obj');
    my $data = link_objects('cviews', 1, @objects);
    my ($resources, $libraries, $exports) = unpack('v3', substr($data, 264, 6));
    !$libraries && $exports == 2 or die "cviews: unexpected exports\n";
    for my $i (0, 1) {
        my ($offset, $resource) = unpack('v2', substr($data, 344 + 4 * $i, 4));
        my $table = 344 + 4 * $exports;
        my $start = 256 + unpack('V', substr($data, $table + 2 * $resources + 4 * $resource, 4));
        my $code = substr($data, $start, unpack('v', substr($data, $table + 2 * $resource, 2)));
        my $call = index($code, "\xe8", $offset);
        $call >= $offset && $call < $offset + 16 or die "cviews: missing near call\n";
        my $target = $call + 3 + unpack('s<', substr($code, $call + 1, 2));
        my $tag = $i == 0 ? 0x1111 : 0x2222;
        index(substr($code, $target, 16), pack('v', $tag)) >= 0
            or die "cviews: static call bound to the wrong object\n";
    }
}
print "Glue local symbols: both orders, duplicate names, data and global fallback passed\n";
