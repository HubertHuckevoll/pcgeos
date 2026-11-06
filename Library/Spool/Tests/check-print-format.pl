#!/usr/bin/env perl
# Check the printer escape ABI across the ESP and C interfaces.
use strict;
use warnings;
use FindBin;
use File::Spec;
my $root = File::Spec->rel2abs("$FindBin::Bin/../../..");
sub read_file {
    open my $fh, '<', "$root/$_[0]" or die "$root/$_[0]: $!";
    local $/;
    return <$fh>;
}
my $esp = read_file('Include/Internal/printDr.def');
my $c = read_file('CInclude/Internal/printDr.h');
$c =~ s{/\*.*?\*/}{}gs;
$c =~ /typedef enum\s*\{([^{}]*)\}\s*PrintEscCode;/s
    or die "C printer escape enum missing\n";
my $enum = $1;
my %c;
my $value = 0;
for my $entry (split /,/, $enum) {
    next unless $entry =~ /\b(DR_PRINT_ESC_\w+)(?:\s*=\s*(0x[0-9a-f]+|\d+))?/i;
    my ($name, $explicit) = ($1, $2);
    $value = $explicit =~ /^0x/ ? hex($explicit) : 0 + $explicit if defined $explicit;
    $c{$name} = $value++;
}
$esp =~ /PrintEscCode\s+etype word,\s*([0-9a-f]+)h,\s*(\d+)/i
    or die "ESP printer escape enum missing\n";
$value = hex($1);
my $step = $2;
while ($esp =~ /^(DR_PRINT_ESC_\w+)\s+enum\s+PrintEscCode\b/mg) {
    my $name = $1;
    defined($c{$name}) && $c{$name} == $value
        or die "Printer escape ABI mismatch: $name\n";
    delete $c{$name};
    $value += $step;
}
die "Extra C printer escapes: " . join(', ', sort keys %c) . "\n" if %c;
print "Printer escape ABI matches in ESP and C, including the optional output format query.\n";
