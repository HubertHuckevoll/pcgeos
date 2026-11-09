#!/usr/bin/env perl
# Check language entries with the real template processor. Author: Codex/MeyerK
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

our %var;
sub FindInstalledFile { return $_[0]; }
sub Debug { return 0; }
sub DebugPrint {}
sub printbold {}
sub Unix2Dos {}
sub Error { die $_[0]; }

require "$FindBin::Bin/../build/template.pl";
my $source = shift || "$FindBin::Bin/../product/bbxensem/Template/geos.ini";
open my $in, '<:raw', $source or die "$source: $!";
my $template = do { local $/; <$in> };
$template =~ /(\[text\]\r?\n.*?)(?=\r?\n\[)/s
    or die "Missing text category\n";
my $text = $1;
my $dir = tempdir(CLEANUP => 1);
open my $out, '>:raw', "$dir/geos.ini" or die $!;
print {$out} $text;
close $out or die $!;
mkdir "$dir/Output" or die $!;

for my $ec (0, 1) {
    for my $language ('english', 'german') {
        %var = (ec => $ec, language => $language);
        {
            open my $quiet, '>', '/dev/null' or die $!;
            local *STDOUT = $quiet;
            ParseTemplateFileAndSend("$dir/geos.ini", "$dir/Output/");
        }
        open my $result, '<:raw', "$dir/Output/geos.ini" or die $!;
        my $ini = do { local $/; <$result> };
        my ($name, $id, $dialect, $dictionary) = $language eq 'english'
            ? ('English (American)', 16, 128, 'EN_US.DCT')
            : ('Deutsch (Deutschland)', 6, 0, 'DE_DE.DCT');
        for my $entry ("languageName = $name", "language = $id",
                       "dialect = $dialect", "dictionary = $dictionary") {
            my @matches = $ini =~ /^\Q$entry\E\r?$/mg;
            @matches == 1 or die "$language EC=$ec: missing or duplicate $entry\n";
        }
        for my $line (split /\r?\n/, $ini) {
            $line =~ /^\s*(?:\[text\]|\w+\s*=.*)?$/
                or die "$language EC=$ec: invalid INI line: $line\n";
        }
    }
}
print "INI language template checks passed\n";
