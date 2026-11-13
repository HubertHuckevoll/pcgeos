#!/usr/bin/env perl
# Run with: perl Library/Text/Tests/print-height.pl
# Author: Codex/MeyerK
use strict;
use warnings;
use FindBin;

sub Source
{
    open my $file, '<', "$FindBin::Bin/../$_[0]" or die $!;
    local $/;
    return <$file>;
}

my $draw = Source('Text/textMethodDraw.asm');
$draw =~ /^printing:\r?\n(.*?)^common:/ms or die "printing path missing\n";
$draw = "$1\ncommon:\n";
my $restore = Source('TextGraphic/tgGraphic.asm');
$restore =~ /^TG_RecalcAfterPrint\s+proc[^\n]*\n(.*?)^TG_RecalcAfterPrint\s+endp/ms
    or die "print restore missing\n";
$restore = $1;

# ATTENTION: Execute the caller and restore source, with native calls stubbed.
# This checks the saved state and stack in EC and NC, not actual font metrics
# or drawing. The reported Swat failure supplies the real layout evidence.
sub Run
{
    my ($body, $reg, $state, $stack, $ec) = @_;
    my (@code, %label, $equal);
    my $depth = @$stack;
    for (split /\n/, $body) {
        if (/^EC <\s*(.*?)\s*>\s*$/) { next unless $ec; $_ = $1; }
        s/;.*//;
        s/^\s+|\s+$//g;
        next if !length || /^(?:class\b|uses\b|\.enter\b|\.leave\b|ret\b)/;
        if (/^(\w+):$/) { $label{$1} = scalar @code; }
        else { push @code, $_; }
    }
    my ($read, $write);
    $read = sub {
        my ($name) = @_;
        return $state->{$1} if $name =~ /^ds:\[(?:di|bx)\]\.VTI_(\w+)$/;
        return 256 if $name eq 'ds:[si]';
        return 32 if $name eq 'ds:[di].Vis_offset';
        return 8 if $name eq 'mask VTSF_GRAPHICS';
        return 128 if $name eq 'mask VTSF_LARGE';
        return 0 if $name eq 'mask TCBF_MSG_DRAW or mask TCBF_PRINT';
        return ($reg->{"${1}x"} >> ($2 eq 'h' ? 8 : 0)) & 255
            if $name =~ /^([abcd])([hl])$/;
        return $reg->{$name} // 0 if length($name) == 2;
        my $value = 0;
        $value = ($value << (/[hl]$/ ? 8 : 16)) | $read->($_)
            for $name =~ /(..)/g;
        return $value;
    };
    $write = sub {
        my ($name, $value) = @_;
        if ($name =~ /^ds:\[(?:di|bx)\]\.VTI_(\w+)$/) {
            $state->{$1} = $value;
        } elsif ($name =~ /^([abcd])([hl])$/) {
            my ($word, $shift) = ("${1}x", $2 eq 'h' ? 8 : 0);
            $reg->{$word} = (($reg->{$word} // 0) & ~(255 << $shift)) |
                (($value & 255) << $shift);
        } elsif (length($name) == 2) {
            $reg->{$name} = $value & 65535;
        } else {
            for my $word (reverse $name =~ /(..)/g) {
                $write->($word, $value);
                $value >>= $word =~ /[hl]$/ ? 8 : 16;
            }
        }
    };
    for (my $pc = 0; $pc < @code; $pc++) {
        my ($op, $args) = split /\s+/, $code[$pc], 2;
        my ($dest, $src) = split /,\s*/, $args // '';
        if ($op =~ /^mov(?:wbf|_tr)?$/) {
            $write->($dest, $read->($src));
        } elsif ($op eq 'clr' || $op eq 'clrdw') {
            $write->($dest, 0);
        } elsif ($op eq 'add') {
            $write->($dest, $read->($dest) + $read->($src));
        } elsif ($op eq 'test' || $op eq 'cmpwbf') {
            $equal = $op eq 'test' ? !($read->($dest) & $read->($src)) :
                $read->($dest) == $read->($src);
        } elsif ($op =~ /^(?:jz|jnz|jcxz)$/) {
            my $take = $op eq 'jcxz' ? !$read->('cx') :
                $op eq 'jz' ? $equal : !$equal;
            die "unknown label $dest\n" unless exists $label{$dest};
            $pc = $label{$dest} - 1 if $take;
        } elsif ($op eq 'push') {
            push @$stack, [map { $read->($_) } split /,\s*/, $args];
        } elsif ($op eq 'pop') {
            die "printing stack underflow\n" unless @$stack > $depth;
            my $values = pop @$stack;
            $write->($_, shift @$values) for split /,\s*/, $args;
        } elsif ($op eq 'xchg') {
            my $value = $read->($dest);
            $write->($dest, $read->($src));
            $write->($src, $value);
        } elsif ($op eq 'WARNING_NZ') {
            die "unexpected height warning: $dest\n" unless $equal;
        } elsif ($op eq 'call' && $dest eq 'TG_IfVariableGraphicsThenRecalc') {
            if ($state->{variable}) {
                $write->('cx', $state->{lines});
                $state->{lines} = 20;
                $state->{height} = $state->{temporaryHeight};
            }
        } elsif ($op eq 'call' && $dest eq 'TextInitModeAndBorder') {
            # Print setup reuses ax for drawing attributes.
            $reg->{ax} = 0xdead;
        } elsif ($op eq 'call' && $dest eq 'TextDraw') {
            # TextDraw preserves ax, cx, and dx in its uses list.
        } elsif ($op eq 'call' && $dest eq 'TG_RecalcAfterPrint') {
            Run($restore, $reg, $state, $stack, $ec);
        } elsif ($op eq 'call' && $dest eq 'LMemFree') {
            die "wrong temporary line array freed\n" unless $read->('ax') == 20;
            $state->{freed}++;
        } elsif ($op eq 'call' && $dest eq 'TL_LineGetCount') {
            die "wrong restored line array\n" unless $state->{lines} == 10;
            $write->('dxax', scalar @{$state->{lineHeights}});
        } elsif ($op eq 'call' && $dest eq 'TL_LineSumAndMarkRange') {
            die "diagnostic changed line flags\n" if $read->('cx');
            my $sum = 0;
            $sum += $_ for @{$state->{lineHeights}};
            $write->('cxdxax', $sum << 8);
        } elsif ($op eq 'call' && $dest eq 'T_AssertIsVisText') {
            # These fixtures are valid text objects.
        } else {
            die "unhandled instruction: $code[$pc]\n";
        }
    }
    die "unbalanced printing stack\n" unless @$stack == $depth;
}

my $checks = 0;
for my $ec (0, 1) {
    for my $heights ([72 * 256, 71 * 256 + 178], # Reported header/footer failure
                     [72 * 256 + 64, 74 * 256 + 255], # Preserve original fraction
                     [20 * 256, 20 * 256]) {    # No temporary height change
        for my $options ([8, 1], [8, 0], [0, 1], [136, 1]) {
            my %state = (height => $heights->[0], temporaryHeight => $heights->[1],
                         lines => 10, storageFlags => $options->[0],
                         variable => $options->[1], freed => 0,
                         lineHeights => [$heights->[0]]);
            for (1 .. 3) {
                my %reg = (ax => 0x1234, bx => 288, dx => 0x5678);
                my @stack = ([0xaaaa], [0xbbbb], [0xcccc]); # Saved draw state
                Run($draw, \%reg, \%state, \@stack, $ec);
                die "restored height differs from original lines (EC=$ec)\n"
                    unless $state{lines} == 10 && $state{height} == $heights->[0];
                die "printing damaged saved draw state\n"
                    unless join(',', map { @$_ } @stack) eq '43690,48059,52428';
                $checks++;
            }
            die "temporary line array lifetime is wrong\n"
                unless $state{freed} == (($options->[0] == 8 && $options->[1]) ? 3 : 0);
        }
    }
}
print "$checks print height checks passed\n";
