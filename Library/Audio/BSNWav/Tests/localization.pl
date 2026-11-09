#!/usr/bin/env perl
# Check audio translation limits and substitutions. Author: Codex/MeyerK
use strict;
use warnings;
use FindBin;

my $root = "$FindBin::Bin/../../../..";
sub read_file {
    open my $in, '<:raw', "$root/$_[0]" or die "$root/$_[0]: $!";
    local $/;
    return <$in>;
}
sub chunks {
    my ($source) = @_;
    my %chunks;
    while ($source =~ /\@chunk\s+char\s+(\w+)\[\]\s*=\s*"((?:\\.|[^"\\])*)";\s*
        (\@localize\s+(?:not|"(?:\\.|[^"\\])*"|\{\s*"(?:\\.|[^"\\])*"\s+\d+-\d+\s*\})\s*;)/gx) {
        $chunks{$1} = [$2, $3];
    }
    return %chunks;
}
sub bound {
    my ($chunk) = @_;
    $chunk->[1] =~ /\s0-(\d+)\s*\}/ or die "Missing translation length limit\n";
    length($chunk->[0]) <= $1 or die "English text exceeds translation limit\n";
    return $1;
}
sub check_format {
    my ($chunk, $expected, $capacity, @values) = @_;
    defined $chunk or die "Missing localized format\n";
    my @formats = $chunk->[0] =~ /%(?:%|\d*l?[duX])/g;
    my $literal = $chunk->[0];
    $literal =~ s/%(?:%|\d*l?[duX])//g;
    index($literal, '%') == -1 or die "Unexpected format substitution\n";
    join(',', @formats) eq $expected or die "Changed format substitutions\n";
    # Simulate a translation at its allowed length, using the largest arguments.
    my $format = $chunk->[0] . ('x' x (bound($chunk) - length($chunk->[0])));
    length(sprintf($format, @values)) < $capacity
        or die "Localized format $expected can exceed its $capacity-byte destination buffer\n";
}

my %mixer = chunks(read_file('Library/Audio/MixLib/Main/mixlib.goc'));
for my $token (0..36) {
    my $chunk = $mixer{"bsmText$token"} or die "Missing mixer token $token\n";
    length($chunk->[0]) < 32 or die "Mixer label exceeds the caller buffer\n";
    if ($token == 0 || ($token >= 29 && $token <= 32)) {
        $chunk->[1] eq '@localize not;'
            or die "Technical mixer token must not be translated\n";
    } else {
        bound($chunk) == 31 or die "Mixer translation must fit 32 bytes\n";
    }
}
my %player = chunks(read_file('Appl/Audio/Bsqp/Main/process.goc'));
for my $entry (['category', 'QuickPlayer'], ['optionsKey', 'options'],
               ['displayKey', 'timeDisplay']) {
    my $chunk = $player{$entry->[0]} or die "Missing INI string\n";
    $chunk->[0] eq $entry->[1] && $chunk->[1] eq '@localize not;'
        or die "INI identities must not be translated\n";
}
check_format($player{BQBitsFormat}, '%u', 80, 65535);
for my $name ('BQMonoText', 'BQStereoText') {
    bound($player{$name}) < 80 or die "Channel label exceeds the display buffer\n";
}
my %sound = chunks(read_file('Appl/Audio/SndChk/UI/uimain.goc'));
for my $name ('TEXT_FOUND_SB_MONO', 'TEXT_FOUND_SB_PRO', 'TEXT_FOUND_SB_16') {
    check_format($sound{$name}, '%X', 80, 65535);
}
bound($sound{TEXT_FOUND_SB_NONE}) < 80 or die "Detection text is too long\n";
check_format($sound{SCProgressFormat}, '%d,%%', 30, 100);
my @filename_args = $sound{completeString}[0] =~ /\\x01/g;
@filename_args == 1 or die "Missing WAV filename substitution\n";
my %converter = chunks(read_file('Appl/MP3Wav/mp3wav.goc'));
check_format($converter{TimingFormat}, '%lu,%02u,%lu,%02u', 48,
             4294967295, 99, 4294967295, 99);
# Prove that the checks reject both a changed argument and an unsafe limit.
for my $bad (['%u%s', '@localize { "bad" 0-76 };'],
             ['%s', '@localize { "bad" 0-76 };'],
             ['%u Bit', '@localize { "bad" 0-79 };']) {
    eval { check_format($bad, '%u', 80, 65535); };
    $@ or die "Invalid translation was accepted\n";
}
print "Audio localization checks passed\n";
