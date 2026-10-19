#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

my $root = "$FindBin::Bin/../../../..";
sub read_file {
    open my $f, '<:raw', $_[0] or die "$_[0]: $!\n";
    local $/;
    return <$f>;
}
my $defs = read_file("$root/Library/Pref/ConfigUI/configui.def");
my @ids = $defs =~ /^(CUIC_\w+)\s+enum ConfigUICombo/gm;
my %id; @id{@ids} = 0 .. $#ids;
my $ui = read_file("$root/Library/Pref/ConfigUI/configuiAppearance.ui");
$ui =~ /UILISUI2000 = GenItem \{(.*?)\}/s or die "missing UI item\n";
$1 =~ /identifier = (\w+);/ or die "missing item identifier\n";
die "ISUI 2000 identifier changed\n" unless $id{$1} == 3;
my $asm = read_file("$root/Library/Pref/ConfigUI/configui.asm");
$asm =~ /uicombos UICombo <(.*?)>\s*CheckHack/s or die "missing combo table\n";
my @combo = split />\s*,\s*</, $1;
my @specific = qw(MotifStr ISUIStr MotifStr ISUI2000Geode);
my @font = qw(BerkeleyStr EsquireStr BerkeleyStr EsquireStr);
die "wrong combo count\n" unless @combo == @ids;
for my $i (0 .. $#combo) {
    my @offset = $combo[$i] =~ /offset (\w+)/g;
    die "wrong UI library/font for index $i\n" unless $offset[0] eq $specific[$i] && $offset[2] eq $font[$i];
}
# Execute the actual UI-change and Apply decisions with native message stubs.
my @schemes = $defs =~ /^(PUIDCS_\w+)\s+enum ConfigUIDefaultColorScheme/gm;
my %symbol = (%id, TRUE => 65535, FALSE => 0, ConfigUICombo => scalar @ids,
    'mask GIGSF_MODIFIED' => 64, 'mask GIGSF_INDETERMINATE' => 128,
    'mask DT_DISP_CLASS' => 240, 'DC_GRAY_1 shl (offset DT_DISP_CLASS)' => 16, 'DC_COLOR_4 shl (offset DT_DISP_CLASS)' => 96);
@symbol{@schemes} = 0 .. $#schemes;
$asm =~ /^UICombo\s+struct\n(.*?)^UICombo ends/ms or die "missing combo layout\n";
my @fields = $1 =~ /^\s*(UIC_\w+)\s+(?:nptr\.TCHAR|FontID|word)\s*$/gm;
$symbol{'size UICombo'} = 2 * @fields;
my @rows;
for my $combo (@combo) {
    $combo =~ s/;[^\n]*//g;
    my @value = map { s/^\s+|\s+$//g; exists $symbol{$_} ? $symbol{$_} : $_ } split /,/, $combo;
    die "wrong combo layout\n" unless @value == @fields;
    my %row; @row{@fields} = @value; push @rows, \%row;
}
sub execute {
    my ($method, $ui, $flags, $display, $uiModified) = @_;
    $asm =~ /^$method\s+method[^\n]*\n(.*?)^$method\s+endm/ms or die "missing $method\n";
    my $body = $1;
    $body =~ s/^redrawSample:.*//ms if $method eq 'PrefUICDialogSPUIChanged';
    $body =~ s/^checkReset2:.*//ms if $method eq 'ConfigUIDialogApply';
    my (@code, %label, %reg, @messages, $selected, $modified, $status, $writes);
    my ($zero, $carry) = (0, 0);
    %reg = (cx => $ui, dx => $flags); $writes = 0;
    my $get; $get = sub {
        my ($name) = @_;
        return $symbol{$name} if exists $symbol{$name};
        return $name if $name =~ /^\d+$/;
        return $reg{$name} // 0 if $name =~ /^(?:[abcd]x|[sd]i|bp)$/;
        return (($reg{$1.'x'} // 0) >> ($2 eq 'h' ? 8 : 0)) & 255 if $name =~ /^([abcd])([hl])$/;
        return $rows[$get->('di') / $symbol{'size UICombo'}]{$1} if $name =~ /^cs:uicombos\[di\]\.(\w+)$/;
        return $name if $name =~ /^(?:MSG_|offset )/;
        die "unknown operand $name\n";
    };
    my $set = sub {
        my ($name, $value) = @_;
        if ($name =~ /^([abcd])([hl])$/) {
            my ($word, $shift) = ($1.'x', $2 eq 'h' ? 8 : 0);
            $reg{$word} = (($reg{$word} // 0) & ~(255 << $shift)) | (($value & 255) << $shift);
        } else { $reg{$name} = $value =~ /^\d+$/ ? $value & 65535 : $value; }
    };
    for (split /\n/, $body) {
        s/;.*//; s/^\s+|\s+$//g; s/\s+/ /g;
        next if /^(?:$|\.|uses\b|MSG_)/;
        if (/^(\w+):$/) { $label{$1} = scalar @code; } else { push @code, $_; }
    }
    @label{qw(redrawSample checkReset2 doReset)} = (scalar @code) x 3;
    for (my $pc = 0; $pc < @code; $pc++) {
        my $line = $code[$pc];
        if ($line =~ /^(mov|test|cmp|and)\s+([^,]+),\s*(.+)$/) {
            my ($op, $a, $b) = ($1, $2, $get->($3));
            if ($op eq 'mov') { $set->($a, $b); }
            elsif ($op eq 'cmp') { $zero = $get->($a) == $b; $carry = $get->($a) < $b; }
            else { my $v = $get->($a) & $b; $zero = !$v; $carry = 0; $set->($a, $v) if $op eq 'and'; }
        } elsif ($line =~ /^mul\s+(\w+)$/) { $reg{ax} = $get->('ax') * $get->($1); $reg{dx} = 0;
        } elsif ($line =~ /^clr\s+(\w+)$/) { $set->($1, 0); $zero = 1; $carry = 0;
        } elsif ($line =~ /^(jz|jnz|jae|ja|jbe|jc|jnc|jmp)\s+(\w+)$/) {
            my ($op, $label) = ($1, $2);
            die "unknown label $label\n" unless exists $label{$label};
            $pc = $label{$label} - 1 if $op eq 'jmp' ||
                ($op eq 'jz' ? $zero : $op eq 'jnz' ? !$zero : $op eq 'jae' ? !$carry :
                 $op eq 'ja' ? !$carry && !$zero : $op eq 'jbe' ? $carry || $zero : $op eq 'jc' ? $carry : !$carry);
        } elsif ($line eq 'call UserGetDisplayType') { $reg{ax} = ($display << 8) | 255;
        } elsif ($line eq 'call SetUIOptions') { $writes++;
        } elsif ($line eq 'call ObjCallInstanceNoLock') {
            my ($message, $target, $cx) = @reg{qw(ax si cx)};
            push @messages, $message;
            if ($target eq 'offset SchemesList') {
                if ($message eq 'MSG_GEN_ITEM_GROUP_SET_SINGLE_SELECTION') {
                    die "hidden or indeterminate scheme\n" unless $cx < ($display > 96 ? @schemes : 3) && !$reg{dx};
                    $selected = $cx; $modified = 0;
                } elsif ($message eq 'MSG_GEN_ITEM_GROUP_SET_MODIFIED_STATE') { $modified = !!$cx;
                } elsif ($message eq 'MSG_GEN_ITEM_GROUP_SEND_STATUS_MSG') { $status = !!$cx;
                } else { die "unexpected scheme message $message\n"; }
            } elsif ($target eq 'offset UIList') {
                if ($message eq 'MSG_GEN_ITEM_GROUP_IS_MODIFIED') { $carry = $uiModified;
                } elsif ($message eq 'MSG_GEN_ITEM_GROUP_GET_SELECTION') { $carry = 0;
                } else { die "unexpected UI mutation $message\n"; }
            } else { die "unexpected target $target\n"; }
            @reg{qw(ax cx dx bp)} = (57005) x 4; # Native calls destroy these.
            $reg{ax} = $ui if $message eq 'MSG_GEN_ITEM_GROUP_GET_SELECTION';
        } else { die "unhandled instruction $line\n"; }
    }
    return ($selected, $modified, $status, $writes, scalar @messages);
}
my @full = @symbol{qw(PUIDCS_DEFAULT PUIDCS_NEWUI PUIDCS_MEADOWS PUIDCS_ISUI2000)};
my @limited = @symbol{qw(PUIDCS_DEFAULT PUIDCS_NEWUI PUIDCS_DEFAULT PUIDCS_NEWUI)};
for my $ui (0 .. 4, 65535) {
    for my $flags (0, 64, 128, 192) {
        for my $display (16, 64, 96, 112, 128) {
            my ($selected, $modified, $status, $writes, $calls) = execute('PrefUICDialogSPUIChanged', $ui, $flags, $display, 1);
            my $change = $ui < @ids && $flags == 64 && $display > 16;
            if ($change) {
                my $want = $display > 96 ? $full[$ui] : $limited[$ui];
                die "wrong combo palette\n" unless defined $selected && $selected == $want;
                die "palette not saved/notified\n" unless $modified && $status && $calls == 3;
            } else { die "custom palette reset on load/redundant selection\n" if defined $selected || $calls; }
            die "UI changed before Apply\n" if $writes;
        }
    }
}
# The theme handler must not change UIList or write the specific UI; Apply
# must only commit UI options when the UI selector itself is modified.
$asm =~ /^PrefUICSetDefaultColor\s+method[^\n]*\n(.*?)^PrefUICSetDefaultColor\s+endm/ms or die "missing theme handler\n";
die "theme handler changes SPUI\n" if $1 =~ /UIList|SetUIOptions|specificKey/;
$asm =~ /^SetUIOptions\s+proc[^\n]*\n(.*?)^SetUIOptions\s+endp/ms or die "missing UI Apply handler\n";
die "Apply resets a later manual theme choice\n" if $1 =~ /SchemesList|MSG_CUID_SET_DEFAULT_COLORS/;
for my $changed (0, 1) {
    my (undef, undef, undef, $writes) = execute('ConfigUIDialogApply', 3, 0, 112, $changed);
    die "theme-only Apply changes SPUI\n" unless $writes == $changed;
}

my $make = read_file("$root/Installed/Makefile");
$make =~ /minimalLibrary\s*:(.*?)(?=\n\w[^\n]*:)/s or die "missing library build list\n";
die "ISUI 2000 omitted from product build\n" unless $1 =~ /\bisui2000\b/;
die "missing ISUI 2000 build target\n" unless $make =~ /^isui2000\s*:\s*Installed\/Library\/SpecUI\/ISUI2000\s*$/m;
my $tree = read_file("$root/Tools/build/product/bbxensem/bbxensem.filetree");
die "ISUI 2000 omitted from product file tree\n" unless $tree =~ m{Library/SpecUI/ISUI2000/isui2000\{ec\}\.geo};
for my $name ('isui2000.geo', 'EC ISUI 2000') {
    die "missing configured library name $name\n" unless index($asm, '"' . $name . '"') >= 0;
}
# Optional product-image check: verify the selected UI can be found by its DOS
# filename or GEOS long name, just as startup's GeodeUseLibrary expects.
if (my $runtime = shift) {
    my @ini = grep { -f $_ } "$runtime/geosec.ini", "$runtime/geos.ini";
    die "missing runtime INI\n" unless @ini;
    my $ini = read_file($ini[0]);
    $ini =~ /^\[ui\]\s*\n(.*?)(?=^\[|\z)/mis or die "missing [ui]\n";
    $1 =~ /^specific\s*=\s*([^\r\n]+)/mi or die "missing specific UI setting\n";
    my $selected = lc $1;
    opendir my $dir, "$runtime/system" or die $!;
    my @files = grep { -f "$runtime/system/$_" } readdir $dir;
    my @found = grep {
        open my $file, '<:raw', "$runtime/system/$_" or die $!;
        read $file, my $header, 40;
        length($header) == 40 && substr($header, 0, 4) eq "\xc7\x45\xc1\x53" && do {
            my $longname = substr($header, 4, 36);
            $longname =~ s/\0.*//s;
            lc($_) eq $selected || lc($longname) eq $selected;
        };
    } @files;
    die "selected UI '$selected' is missing from SYSTEM\n" unless @found;
}
print "Specific UI selection, scheme and packaging checks passed\n";
