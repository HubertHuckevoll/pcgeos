#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

# Execute the actual ESP state and paint decisions. Native graphics and message
# calls are stubs with their register contracts; PC/GEOS is not run here.
sub source {
    open my $f, '<', "$FindBin::Bin/../$_[0]" or die $!;
    local $/;
    my $text = <$f>;
    $text =~ s/\r//g;
    return $text;
}
my $asm = source('CButton/copenButtonCommon.asm') .
          source('CButton/copenButtonColor.asm') . source('CWin/cwinPtr.asm') .
          source('CComp/copenMenuItemGroup.asm') . source('../ISUI/Win/winDraw.asm') .
          source('CItem/citemItemColor.asm') . source('CComp/copenCtrlCommon.asm') .
          source('CButton/copenButtonClass.asm') . source('CGadget/copenTextBuild.asm') .
          source('CGadget/copenGlyphDisplay.asm') . source('../../User/Vis/visSpecUtils.asm') . source('../../User/UI/uiExpress.asm') .
          source('CItem/citemItemCommon.asm') . source('../ISUI/View/viewScrollbarDraw.asm');
my $spin = source('CGadget/copenSpinGadget.asm');
$spin =~ /if _ISUI2000\n(\t;\n\t; Match single-line text.*?)(?=^endif)/ms
    or die "missing spin field geometry\n";
$asm .= "\nSpinFieldHeight proc near\n$1\nret\nSpinFieldHeight endp\n";
my $displayGroup = source('CWin/cwinDisplayControl.asm');
$displayGroup =~ /^else\n\nOLDisplayGroupDraw[^\n]*\n(.*?)^OLDisplayGroupDraw\s+endp/ms
    or die "display-group paint path missing\n";
my $groupDraw = $1;

$groupDraw =~ s/GOTO\s+GrFillRect/call GrFillRect\nret/;
$asm .= "\nDisplayGroupFrame proc near\n$groupDraw\nDisplayGroupFrame endp\n";
my $mainCode = source('CMain/cmainCode.asm');
$mainCode =~ /(\tmov\tal, ds:\[moCS_dsDarkColor\]\n.*?)(?=\t\.leave)/s
    or die "missing display-scheme packing\n";
$asm .= "\nPackDisplayScheme proc near\n$1\nret\nPackDisplayScheme endp\n";
my $titleCode = source('../ISUI/Win/winDraw.asm');
$titleCode =~ /^DrawGradientTitle\s+proc.*?(\tmov\tal, ds:\[moCS_activeTitleBar\].*?\tcall\tDrawGradient)/ms
    or die "missing title gradient endpoints\n";
$asm .= "\nTitleGradientEndpoints proc near\n$1\nret\nTitleGradientEndpoints endp\n";
my %constant = (TRUE => -1, C_BLACK => 0, C_LIGHT_GRAY => 7, C_DARK_GRAY => 8, C_GRAY_27 => 20, DC_GRAY_1 => 1, C_WHITE => 15, SDM_100 => 0, SDM_50 => 6,
    'mask VA_FULLY_ENABLED' => 0x80, 'mask MF_CALL' => 1,
    'mask MF_FIXUP_DS' => 2, 'mask VOF_IMAGE_INVALID' => 4,
    VUM_DELAYED_VIA_UI_QUEUE => 1, MSG_OL_BUTTON_SET_TOOLBOX_HOVER => 123,
    MSG_OL_WIN_SET_TOOLBOX_HOVER => 124, MSG_VIS_VUP_FIND_OBJECT_OF_CLASS => 125,
    'segment OLWinClass' => 20, 'offset OLWinClass' => 30,
    'segment TaskBarListClass' => 21, 'offset TaskBarListClass' => 31);
my $shared = source('cConstant.def');
$shared =~ /^ISUI2000_FIELD_Y_INSET\s*=\s*(\d+)/m or die "missing field inset\n";
my $fieldInset = $1;
# Read the palette indices from the native definitions.
open my $colors, '<', "$FindBin::Bin/../../../../Include/color.def" or die $!;
my $index = 0;
while (<$colors>) {
    if (/^(C_\w+)\s+enum Color(?:,\s*(0x[0-9a-f]+))?/i) {
        $index = hex($2) if defined $2;
        $constant{$1} = $index++;
    }
}
$constant{C_LIGHT_GREY} = $constant{C_LIGHT_GRAY};
$constant{C_DARK_GREY} = $constant{C_DARK_GRAY};
$constant{MAX_CF_INDEX} = $constant{C_WHITE};
@constant{qw(FRAME_TEXT_MARGIN CGA_FRAME_TEXT_MARGIN PEN_FRAME_TEXT_MARGIN ISUI2000_FIELD_Y_INSET)} = (2, 1, 10, $fieldInset);
@constant{'SpecWidth <SST_AVG_CHAR_WIDTHS, 25>', 'SpecHeight <SST_LINES_OF_TEXT, 7>'} = (1, 2);
@constant{qw(ATTR_OL_BUTTON_IN_TITLE_BAR HINT_FIXED_SIZE HINT_MAXIMUM_SIZE HINT_TEXT_DO_NOT_MAKE_LARGER_ON_PEN_SYSTEMS HINT_NO_BORDERS_ON_MONIKERS HINT_EXPRESS_MENU)} = (1001, 1002, 1003, 1004, 1005, 1006);
@constant{'mask VMT_GSTRING', 'mask VMT_MONIKER_LIST', 'mask VTF_IS_GEN', 'mask GTA_SINGLE_LINE_TEXT',
    'mask SSS_DATA', 'mask TDSS_IN_FRAME', 'mask OLSGA_SLIDER', 'mask OLSGS_DRAW_FRAME', 'J_CENTER shl offset DMF_X_JUST'} = (64, 128, 128, 1, 1023, 1, 1, 1, 1);
for my $record (qw(OLButtonSpecState OLButtonMoreAttrs OLButtonFixedAttrs OLWinFixedAttr OLDisplayGroupStates OLItemState)) {
    my $file = $record eq 'OLDisplayGroupStates' ? 'olDisplayGroupClass.def' :
               $record eq 'OLItemState' ? 'olItemClass.def' :
               $record eq 'OLWinFixedAttr' ? 'olWinClass.def' : 'olButtonClass.def';
    open my $f, '<', "$FindBin::Bin/../../../../Include/Internal/SpecUI/$file" or die $!;
    local $/;
    my $def = <$f>;
    $def =~ /\b$record\s+record(.*?)\b$record\s+end/s or die $record;
    my @bits = $1 =~ /^\s*(\w*):(\d+)/gm;
    my $shift = 0;
    $shift += $bits[$_] for grep { $_ % 2 } 0 .. $#bits;
    for (my $i = 0; $i < @bits; $i += 2) {
        $shift -= $bits[$i + 1];
        $constant{"mask $bits[$i]"} = ((1 << $bits[$i + 1]) - 1) << $shift if $bits[$i] ne '';
    }
}
for my $flag (qw(EXPAND_WIDTH_TO_FIT_PARENT EXPAND_HEIGHT_TO_FIT_PARENT CAN_CLIP_MONIKER_WIDTH CAN_CLIP_MONIKER_HEIGHT IN_TOOLBOX)) {
    $constant{"mask OLGDF_$flag"} = $constant{"mask OLBMA_$flag"};
}
my ($cga, $hasTitle, $penLarge, $penNoLarge, $fixedHeight, $maxHeight, $noBorders, $express, $fontWidth, $fontHeight, $gstates) = (0, 0, 0, 0, undef, undef, 0, 0, 6, 13, 0);
my $isui2000 = 1;
my $isui = 1;
my ($textColors, $textColor, $backgroundColors, $copyHintFixture, $hintCopied, $backgroundSelected, $bounds, $surface, $paintClip);
my $mixMode = 1;
my @savedGraphics;
my $raster = source('../../../Driver/Video/Dumb/VidMem/Clr8/clr8Output.asm');
$raster =~ /NOTtable\s+label\s+byte\n(.*)/s or die "missing native colour inversion table\n";
my @not = map { hex($_) } $1 =~ /0x([0-9a-f]{2})/gi;
@not = @not[0 .. 255];
my ($loadedUI, @searched);
@constant{qw(dgroup cs), 'mask GA_LIBRARY', 'mask GA_PROCESS or mask GA_DRIVER or mask GA_APPLICATION'} = (1, 2, 1, 14);
for my $name (qw(isuiName isui2000Name)) {
    $asm =~ /^$name\s+char\s+"([^"]+)"/m or die "missing $name\n";
    $constant{"offset $name"} = $name eq 'isuiName' ? 2001 : 2002;
    $constant{$constant{"offset $name"}} = $1;
}
my (%reg, %mem, @gradient, @frame, @rect, @line, @fill, @invalid, $zero, $carry, $signedLess, $negative, $mask, @pen, $bw, $lineColor, $bordered, $areaColor, $faceColor, $parentIsTaskbar, $hasParent, $parentLocked);
my @bitmap;
@constant{qw(MM_COPY MM_INVERT MM_XOR)} = (1, 4, 5);
$constant{'size BackgroundColors'} = 4;
$constant{HINT_GADGET_TEXT_COLOR} = 1007;
$constant{HINT_GADGET_BACKGROUND_COLORS} = 1008;
my (@solidFrame, @bitmapPos, @sbFill, @sbPart, @paintFill);
@constant{qw(GMT_ENUM OL_DOWN_MARK_WIDTH OL_MARK_HEIGHT BUTTON_INSET_X), 'segment moCS_selBkgdColor'} = (0, 16, 8, 6, 1);
$constant{'mask SDM_INVERSE'} = 128;
@constant{'mask OLSA_ENABLED', 'mask OLSA_TWISTED', 'mask OLSS_DOWN_FLAGS', qw(OLSS_PAGE_UP OLSS_PAGE_DOWN)} = (2, 4, 7, 2, 6);
@constant{map { "offset $_" } qw(vsbPageUp vsbPageDn hsbPageUp hsbPageDn cgahPageUp cgahPageDn spinGadget ISUI2000SpinUp ISUI2000SpinDown MenuDownMarkDarkBitmap)} = (1000, 1100, 1200, 1300, 1400, 1500, 2000, 4000, 4012, 8000);
@constant{map { "offset $_" } qw(ISUI2000ArrowUp ISUI2000ArrowDown ISUI2000ArrowLeft ISUI2000ArrowRight VUpInside VDownInside HUpInside HDownInside)} = (10000, 10012, 10024, 10036, 11001, 11002, 11003, 11004);
@constant{map { "offset $_" } qw(itemCheck itemMenuBullet itemCheckBoxBorder itemCheckBoxCheck)} = (7001, 7002, 7003, 7004);
$hasParent = 1; $parentIsTaskbar = 1; $parentLocked = 0;
sub value {
    my ($x) = @_;
    $x =~ s/^\s+|\s+$//g;
    $x =~ s/^\{word\}\s+//;
    return $reg{$x} // 0 if $x =~ /^(?:[abcd]x|[sd]i|bp|[de]s)$/;
    return ($reg{$1 . 'x'} >> ($2 eq 'h' ? 8 : 0)) & 255 if $x =~ /^([abcd])([hl])$/;
    return value($1) * 65536 + value($2) if $x =~ /^(bx|cx)(si|dx)$/;
    return $constant{$x} if exists $constant{$x};
    return $x if $x =~ /^-?\d+$/;
    return hex($1) if $x =~ /^(?:0x([0-9a-f]+))$/i;
    return hex($1) if $x =~ /^([0-9a-f]+)h$/i;
    return 2 * ($constant{ISUI2000_FIELD_Y_INSET} - 1) if $x eq '2 * (ISUI2000_FIELD_Y_INSET - 1)';
    return value($1) << $2 if $x =~ /^\((.+) shl (\d+)\)$/;
    return value($1) * 16 + value($2) if $x =~ /^ColorScheme <([^,]+),\s*(.+)>$/;
    if ($x =~ / or /) { my $v = 0; $v |= value($_) for split / or /, $x; return $v; }
    return value($1) if $x =~ /^\((.+)\)$/;
    return value($1) + value($2) if $x =~ /^(.+) \+ (.+)$/;
    return value('offset spinGadget') + 34 if $x eq 'offset spinGadget+34';
    return $mem{$x} // 0 if $x =~ /^(?:state|oldMask|background|attrs|selected\?|posX|posY|gstate|ltColor|rbColor|fillColor|darkColor)$/;
    $x =~ s{\[(si|di|bx|bp)(?:\+(\d+))?\]}{'[' . (value($1) + ($2 // 0)) . ']'}ge;
    return $mem{$x} // 0 if $x =~ /^(?:[de]s:|desiredSize\.)/;
    die "unknown operand: $x\n";
}
sub assign {
    my ($x, $v) = @_;
    $x =~ s/^\{word\}\s+//;
    if ($x =~ /^([abcd])([hl])$/) {
        my ($r, $shift) = ($1 . 'x', $2 eq 'h' ? 8 : 0);
        $reg{$r} = (($reg{$r} // 0) & ~(255 << $shift)) | (($v & 255) << $shift);
    } elsif ($x =~ /^(bx|cx)(si|dx)$/) { assign($1, $v >> 16); assign($2, $v & 65535);
    } elsif ($x =~ /^(?:state|oldMask|background|attrs|selected\?|posX|posY|gstate|ltColor|rbColor|fillColor|darkColor)$/) {
        $mem{$x} = $v;
    } elsif ($x =~ /^[de]s:/) {
        $x =~ s/\[(si|di|bx|bp)(?:\+(\d+))?\]/'[' . (value($1) + ($2 \/\/ 0)) . ']'/ge;
        $mem{$x} = $v;
    } else { $reg{$x} = $v; }
}
sub run {
    my ($name) = @_;
    $asm =~ /^$name\s+(?:proc|method)([^\n]*)\n(.*?)^$name\s+end[pm]/ms or die "missing $name\n";
    my ($declaration, $body) = ($1, $2);
    $body =~ s/\\\n\s*/ /g;
    my $prologue = "$declaration\n$body";
    $prologue =~ s/;[^\n]*//g;
    my @uses = $prologue =~ /(?:^|\s)uses\s+([^;\n]+)/m ? split(/,\s*/, $1) : ();
    my @saved = map { value($_) } @uses;
    my (@code, %label, @stack, @conditions, @returns);
    my $active = 1;
    for (split /\n/, $body) {
        s/;.*//; s/^\s+|\s+$//g;
        s/^(?:TABS|CUAS|NOFXIP)\s*<(.*?)>/$1/;
        next if /^(?:OLS|EC|FXIP)\s*</; s/\b(?:LONG|short)\s+//g;
        s/^\s+|\s+$//g;
        if (/^if\s+(.+)$/) {
            my %enabled = (_ISUI => $isui, _ISUI2000 => $isui2000, '_MOTIF or _ISUI' => 1, TOOL_AREA_IS_TASK_BAR => 1, '(not _DUI)' => 1,
                USE_COLOR_FOR_DISABLED_GADGETS => 0, DRAW_STYLES => 0,
                '((FRAME_TEXT_MARGIN - CGA_FRAME_TEXT_MARGIN) eq 1)' => 1,
                '(_MOTIF or _ISUI) and ALLOW_TAB_ITEMS' => 1);
            die "unknown condition $1\n" unless exists $enabled{$1};
            push @conditions, [$active, $enabled{$1}, $enabled{$1}]; $active &&= $enabled{$1}; next;
        } elsif (/^elif _ISUI$/) {
            my $chosen = !$conditions[-1][2] && $isui;
            $conditions[-1][1] = $chosen; $conditions[-1][2] ||= $chosen;
            $active = $conditions[-1][0] && $chosen; next;
        } elsif (/^else\b/) { $active = $conditions[-1][0] && !$conditions[-1][2]; $conditions[-1][2] = 1; next;
        } elsif (/^endif\b/) { $active = (pop @conditions)->[0]; next; }
        next unless $active;
        next if /^(?:$|uses\b|class\b|\.|MSG_)/ || /^[\w?]+\s+local\b/;
        if (/^([\w\$]+):$/) { $label{$1} = scalar @code; } else { push @code, $_; }
    }
    for (my $i = 0; $i < @code; $i++) {
        my $line = $code[$i];
        $line =~ s/^(segmov\s+\w+,\s*\w+),\s*\w+$/$1/;
        if ($line =~ /^(mov(?:dw)?|segmov|add|and|or(?:nf)?|shl|shr|sub|cmp(?:dw)?|test|xchg)\s+(.+?),\s*(.+)$/) {
            my ($op, $a, $b) = ($1, $2, $3);
            my $v = value($b);
            if ($op =~ /^mov/ || $op eq 'segmov') { assign($a, $v); }
            elsif ($op eq 'add') { assign($a, value($a) + $v); $zero = !value($a); $carry = 0; }
            elsif ($op =~ /^cmp/) { $zero = value($a) == $v; $carry = value($a) < $v;
                my ($left, $right) = (value($a), $v);
                $left -= 65536 if $left & 32768; $right -= 65536 if $right & 32768;
                $signedLess = $left < $right; }
            elsif ($op =~ /^or/ || $op eq 'and' || $op eq 'shl' || $op eq 'shr' || $op eq 'sub') {
                assign($a, $op =~ /^or/ ? value($a) | $v : $op eq 'and' ? value($a) & $v : $op eq 'shl' ? value($a) << $v : $op eq 'shr' ? value($a) >> $v : value($a) - $v);
                $zero = !value($a); $carry = 0; }
            elsif ($op eq 'test') { $zero = !(value($a) & $v); $carry = 0; }
            else { my $old = value($a); assign($a, $v); assign($b, $old); }
        } elsif ($line =~ /^rcl\s+(.+),\s*1$/) {
            my $old = value($1); assign($1, (($old << 1) | $carry) & 255); $carry = !!($old & 128);
        } elsif ($line =~ /^(inc|dec)\s+(.+)$/) {
            my ($op, $a) = ($1, $2); assign($a, value($a) + ($op eq 'inc' ? 1 : -1)); $zero = !value($a);
        } elsif ($line eq 'pushf') { push @stack, [$zero, $carry];
        } elsif ($line eq 'popf') { ($zero, $carry) = @{pop @stack};
        } elsif ($line =~ /^tst\s+(.+)$/) { $zero = !value($1); $carry = 0; $negative = !!(value($1) & 32768);
        } elsif ($line =~ /^clr\s+(.+)$/) { assign($_, 0) for split /,\s*/, $1; $zero = 1; $carry = 0;
        } elsif ($line =~ /^(push|pop)\s+(.+)$/) {
            my ($op, @r) = ($1, split /,\s*/, $2);
            if ($op eq 'push') { push @stack, [map { value($_) } @r]; }
            else { my $v = pop @stack or die "stack underflow\n"; assign($r[$_], $v->[$_]) for 0 .. $#r; }
        } elsif ($line =~ /^jcxz\s+([\w\$]+)$/) {
            $i = $label{$1} - 1 if !$reg{cx};
        } elsif ($line =~ /^(jz|je|jnz|jne|jnc|jc|jbe|jae|ja|jb|jl|jle|js|jmp)\s+([\w\$]+)$/) {
            my ($op, $target) = ($1, $2);
            $i = $label{$target} - 1 if $op eq 'jmp' ||
                ($op =~ /^j[ze]$/ ? $zero : $op =~ /^jn[ze]$/ ? !$zero : $op eq 'jc' ? $carry : $op eq 'jbe' ? $carry || $zero : $op eq 'ja' ? !$carry && !$zero :
                 $op eq 'jb' ? $carry : $op eq 'jl' ? $signedLess : $op eq 'jle' ? $signedLess || $zero : $op eq 'js' ? $negative : !$carry);
        } elsif ($line eq 'stc' || $line eq 'clc') { $carry = $line eq 'stc';
        } elsif ($line eq 'ret') { if (@returns) { $i = pop @returns; } else { last; }
        } elsif ($line =~ /^call\s+(\w+)$/) {
            my $call = $1;
            if (exists $label{$call}) { push @returns, $i; $i = $label{$call} - 1; next; }
            if ($call eq 'DrawGradient') { push @gradient, [value('al'), value('dh')]; }
            elsif ($call eq 'GeodeFind') {
                die "wrong Express geode search\n" unless $reg{ax} == 8 && $reg{cx} == 1 && $reg{dx} == 14 && $reg{es} == 2;
                push @searched, $constant{$reg{di}};
                $carry = $constant{$reg{di}} eq $loadedUI; $reg{bx} = $carry ? 99 : 0;
            }
            elsif ($call eq 'OpenCheckIfCGA') { $carry = $cga; }
            elsif ($call eq 'OpenMinimizeIfCGA') { $carry = $cga; }
            elsif ($call eq 'SysGetPenMode') { $reg{ax} = $penLarge; }
            elsif ($call eq 'CheckIfLargeHeight') { $carry = $penLarge; }
            elsif ($call eq 'ObjVarFindData') {
                my $hint = $reg{ax};
                if (defined $copyHintFixture) {
                    die "hint copy used the wrong source object\n" unless $reg{si} == 2;
                    $carry = $copyHintFixture->[0]; $reg{bx} = 9;
                    @mem{qw(ds:[9] ds:[11])} = @$copyHintFixture[1,2];
                } else {
                    $carry = $hint == 1001 ? $hasTitle : $hint == 1002 ? defined $fixedHeight :
                        $hint == 1003 ? defined $maxHeight : $hint == 1004 ? $penNoLarge : $hint == 1005 ? $noBorders : $hint == 1006 ? $express : die "unexpected hint\n";
                    $reg{bx} = 9;
                    $mem{'ds:[9].CSHA_height'} = ($hint == 1002 ? $fixedHeight : $maxHeight) // 0;
                }
            }
            elsif ($call eq 'ObjVarAddData') {
                die "hint copy used the wrong destination object\n" unless $reg{si} == 1;
                $hintCopied = 1; $reg{bx} = 19;
                @mem{qw(ds:[9] ds:[11])} = (0xdead, 0xbeef); # allocation moves the source
                @mem{qw(ds:[19] ds:[21])} = (0, 0);
            }
            elsif ($call eq 'ViewCreateCalcGState') { $gstates++; @reg{qw(di bp)} = (77, 77); }
            elsif ($call eq 'VisConvertSpecVisSize') {
                die "missing font GState\n" unless $gstates == 1 && $reg{di} == 77;
                $reg{ax} = $reg{ax} == 1 ? 25 * $fontWidth : $reg{ax} == 2 ? 7 * $fontHeight : die "bad preferred size\n";
            }
            elsif ($call eq 'GrDestroyState') { die "wrong GState\n" unless $reg{di} == 77 && $gstates == 1; $gstates--; }
            elsif ($call eq 'OpenCheckIfBW') { $carry = $bw; }
            elsif ($call eq 'OpenGetBackgroundColor') {
                $carry = defined $backgroundColors;
                $backgroundSelected = !!value('al');
                $reg{ax} = $carry ? $backgroundColors->[$backgroundSelected] : 0x0707;
            }
            elsif ($call eq 'GrGetCurPos') { @reg{qw(ax bx)} = @pen; }
            elsif ($call eq 'GrMoveTo') { @pen = @reg{qw(ax bx)}; }
            elsif ($call eq 'GrSetAreaMask') { $mask = value('al'); }
            elsif ($call eq 'GrSaveState') { push @savedGraphics, [$mixMode, $mask, $areaColor]; }
            elsif ($call eq 'GrRestoreState') {
                my $saved = pop @savedGraphics or die "unbalanced graphics state\n";
                ($mixMode, $mask, $areaColor) = @$saved;
            }
            elsif ($call eq 'GrSetMixMode') { $mixMode = value('al'); }
            elsif ($call eq 'GrFillRect') {
                push @fill, $mask; push @paintFill, [$areaColor, @reg{qw(ax bx cx dx)}];
                if (defined $surface) {
                    die "inversion was dithered\n" if $mixMode == 4 && $mask != 0;
                    for my $y ($reg{bx} .. $reg{dx}) {
                        for my $x ($reg{ax} .. $reg{cx}) {
                            next if defined $paintClip && ($x < $paintClip->[0] || $y < $paintClip->[1] || $x > $paintClip->[2] || $y > $paintClip->[3]);
                            my $key = "$x,$y";
                            die "inversion escaped the content rectangle\n" unless exists $surface->{$key};
                            $surface->{$key} = $mixMode == 4 ? $not[$surface->{$key}] : $areaColor;
                        }
                    }
                }
            }
            elsif ($call eq 'GrSetAreaColor') { $areaColor = value('al'); }
            elsif ($call eq 'GetCheckboxBounds') { @reg{qw(ax bx cx dx)} = (12, 26, 24, 37); $zero = 0; $carry = 1; }
            elsif ($call =~ /^Gr(?:Fill|Draw)Bitmap(?:AtCP)?$/) { push @bitmap, [$reg{si}, $areaColor, $mask]; push @bitmapPos, [@reg{qw(ax bx)}]; }
            elsif ($call eq 'GrGetAreaMask') { $reg{ax} = $mask; }
            elsif ($call eq 'OpenButtonCheckIfFullyEnabled') { $carry = !!$mem{'ds:[1].VI_attrs'}; }
            elsif ($call eq 'OpenDrawRectSolid') { push @solidFrame, [$reg{bp}, @reg{qw(ax bx cx dx)}]; @pen = (33, 43); }
            elsif ($call eq 'ApplySBParams') { } # fixtures contain literal table coordinates
            elsif ($call eq 'FillSBBitmap') { push @bitmap, [$reg{si}, $areaColor, $mask]; push @bitmapPos, [@mem{qw(posX posY)}]; $reg{si} += 6; }
            elsif ($call eq 'FillSBRect') { push @sbFill, [$reg{si}, $areaColor, $mask]; $reg{si} += 8; }
            elsif ($call eq 'DrawSBPart') { push @sbPart, $mem{'selected?'}; }
            elsif ($call =~ /^GrSet(?:LineMask|TextMask)$/) { }
            elsif ($call eq 'GrSetTextColor') { $textColor = value('al'); }
            elsif ($call eq 'GrSetLineColor') { $lineColor = value('al'); }
            elsif ($call eq 'GrDrawHLine') { push @line, [$reg{ax}, $reg{bx}, $reg{cx}, $lineColor]; @pen = @reg{qw(cx bx)}; $carry = 1; $zero = 0; }
            elsif ($call eq 'GrDrawVLine') { push @line, [$reg{ax}, $reg{bx}, $reg{dx}, $lineColor]; @pen = @reg{qw(ax dx)}; $carry = 1; $zero = 0; }
            elsif ($call eq 'GrGetLineColor') {
                my %rgb = (0 => [0, 0], 1 => [0, 0x8000], 7 => [192, 0xc0c0], 8 => [128, 0x8080], 15 => [255, 0xffff]);
                die "unknown RGB colour $lineColor\n" unless exists $rgb{$lineColor};
                @reg{qw(ax bx)} = @{$rgb{$lineColor}};
            }
            elsif ($call eq 'GenSwapLockParent') {
                $carry = $hasParent; $reg{si} = $hasParent ? 2 : 0;
                $reg{bx} = 1;
                if ($hasParent) { $reg{ds} = 2; $parentLocked++; }
            }
            elsif ($call eq 'ObjIsObjectInClass') {
                die "wrong taskbar query\n" unless $reg{si} == 2 && $reg{es} == 21 && $reg{di} == 31;
                $carry = $parentIsTaskbar;
            }
            elsif ($call eq 'ObjSwapUnlock') {
                die "unbalanced parent unlock\n" unless $parentLocked == 1;
                $parentLocked--; $reg{ds} = 1;
            }
            elsif ($call eq 'SetBlack') { $lineColor = 0; }
            elsif ($call eq 'CheckIfTabStyleItem') { $carry = 0; }
            elsif ($call eq 'OpenGetTextColor') { $carry = defined $textColors; $reg{ax} = $textColors->[0] | ($textColors->[1] << 8) if $carry; }
            elsif ($call eq 'OpenWinCheckIfBordered') { $carry = $bordered; }
            elsif ($call eq 'OpenWinGetBounds') { @reg{qw(ax bx cx dx)} = (0, 0, 100, 80); }
            elsif ($call eq 'FillRectWithBGColors') { $mask = 0; push @fill, 0; @reg{qw(ax bx cx dx)} = (10, 20, 34, 44); }
            elsif ($call eq 'WinDrawBoxFrame') {
                push @frame, $reg{bp} >> 8 == 1 ? 0 : (($reg{bp} & 15) | (($reg{bp} & 240) << 4));
            }
            elsif ($call eq 'VisGetBounds') { @reg{qw(ax bx cx dx)} = defined $bounds ? @$bounds : (10, 20, 34, 44); }
            elsif ($call eq 'VisCheckIfFullyEnabled') { $carry = !!$mem{'ds:[1].VI_attrs'}; }
            elsif ($call eq 'GetDarkColor') { $reg{ax} = 8; }
            elsif ($call eq 'GetLightColor') { $reg{ax} = $faceColor; }
            elsif ($call eq 'OpenDrawRect') { push @frame, $reg{bp}; push @rect, [@reg{qw(ax bx cx dx)}]; @pen = (33, 43); $carry = 1; $zero = 0; }
            elsif ($call eq 'VisMarkInvalid') { push @invalid, $reg{si}; }
            elsif ($call eq 'VisTestPointInBounds') {
                $carry = $reg{cx} >= 10 && $reg{cx} < 34 && $reg{dx} >= 20 && $reg{dx} < 44;
            } elsif ($call eq 'ObjCallInstanceNoLock') {
                die "wrong window query\n" unless $reg{ax} == 125 && $reg{cx} == 20 && $reg{dx} == 30;
                @reg{qw(ax bp cx dx)} = (0xdead, 0xbeef, 1, 900); $carry = 1;
            } elsif ($call eq 'ObjMessage') {
                local $reg{di} = $reg{si};
                run($reg{ax} == 124 ? 'OpenWinSetToolboxHover' : 'OLButtonSetToolboxHover');
            } else { run($call); }
        } else { die "unhandled $name instruction: $line\n"; }
    }
    die "unbalanced $name stack\n" if @stack;
    assign($uses[$_], $saved[$_]) for 0 .. $#uses;
}

# Ordinary controls, menus, caption buttons and monochrome keep their chrome.
for my $toolbox (0, $constant{'mask OLBMA_IN_TOOLBOX'}) {
    for my $kind (0, map { $constant{"mask $_"} } qw(OLBSS_IN_MENU OLBSS_IN_MENU_BAR OLBSS_SYS_ICON OLBSS_MENU_DOWN_MARK)) {
        for my $reply (0, $constant{'mask OLBFA_IN_REPLY_BAR'}) {
            for my $mono (0, 1) {
                $bw = $mono;
                %reg = (si => 1, di => 99);
                %mem = ('ds:[1]' => 1, 'ds:[1].OLBI_moreAttrs' => $toolbox,
                    'ds:[1].OLBI_specState' => $kind, 'ds:[1].OLBI_fixedAttrs' => $reply);
                run('OLButtonIsFlatToolbox');
                die "wrong toolbar scope: $toolbox/$kind/$reply/$bw carry=$carry\n" unless !!$carry == !!($toolbox && !$kind && !$reply && !$bw);
                die "instance register changed\n" unless $reg{di} == 99;
            }
        }
    }
}
$bw = 0;
# Moving onto and off the edge must preserve the original pointer event.
for my $point ([10, 20, 1], [33, 43, 1], [34, 20, 0], [10, 44, 0], [9, 20, 0]) {
    %reg = (ax => 91, bx => 92, cx => $point->[0], dx => $point->[1], bp => 0xa555, si => 1, di => 93);
    %mem = ('ds:[1]' => 1, 'ds:[LMBH_handle]' => 1,
        'ds:[1].OLBI_moreAttrs' => $constant{'mask OLBMA_IN_TOOLBOX'}, 'ds:[1].VI_attrs' => 0x80);
    my %before = %reg;
    run('OLButtonTrackToolboxHover');
    die "wrong pointer boundary\n" unless ($mem{'ds:[900].OLWI_toolboxHover'} // 0) == ($point->[2] ? 65537 : 0);
    die "pointer event damaged\n" if grep { $reg{$_} != $before{$_} } keys %before;
}
for my $state (0 .. 7) { # cursored, depressed, selected, and combinations
    for my $enabled (0, 1) {
        for my $hot (0, 1) {
            %reg = (ax => $state, bx => 77, cx => 88, dx => 99, si => 1, di => 50, bp => 66);
            %mem = ('ds:[1]' => 1, 'ds:[1].OLBI_toolboxHover' => $hot, 'ds:[1].VI_attrs' => $enabled);
            my %before = %reg;
            @pen = (4, 5); @frame = (); @fill = ();
            run('OLButtonDrawToolboxFrame');
            my $selected = $state & $constant{'mask OLBSS_SELECTED'};
            my $down = $state & $constant{'mask OLBSS_DEPRESSED'};
            my $edge = $selected || ($enabled && ($down || $hot));
            die "wrong toolbar edge $state/$enabled/$hot\n" unless @frame == !!$edge;
            die "wrong edge direction\n" if $edge && $frame[0] != ($selected || $down ? 0x0f08 : 0x080f);
            die "missing checked face\n" unless grep($_ == 6, @fill) == !!($selected && !$down);
            die "pen moved\n" unless "@pen" eq '4 5';
            die "register changed\n" if grep { $reg{$_} != $before{$_} } keys %before;
        }
    }
}
# Close and window-leave cleanup must forget the object before it is freed.
for my $method (qw(OLButtonVisClose OpenWinRawUnivLeave)) {
    $asm =~ /^$method\s+method[^\n]*\nif _ISUI2000\n(.*?)^endif/ms or die "missing $method cleanup\n";
    $asm .= "\nCleanup proc near\n$1\nCleanup endp\n";
    %reg = (si => $method eq 'OLButtonVisClose' ? 1 : 900);
    $reg{di} = $reg{si};
    %mem = ('ds:[1].OLBI_toolboxHover' => 1, 'ds:[900].OLWI_toolboxHover' => 65537,
        'ds:[1].OLBI_specState' => 5, 'ds:[900]' => 900);
    run('Cleanup');
    die "stale hover after $method\n" if $mem{'ds:[1].OLBI_toolboxHover'} || $mem{'ds:[900].OLWI_toolboxHover'};
    die "cleanup changed selection or focus\n" unless $mem{'ds:[1].OLBI_specState'} == 5;
    $asm =~ s/\nCleanup proc near.*?Cleanup endp\n//s;
}
# Same hit must not repaint; changing owner clears the previous control first.
%reg = (si => 900, di => 900, cx => 1, dx => 1);
%mem = (); @invalid = ();
for my $target (1, 1, 2, 0, 0) {
    @reg{qw(cx dx)} = ($target ? 1 : 0, $target);
    run('OpenWinSetToolboxHover');
    die "stale owner\n" unless $mem{'ds:[900].OLWI_toolboxHover'} == ($target ? 65536 + $target : 0);
}
die "wrong hover transitions: @invalid\n" unless "@invalid" eq '1 1 2 2';
die "hover left behind\n" if $mem{'ds:[1].OLBI_toolboxHover'} || $mem{'ds:[2].OLBI_toolboxHover'};
# Shell buttons retain raised/recessed states, with only one white highlight.
for my $selected (0, 4) {
    $bw = 0;
    %reg = (ax => 0, bx => $selected << 8, si => 1, di => 50);
    %mem = ('ds:[1]' => 1); @frame = (); @fill = (); @rect = ();
    run('ItemDrawColorTool');
    my @want = $selected ? (0x0f14, 0x0708) : (0x140f, 0x0807);
    die "wrong taskbar bevel\n" unless "@frame" eq "@want";
    die "wrong taskbar border bounds\n" unless "@{$rect[0]}" eq '10 20 34 44' && "@{$rect[1]}" eq '11 21 33 43';
    die "wrong active taskbar face\n" unless grep($_ == 6, @fill) == !!$selected;
}
# Dialog palette choices retain an outline and a recessed selection, using
# just the outer bevel. Menus, orphan items and the taskbar keep two levels.
for my $kind (qw(palette menu taskbar orphan monochrome)) {
    for my $selected (0, 4) {
        $bw = $kind eq 'monochrome'; $hasParent = $kind ne 'orphan';
        $parentIsTaskbar = $kind eq 'taskbar';
        %reg = (ax => 0, bx => $selected << 8, si => 1, di => 50, bp => 66, ds => 1, es => 41);
        %mem = ('ds:[1]' => 1, 'ds:[1].OLBI_specState' => $kind eq 'menu' ? $constant{'mask OLBSS_IN_MENU'} : 0);
        @frame = (); @fill = (); @rect = ();
        run('ItemDrawColorTool');
        my @want = $selected ? (0x0f14, 0x0708) : (0x140f, 0x0807);
        pop @want if $kind eq 'palette';
        die "wrong $kind bevel\n" unless "@frame" eq "@want";
        die "palette context damaged\n" unless $reg{si} == 1 && $reg{ds} == 1 && $reg{es} == 41 && $reg{bp} == 66 && $reg{bx} == $selected << 8;
        die "parent block left locked\n" if $parentLocked;
    }
}
$hasParent = 1; $parentIsTaskbar = 1; $bw = 0;
# Legacy ISUI keeps two black/white bevels in every toolbox-item context.
$isui2000 = 0;
for my $kind (qw(palette menu taskbar orphan monochrome)) {
    for my $selected (0, 4) {
        $bw = $kind eq 'monochrome'; $hasParent = $kind ne 'orphan';
        $parentIsTaskbar = $kind eq 'taskbar';
        %reg = (ax => 0, bx => $selected << 8, si => 1, di => 50, ds => 1);
        %mem = ('ds:[1]' => 1); @frame = (); @fill = ();
        run('ItemDrawColorTool');
        my @want = $selected ? (0x0f00, 0x0f08) : (0x000f, 0x080f);
        die "legacy $kind bevel changed\n" unless "@frame" eq "@want";
        die "legacy checked face changed\n" if grep($_ == 6, @fill);
        die "legacy parent unexpectedly locked\n" if $parentLocked;
    }
}
$hasParent = 1; $parentIsTaskbar = 1; $bw = 0;
for my $variant (0, 1) {
    $isui2000 = $variant;
    # Group-box etching must distinguish black ink from non-black erase colours.
    for my $axis (qw(H V)) {
        for my $mono (0, 1) {
            for my $ink (0, 1, 7, 15) {
                for my $bottom (0, 1) {
                    $bw = $mono; $lineColor = $ink; $carry = $bottom; @line = ();
                    %reg = (ax => 10, bx => 20, cx => 100, dx => 80, ds => 1);
                    run("DrawEtched${axis}Line");
                    my $coord = ($axis eq 'H' ? 20 : 10) - (!$mono && $bottom ? 1 : 0);
                    my @want = $mono ? ($ink) : $ink ? ($ink, $ink) : (($isui2000 ? 8 : 0), 15);
                    die "wrong etched colours for $isui2000/$axis/$mono/$ink/$bottom: " . join(" ", map { $_->[3] } @line) . " expected @want\n" unless join(' ', map { $_->[3] } @line) eq "@want";
                    for my $i (0 .. $#line) {
                        die "etched position changed\n" unless $line[$i][$axis eq 'H' ? 1 : 0] == $coord + $i;
                    }
                    die "etching changed bounds or erase ink\n" unless $reg{ax} == 10 && $reg{bx} == 20 && $lineColor == $ink && $reg{ds} == 1;
                }
            }
        }
    }
    # Colour menus get the softer shadow; other windows and B/W keep their edges.
    for my $menu (0, 1) {
        for my $mono (0, 1) {
            for my $hasBorder (0, 1) {
                $bordered = $hasBorder;
                %reg = (ax => ($mono ? 1 : 7) << 8, bp => 1, si => 1);
                %mem = ('ds:[1].OLWI_fixedAttr' => $menu ? $constant{'mask OWFA_IS_MENU'} : 0);
                @frame = (); @rect = ();
                run('OpenWinDrawWindowBorder');
                my @want = !$hasBorder ? () : $mono ? (0, 0) : ($menu && $isui2000 ? 0x1407 : 0x0007, 0x080f);
                die "wrong menu/window frame $menu/$mono/$hasBorder: @frame expected @want\n" unless "@frame" eq "@want";
                die "wrong menu border bounds\n" if $menu && $isui2000 && !$mono && $hasBorder &&
                    ("@{$rect[0]}" ne '0 0 100 80' || "@{$rect[1]}" ne '1 1 99 79');
            }
        }
    }
}
# Both separator rows must stay inside the reserved top/bottom margin.
for my $mono (0, 1) {
    for my $bottom (0, 1) {
        $bw = $mono; $carry = $bottom; $lineColor = 0; @line = ();
        %reg = (ax => 10, bx => 20, cx => 100);
        run('DrawISUIMenuSeparator');
        my @want = $mono ? ('10 20 100 0') : ('10 ' . (20 - $bottom) . ' 100 8', '10 ' . (21 - $bottom) . ' 100 15');
        die "wrong menu separator\n" unless join(';', map { "@$_" } @line) eq join(';', @want);
        die "separator changed caller bounds or ink\n" unless $reg{ax} == 10 && $reg{bx} == 20 && $lineColor == 0;
    }
}
for my $variant (0, 1) {
    $isui2000 = $variant;
    # A full-size browser/document has both a display-group rim and a view edge.
    # Blend the former into the configured UI face, retaining other modes.
    for my $mono (0, 1) {
        for my $state (0, 1, 128, 129, 255) {
            for my $face (7, 28) {
                $bw = $mono; $faceColor = $face; $mask = 0; @fill = (); @frame = ();
                %reg = (si => 1, di => 1, bp => 50);
                %mem = ('ds:[1]' => 1, 'ds:[1].OLDGI_states' => $state);
                run('DisplayGroupFrame');
                my $want = $isui2000 && !$mono && ($state & $constant{'mask OLDGS_MAXIMIZED'}) ? $face : 0;
                die "wrong display-group rim colour\n" unless $areaColor == $want;
                die "display-group draw contract changed\n" unless @fill == 1 && !@frame && $reg{di} == 50;
            }
        }
    }
}
# Defaults, four-bit compatibility and active/inactive gradient endpoints.
my $variables = source('CMain/cmainVariable.def');
$variables =~ /^if _ISUI\s*;.*?^(CUA_ColorSchemeVars.*?)(?=^endif\s*;ISUI)/ms
    or die "missing ISUI colour tables\n";
my $tables = $1;
my $prefs = source('../../Pref/ConfigUI/configui.asm');
$prefs =~ /^defaultISUI2000Colors Color \\\n(.*?)(?=^CheckHack)/ms
    or die "missing ISUI 2000 preset\n";
my @preset = $1 =~ /^\s*(C_\w+)/gm;
for my $variant (0, 1) {
    $isui2000 = $variant;
    my ($active, @rows) = (1);
    for (split /\n/, $tables) {
        if (/^if _ISUI2000/) { $active = $variant; next; }
        if (/^else/) { $active = !$variant; next; }
        if (/^endif/) { $active = 1; next; }
        push @rows, $_ if $active;
    }
    my $expanded = join "\n", @rows;
    my %defaults = $expanded =~ /^(moCS_\w+)\s+byte\s+(\w+)/gm;
    my @fields = qw(moCS_activeTitleBar moCS_titleBar2 moCS_dsDarkColor moCS_dsLightColor moCS_selBkgdColor);
    my @want = $variant ? (48, 177, 8, 28, 48) : (1, 1, 8, 7, 1);
    die "wrong compiled colour defaults\n" unless join(' ', map { value($defaults{$_}) } @fields) eq "@want";
    if ($variant) {
        die "preset differs from library defaults\n" unless join(' ', map { value($_) } @preset[0,1,2,3,6]) eq "@want";
        $expanded =~ /CUA_ColorSchemeVars(.*?)CUA_EndColorSchemeVars/s or die "missing colour fields\n";
        my $fieldCount = () = $1 =~ /^moCS_\w+\s+(?:byte|ColorSchemeFlags)\b/gm;
        $expanded =~ /CUA_MonochromeColorTable(.*)/s or die "missing monochrome table\n";
        my $mono = $1;
        my $monoCount = () = $mono =~ /^\s*byte\b/gm;
        die "monochrome table does not cover the gradient\n" unless $monoCount == $fieldCount;
        $mono =~ /byte\s+C_BLACK\s*$/s or die "wrong monochrome gradient endpoint\n";
    }
    for my $light (0 .. 15, 16, 28, 255) {
        for my $dark (0 .. 15, 16, 24, 255) {
            next if !$variant && ($light > 15 || $dark > 15);
            %reg = (ax => 0x7000);
            %mem = ('ds:[moCS_dsLightColor]' => $light, 'ds:[moCS_dsDarkColor]' => $dark);
            run('PackDisplayScheme');
            my $want = 0x7000 | (($light > 15 ? 7 : $light) << 4) | ($dark > 15 ? 8 : $dark);
            die "packed scheme corrupt\n" unless $mem{'ds:[specDisplayScheme.DS_colorScheme]'} == $want;
            die "full palette indices lost\n" unless $mem{'ds:[specDisplayScheme.DS_lightColor]'} == $light &&
                $mem{'ds:[specDisplayScheme.DS_darkColor]'} == $dark;
        }
    }
    for my $focused (0, 1) {
        %reg = (); @gradient = (); $zero = !$focused;
        %mem = ('ds:[moCS_activeTitleBar]' => 48, 'ds:[moCS_inactiveTitleBar]' => 8, 'ds:[moCS_titleBar2]' => 177);
        run('TitleGradientEndpoints');
        my @want = ($focused ? 48 : 8, !$focused && $variant ? 7 : 177);
        die "wrong caption gradient\n" unless @gradient == 1 && "@{$gradient[0]}" eq "@want";
    }
}
print "ISUI / ISUI 2000 chrome paint and hover checks passed\n";

# Use the actual preferred-size code, then GEOS's expand/clip and size-hint
# routines. Suggested sizes must remain suggestions, including CHOOSE_OWN_SIZE.
$isui2000 = 1;
for my $kind (qw(text graphic list empty no_generic no_gen_chunk menu menu_bar popup submenu caption title toolbar unbordered borderless_pressed setting express)) {
    for my $compact (0, 1) {
        $cga = $compact; $hasTitle = $kind eq 'title'; $noBorders = $kind eq 'borderless_pressed'; $express = $kind eq 'express';
        %reg = (ax => 32768, bx => 32768, cx => 24, dx => 17, si => 1, di => 1, bp => 991);
        %mem = ('ds:[1]' => 1, 'ds:[2]' => 2, 'ds:[3]' => 3,
            'ds:[1].OLBI_genChunk' => $kind eq 'no_gen_chunk' ? 0 : 2,
            'ds:[2].VI_typeFlags' => $kind eq 'no_generic' ? 0 : $constant{'mask VTF_IS_GEN'},
            'ds:[2].GI_visMoniker' => $kind eq 'empty' ? 0 : 3,
            'ds:[3].VM_type' => $kind eq 'graphic' ? 64 : $kind eq 'list' ? 128 : 0,
            'ds:[1].OLBI_moreAttrs' => $kind eq 'toolbar' ? $constant{'mask OLBMA_IN_TOOLBOX'} : 0,
            'ds:[1].OLBI_specState' => $kind eq 'unbordered' ? 0 : $constant{'mask OLBSS_BORDERED'});
        my %state = (menu => 'IN_MENU', menu_bar => 'IN_MENU_BAR', popup => 'MENU_DOWN_MARK', submenu => 'MENU_RIGHT_MARK', caption => 'SYS_ICON', setting => 'SETTING');
        $mem{'ds:[1].OLBI_specState'} |= $constant{'mask OLBSS_'.$state{$kind}} if exists $state{$kind};
        my %before = %reg;
        run('OLButtonApplyISUI2000Size');
        my $want = $kind eq 'text' && !$compact ? '75 23' : '24 17';
        die "wrong $kind/$compact preferred size\n" unless "$reg{cx} $reg{dx}" eq $want;
        die "size suggestions/registers damaged\n" if grep { $reg{$_} != $before{$_} } qw(ax bx bp si di);
        die "geometry GState leak\n" if $gstates;
    }
}
$cga = 0; $hasTitle = 0; $noBorders = 0; $express = 0;
%mem = ('ds:[1]' => 1, 'ds:[2]' => 2, 'ds:[3]' => 3,
    'ds:[1].OLBI_genChunk' => 2, 'ds:[2].VI_typeFlags' => 128,
    'ds:[2].GI_visMoniker' => 3, 'ds:[1].OLBI_specState' => $constant{'mask OLBSS_BORDERED'});
for my $metrics ([4,9,50,16], [6,13,75,23], [9,20,113,35], [14,32,175,56]) {
    ($fontWidth, $fontHeight) = @$metrics;
    for my $natural ([12,7], [200,80]) {
        %reg = (cx => $natural->[0], dx => $natural->[1], si => 1, di => 1);
        run('OLButtonApplyISUI2000Size');
        die "font/long moniker not accommodated\n" unless $reg{cx} == ($natural->[0] > $metrics->[2] ? $natural->[0] : $metrics->[2]) &&
            $reg{dx} == ($natural->[1] > $metrics->[3] ? $natural->[1] : $metrics->[3]);
    }
}
($fontWidth, $fontHeight) = (6, 13);
my $expand = $constant{'mask OLGDF_EXPAND_WIDTH_TO_FIT_PARENT'} | $constant{'mask OLGDF_EXPAND_HEIGHT_TO_FIT_PARENT'};
my $clip = $constant{'mask OLGDF_CAN_CLIP_MONIKER_WIDTH'} | $constant{'mask OLGDF_CAN_CLIP_MONIKER_HEIGHT'};
for my $parent ([180,40,0,75,23], [180,40,$expand,180,40], [50,18,$clip,50,18], [32768,32768,$expand,75,23], [32768,32768,$clip,75,23]) {
    %reg = (ax => $parent->[0], bx => $parent->[1], cx => 24, dx => 17, si => 1, di => 1, bp => $parent->[2]);
    run('OLButtonApplyISUI2000Size'); run('OpenChooseNewGadgetSize');
    die "parent geometry decision ignored\n" unless $reg{cx} == $parent->[3] && $reg{dx} == $parent->[4];
}
for my $limits ([0,0,0,0,0,0,75,23], [40,17,40,17,40,17,40,17], [0,0,100,30,0,0,100,30], [0,0,0,0,60,20,60,20]) {
    @mem{map { 'desiredSize.SSA_'.$_ } qw(fixedWidth fixedHeight minWidth minHeight maxWidth maxHeight)} = @$limits[0..5];
    %reg = (cx => 75, dx => 23);
    run('VisApplySizeArgsToWidth'); run('VisApplySizeArgsToHeight');
    die "fixed/min/max geometry hint ignored\n" unless $reg{cx} == $limits->[6] && $reg{dx} == $limits->[7];
}
my $buttonClass = source('CButton/copenButtonClass.asm');
$buttonClass =~ /OLButtonRerecalcSize\s+method(.*?)^OLButtonRerecalcSize\s+end[pm]/ms or die "missing button recalc\n";
die "preferred size bypasses geometry/hints\n" unless $1 =~ /call\s+OLButtonApplySizeHints.*?call\s+OLButtonApplyISUI2000Size.*?call\s+OpenChooseNewGadgetSize.*?call\s+OLButtonApplySizeHints/s;
# Single-line field margins preserve multi-line text, pen sizing and explicit
# height constraints. Width-only fixed/max hints still get normal field inset.
for my $variant (0, 1) {
    $isui2000 = $variant;
    for my $single (0, 1) {
        for my $compact (0, 1) {
            for my $pen (0, 1) {
                for my $heights ([undef,undef], [0,undef], [17,undef], [6144,undef], [undef,0], [undef,17], [undef,6144]) {
                    $cga = $compact; $penLarge = $pen; ($fixedHeight, $maxHeight) = @$heights;
                    %reg = (si => 1); %mem = ('ds:[1]' => 1, 'ds:[1].GTXI_attrs' => $single);
                    run('SetTextMargins');
                    my $want = $pen && $single ? 10 : $compact ? 1 : $variant && $single && !(($fixedHeight // 0) & 1023) && !(($maxHeight // 0) & 1023) ? 4 : 2;
                    die "single-line margin/hint regression\n" unless $mem{'ds:[1].VTI_tbMargin'} == $want;
                    die "multi-line/width margin changed\n" unless $mem{'ds:[1].VTI_lrMargin'} == 2;
                }
            }
        }
    }
}
$isui2000 = 1; $fixedHeight = $maxHeight = undef; $penLarge = $cga = 0;
for my $slider (0, 1) {
    for my $frame (0, 1) {
        for my $compact (0, 1) {
            for my $pen (0, 1) {
                $cga = $compact; $penLarge = $pen;
                %reg = (ax => 13, cx => 90, dx => 91, di => 1, si => 1);
                %mem = ('ds:[1].OLSGI_attrs' => $slider, 'ds:[1].OLSGI_states' => $frame);
                run('SpinFieldHeight');
                my $want = !$slider && $frame && !$compact && !$pen ? 19 : 13;
                die "spin default/pen/slider sizing regression\n" unless $reg{ax} == $want && $reg{cx} == 90 && $reg{dx} == 91;
            }
        }
    }
}
$penLarge = $cga = 0;

# The default ring is separate from content padding. Default/non-default reply
# buttons must retain the same geometry, including long or multi-line monikers.
my $regions = source('CButton/copenButtonData.asm');
$regions =~ /;ISUI reply bar button region structures(.*?);ISUI listbox button region structures/s or die "missing reply regions\n";
my $reply = $1;
$reply =~ s/^if _ISUI2000\n(.*?)^else\n.*?^endif\n/$1/msg;
for my $name (qw(MOBWButtonRegionSet_replyButton MOBWButtonRegionSet_defReplyButton)) {
    $reply =~ /^$name\s+label[^\n]*\n(.*?)(?=^MOBW|\z)/ms or die "missing $name\n";
    my @insets = $1 =~ /^\s*byte\s+(\w+)\s*$/gm;
    die "reply padding disagrees with drawing/default state\n" unless $insets[0] eq 'MO_BUTTON_INSET_X' && $insets[1] eq 'MO_BUTTON_INSET_Y';
}

for my $method (qw(SetupMonikerArgs OLButtonDrawMoniker)) {
    $asm =~ /^$method\s+proc[^\n]*\n(.*?)^$method\s+endp/ms or die "missing $method\n";
    die "drawing and moniker geometry disagree\n" unless $1 =~ /call\s+OLButtonIsISUI2000Command.*?or\s+a[lx], J_CENTER shl offset DMF_X_JUST/s;
}
print "ISUI 2000 geometry-manager checks passed\n";

# The shared UI must recognize both ISUI permanent names, for EC and NC alike.
for my $ui ('isui    ', 'isui2000', 'motif   ', 'motifr  ', 'isui2001', '') {
    $loadedUI = $ui;
    @searched = ();
    %mem = ('ds:[runningISUI]' => 128);
    %reg = (ax => 11, bx => 22, cx => 33, dx => 44, si => 55, di => 66, ds => 77, es => 88);
    my %before = %reg;
    my $found = $loadedUI eq 'isui    ' || $loadedUI eq 'isui2000' ? 1 : 0;
    for (1 .. 2) {
        run('CheckIfRunningISUI');
        die "wrong Express UI family/cache\n" unless (!$zero) == $found && $mem{'ds:[runningISUI]'} == $found;
        die "Express search damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;
        my $want = $loadedUI eq 'isui    ' ? 'isui    ' : 'isui    |isui2000';
        die "wrong Express lookup/cache sequence\n" unless join('|', @searched) eq $want;
    }
}
print "Express menu UI-family checks passed\n";

# Execute the shared menu renderer with the bounds call destroying DH, as on
# GEOS. Check both glyph types, inverse menu highlights and disabled masks.
for my $variant (0, 1) {
    $isui2000 = $variant;
    for my $checkbox (0, 1) {
        for my $selected (0, 1) {
            for my $depressed (0, 1) {
                for my $drawMask (0, 6) {
                    %reg = (ax => 11, bx => ($selected * $constant{'mask OLBSS_SELECTED'} |
                        $depressed * $constant{'mask OLBSS_DEPRESSED'}) << 8,
                        cx => 33, dx => $checkbox * $constant{'mask OLIS_IS_CHECKBOX'} << 8,
                        si => 55, di => 66, bp => 77, ds => 88);
                    my %before = %reg;
                    @bitmap = (); $mask = $drawMask;
                    run('ItemDrawISUICheck');
                    my $want = $variant && !$checkbox ? 7002 : 7001;
                    die "wrong menu glyph/state/colour/mask\n" unless @bitmap == $selected &&
                        (!$selected || join(',', @{$bitmap[0]}) eq "$want," . ($depressed ? 15 : 0) . ",$drawMask");
                    die "menu glyph damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;
                }
            }
        }
    }
    for my $selected (0, 1) {
        %reg = (bx => $selected * $constant{'mask OLBSS_SELECTED'} << 8, di => 66);
        @bitmap = (); $mask = 6;
        run('ItemDrawColorISUINonExclBox');
        die "wrong checkbox glyph/state/colour/mask\n" unless @bitmap == 1 + $selected &&
            (!$selected || join(',', @{$bitmap[1]}) eq '7004,' . ($variant ? 0 : 8) . ',6');
    }
}

# Compare actual ink coordinates, allowing different padded bitmap dimensions.
sub ink {
    my ($file, $label, $variant, $height) = @_;
    my $s = source($file);
    $s =~ /^\Q$label\E\s+label[^\n]*\n(.*?)(?=\n\n)/ms or die "missing $label\n";
    my $block = $1;
    $block =~ s/^if _ISUI2000\n(.*?)^else\n(.*?)^endif[^\n]*(?:\n|$)/$variant ? $1 : $2/mseg;
    my @rows;
    for (split /\n/, $block) {
        my @bytes = /([01]{8})b/g;
        push @rows, join('', @bytes) if @bytes;
    }
    die "wrong $label height\n" unless @rows == $height;
    my @ink;
    for my $y (0 .. $#rows) {
        for my $x (0 .. length($rows[$y]) - 1) {
            push @ink, "$x,$y" if substr($rows[$y], $x, 1) eq '1';
        }
    }
    return join(';', @ink);
}
my $tick = ink('CItem/citemItemColor.asm', 'itemCheckBoxCheck', 1, 10);
die "checkbox and menu ticks differ\n" unless
    ink('CItem/citemItemCommon.asm', 'itemCheck', 1, 12) eq $tick &&
    ink('CItem/citemItemBW.asm', 'checkBM', 1, 12) eq $tick;
die "menu and dialog radio bullets differ\n" unless
    ink('CItem/citemItemCommon.asm', 'itemMenuBullet', 1, 9) eq
    ink('CItem/citemItemColor.asm', 'itemRadioButtonBullet', 1, 9);
die "classic ISUI tick changed\n" if ink('CItem/citemItemCommon.asm', 'itemCheck', 0, 12) eq $tick;

# Select the ISUI branch before comparing its colour and monochrome arrows.
my $arrows = source('CButton/copenData.asm');
$arrows =~ s/^if _ISUI\b[^\n]*\n/MenuISUIBranch\n/mg;
my @down = $arrows =~ /^MenuISUIBranch\n\n(MenuDownMark(?:Dark)?Bitmap.*?)(?=^else\t\t;-)/msg;
die "missing ISUI dropdown tables\n" unless @down == 2;
my @bits;
for (@down) {
    s/^if _ISUI2000\n(.*?)^else\n(.*?)^endif[^\n]*\n/$1/msg;
    push @bits, join('', /([01]{8})b/g);
}
die "colour and monochrome dropdown triangles differ\n" unless $bits[0] eq $bits[1];
print "ISUI 2000 selection glyph checks passed\n";

# Paint states must leave the layout, origin and drawing-table consumption
# unchanged. Exercise colour painting with a nonzero origin and stale mask.
$isui2000 = 1; $bw = 0; $faceColor = 42;
for my $enabled (0, 1) {
    for my $pressed (0, 1) {
        %mem = ('ds:[1].VI_attrs' => $enabled, 'ds:[moCS_selBkgdColor]' => 1);
        %reg = (ax => 11, bx => $pressed * $constant{'mask OLBSS_DEPRESSED'},
            cx => 80, dx => 24, si => 1, di => 66, bp => 77, ds => 1);
        my %before = %reg;
        @pen = (10, 20); @solidFrame = (); @paintFill = (); $mask = 6;
        run('OLButtonDrawISUI2000DropDown');
        my $edge = $enabled && $pressed ? 15 * 256 + 8 : 20 * 256 + 7;
        die "wrong dropdown state/frame bounds\n" unless @solidFrame == 4 &&
            join(',', @{$solidFrame[0]}) eq '3848,10,20,90,44' &&
            join(',', @{$solidFrame[2]}) eq "$edge,73,22,89,42" &&
            $paintFill[0][0] == ($enabled ? 15 : 42);
        die "dropdown paint changed geometry/registers/origin\n" if
            join(',', @pen) ne '10,20' || grep { $reg{$_} != $before{$_} } keys %before;
        @bitmap = (); @bitmapPos = (); $mask = 6; $areaColor = 11;
        run('OLButtonDrawISUI2000DropDownMark');
        die "wrong dropdown glyph state or disabled emboss\n" unless @bitmap == ($enabled ? 1 : 2) &&
            $bitmap[-1][1] == ($enabled ? 0 : 8) && $mask == 6 && $areaColor == 11 &&
            join(',', @{$bitmapPos[-1]}) eq ($enabled && $pressed ? '70,29' : '69,28');
        die "dropdown mark damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;

        # Check visible ink against the arrow button, not the padded bitmap.
        my @ink = grep { substr($bits[0], $_, 1) eq '1' } 0 .. length($bits[0])-1;
        my @xs = sort { $a <=> $b } map { $_ % 16 } @ink;
        my @ys = sort { $a <=> $b } map { int($_ / 16) } @ink;
        my ($x, $y) = @{$bitmapPos[-1]};
        $x--, $y-- if $enabled && $pressed; # intentional pressed displacement
        my (undef, $left, $top, $right, $bottom) = @{$solidFrame[2]};
        die "dropdown triangle ink is not centered in its frame\n" if
            abs(($x + $xs[0] - $left) - ($right - 1 - $x - $xs[-1])) > 1 ||
            abs(($y + $ys[0] - $top) - ($bottom - 1 - $y - $ys[-1])) > 1;

        for my $case ([5000, 11001, 10000, 6], [5100, 11002, 10012, 6],
                      [5200, 11003, 10024, 6], [5300, 11004, 10036, 6],
                      [5400, 11201, 5432, 12], # unchanged CGA glyph path
                      [2002, 0, 4000, 6], [3002, 0, 4012, 6]) {
            my ($start, $sourceBitmap, $normal, $pressedStep) = @$case;
            %mem = (attrs => ($enabled ? 2 : 0) | ($start < 5000 ? 4 : 0),
                'selected?' => $pressed ? 0 : 255, fillColor => 42, ltColor => 15,
                rbColor => 8, posX => 10, posY => 20);
            @mem{map { 'ds:[' . ($start + $_) . ']' } (8, 10, 16, 26)} = (11, 21, 23, 34);
            $mem{'ds:[' . ($start + 36) . ']'} = $sourceBitmap;
            %reg = (si => $start, di => 66, bp => 77);
            @solidFrame = (); @bitmap = (); @bitmapPos = (); $mask = 6;
            run('HVUpDownArrow');
            my $glyph = $normal + ($enabled && $pressed ? $pressedStep : 0);
            die "wrong scrollbar/spinner arrow frame/table advance\n" unless
                $reg{si} == $start + 56 && $reg{bp} == 77 && @solidFrame == 2 &&
                $solidFrame[0][0] == $edge && $bitmap[-1][0] == $glyph &&
                $bitmap[-1][1] == ($enabled ? 0 : 8) && @bitmap == ($enabled ? 1 : 2) &&
                $mem{posX} == 10 && $mem{posY} == 20;
        }
    }
}
for my $state (0, 2, 6) {
    for my $part (1000, 1100, 1200, 1300, 1400, 1500) {
        %mem = (attrs => 2, gstate => 66, 'es:[1].OLSBI_state' => $state);
        %reg = (ax => 11, si => $part, di => 1); @sbPart = ();
        run('DrawPageUpDownArea');
        my $selected = $state && (($state == 2) == ($part % 200 == 0));
        die "wrong pressed page region\n" unless @sbPart == 1 && $sbPart[0] == ($selected ? 0 : 255);
        @sbFill = (); $mem{fillColor} = 42; $mem{darkColor} = 8; $reg{si} = 6000;
        run('HVPageUpDn');
        die "wrong track pattern or table advance\n" unless $reg{si} == 6008 && @sbFill == 2 &&
            $sbFill[0][1] == ($selected ? 8 : 42) && $sbFill[1][1] == ($selected ? 0 : 15) && $mask == 0;
    }
}
for my $inert (0, 1) {
    %mem = (attrs => 2, 'selected?' => 255, fillColor => 42, ltColor => $inert ? 7 : 15, rbColor => $inert ? 7 : 8);
    @mem{qw(ds:[7008] ds:[7010] ds:[7016] ds:[7026])} = (11, 21, 23, 34);
    %reg = (si => 7000, di => 66, bp => 77); @solidFrame = ();
    run('HVThumb');
    die "wrong thumb frame/table advance\n" unless $reg{si} == 7040 && @solidFrame == ($inert ? 0 : 2);
}
print "ISUI 2000 scrollbar, spinner and dropdown paint checks passed\n";

# Compare the native geometry expressions and coordinate tables with the
# supplied Windows 2000 reference: 16-pixel shaft, square inset end buttons.
sub geometry_value {
    my ($expr, $values) = @_;
    $expr =~ s/\b([A-Z][A-Z_0-9]*)\b/exists $values->{$1} ? $values->{$1} : die "unknown geometry constant $1\n"/ge;
    die "invalid geometry expression $expr\n" unless $expr =~ /^[0-9\s()+*\/-]+$/;
    my $v = eval $expr;
    die $@ if $@;
    return $v;
}
my $scrollDraw = source('../ISUI/View/viewScrollbarDraw.asm');
$scrollDraw =~ s/\\\n\s*/ /g;
my $scrollSelect = source('CView/cviewScrollbarSelect.asm');
$scrollSelect =~ /(\tmov\tbx, MO_ARROW_HEIGHT.*?^10\$:)/ms or die "missing scrollbar hit dimensions\n";
$asm .= "\nScrollHitDimensions proc near\n$1\nret\nScrollHitDimensions endp\n";
$constant{'mask OLSA_VERTICAL'} = 64;
for my $variant (0, 1) {
    my $constants = $shared;
    $constants =~ s/^if _ISUI2000\n(\s+MO_SCROLLBAR_WIDTH[^\n]*\n)^else\n(.*?)^endif/$variant ? $1 : $2/mseg;
    my %v = (PARAM_2 => 37, PARAM_3 => 300);
    for my $name (qw(MO_ARROW_WIDTH CGA_HORIZ_ARROW_WIDTH MO_ARROW_HEIGHT MO_SCROLLBAR_WIDTH MO_ARROW_BITMAP_INSET CGA_HORIZ_SCROLLBAR_WIDTH MO_SCR_AREA_MARGIN MO_THUMB_HEIGHT NUI_SPIN_ARROW_HEIGHT)) {
        $constants =~ /^\s*(?:ISU<\s*)?\Q$name\E\s*=\s*([^;>\n]+)/m or die "missing geometry $name\n";
        $v{$name} = geometry_value($1, \%v);
    }
    die "wrong scrollbar width/arrow reservation\n" unless $v{MO_SCROLLBAR_WIDTH} == ($variant ? 16 : 14) && $v{MO_SCR_AREA_MARGIN} == 15;
    $isui2000 = $variant;
    @constant{qw(MO_ARROW_HEIGHT MO_SCROLLBAR_WIDTH-1 MO_ARROW_WIDTH+2 NUI_SPIN_ARROW_HEIGHT+2),
        'MO_SCROLLBAR_WIDTH - CGA_HORIZ_SCROLLBAR_WIDTH'} =
        ($v{MO_ARROW_HEIGHT}, $v{MO_SCROLLBAR_WIDTH}-1, $v{MO_ARROW_WIDTH}+2,
         $v{NUI_SPIN_ARROW_HEIGHT}+2, $v{MO_SCROLLBAR_WIDTH}-$v{CGA_HORIZ_SCROLLBAR_WIDTH});
    for my $kind (qw(vertical horizontal cga spinner)) {
        $cga = $kind eq 'cga';
        %reg = (di => 1);
        %mem = ('ds:[1].OLSBI_attrs' => $kind eq 'spinner' ? 68 : $kind eq 'vertical' ? 64 : 0);
        run('ScrollHitDimensions');
        my $width = $kind eq 'spinner' ? 15 : $cga ? 10 : $v{MO_SCROLLBAR_WIDTH};
        die "scrollbar paint/hit width mismatch\n" unless $reg{bp} + 1 == $width &&
            $reg{bx} == ($kind eq 'spinner' ? 12 : 13);
    }
    for my $case (['vertScrollbar', 0, 14, $variant ? 14 : 12],
                  ['vsbDnArrow', 0, 14, $variant ? 14 : 12],
                  ['horizScrollbar', 0, $variant ? 14 : 12, 14],
                  ['hsbPageDn', 1, $variant ? 14 : 12, 14],
                  ['CGAHorizScrollbar', 0, 8, 14],
                  ['spinGadget', 0, 10, 13], ['spinDnArrow', 0, 10, 13]) {
        my ($label, $skip, $height, $width) = @$case;
        $scrollDraw =~ /^\Q$label\E\s+label[^\n]*\n(.*)/ms or die "missing table $label\n";
        my @records = $1 =~ /^\s*word\s+([^\n]+)/mg;
        my @edge = map { [map { geometry_value($_, \%v) } split /,\s*/, $records[$_]] } $skip .. $skip + 3;
        die "wrong $label proportions\n" unless $edge[2][0] - $edge[1][0] + 1 == $width &&
            $edge[3][1] - $edge[1][1] + 1 == $height;
        my @glyph = split /,\s*/, $records[$skip + 4];
        if ($label =~ /^(vertScrollbar|vsbDnArrow|horizScrollbar|hsbPageDn)$/) {
            my $cross = $label =~ /^(vertScrollbar|vsbDnArrow)$/ ? 0 : 1;
            die "arrow bitmap not recentered\n" unless geometry_value($glyph[$cross], \%v) == ($variant ? 2 : 1);
        }
    }
}
my $scrollSize = source('CView/cviewScrollbar.asm');
$scrollSize =~ /ISU\s*<\s*mov\s+cx, ([^;>\n]+);keep spinner width/ or die "missing spinner width\n";
die "scrollbar change resized spinner\n" unless geometry_value($1, {MO_ARROW_WIDTH => 12}) == 15;
print "ISUI / ISUI 2000 scrollbar proportions and spinner isolation checks passed\n";

# Check actual ink dimensions and padding, not screenshot display scaling.
for my $case (['Up', 6, 3, 1, 1], ['Down', 6, 3, 1, 286],
              ['Left', 3, 6, 1, 1], ['Right', 3, 6, 286, 1]) {
    my ($direction, $width, $height, $left, $top) = @$case;
    my $label = 'ISUI2000Arrow' . $direction;
    my @pixels = map { [split /,/] } split /;/, ink('../ISUI/View/viewScrollbarDraw.asm', $label . 'BM', 1, $height);
    die "wrong compact arrow ink\n" unless @pixels == 12 &&
        !grep { $_->[0] >= $width || $_->[1] >= $height } @pixels;
    my @x = sort {$a <=> $b} map { $_->[0] } @pixels;
    my @y = sort {$a <=> $b} map { $_->[1] } @pixels;
    die "compact arrow bounding box changed\n" unless $x[0] == 0 && $x[-1] == $width-1 && $y[0] == 0 && $y[-1] == $height-1;
    $scrollDraw =~ /^\Q$label\E\s+label[^\n]*\n\s*word\s+([^\n]+)\n\s*word\s+([^\n]+)/m or die "missing compact arrow positions\n";
    my @normal = split /,\s*/, $1; my @pressed = split /,\s*/, $2;
    my %v = (PARAM_3 => 300, MO_ARROW_HEIGHT => 13);
    my ($px, $py) = map { geometry_value($_, \%v) } @normal[0,1];
    my @padding = ($px-$left, $left+14-$px-$width, $py-$top, $top+14-$py-$height);
    my $want = $width == 6 ? '4,4,5,6' : '5,6,4,4';
    die "wrong compact arrow padding\n" unless join(',', @padding) eq $want;
    die "pressed arrow moved its frame\n" unless geometry_value($pressed[0], \%v) == $px+1 && geometry_value($pressed[1], \%v) == $py+1;
}
print "ISUI 2000 compact arrow ink and padding checks passed\n";

# Execute the normal-content drawing and the actual post-moniker inversion.
my $buttonColor = source('CButton/copenButtonColor.asm');
$buttonColor =~ /call\s+OLButtonDrawMoniker\n(if _ISUI\n\t;\n\t; Invert the completed content.*?^endif\n\tret)/ms
    or die "missing post-moniker dropdown inversion\n";
$asm .= "\nInvertDropDownContent proc near\n$1\nInvertDropDownContent endp\n";
$buttonColor =~ /DrawColorButtonInterior\s+proc.*?(\tclr\tax.*?call\s+OpenGetBackgroundColor[^\n]*)/s
    or die "missing classic dropdown background state\n";
$asm .= "\nClassicDropDownBackground proc near\n$1\nret\nClassicDropDownBackground endp\n";
my $popupBuild = source('CItem/citemItemGroupClass.asm');
$asm .= "\n$popupBuild";
for my $size (0, 2, 4) {
    for my $present (0, 1) {
        $copyHintFixture = [$present, 0x0f07, 0x0803]; $hintCopied = 0;
        %reg = (ax => 1008, bx => 3, cx => $size, dx => 44, bp => 55, si => 1, di => 2);
        %mem = ();
        run('CopyHintIfSpecified');
        die "hint copy changed registers or copied an absent hint\n" unless
            $reg{si} == 1 && $reg{di} == 2 && $reg{dx} == 44 && $reg{bp} == 55 && $hintCopied == $present;
        die "hint copy lost normal or selected background colours\n" if $present &&
            (($size >= 2 && $mem{'ds:[19]'} != 0x0f07) || ($size == 4 && $mem{'ds:[21]'} != 0x0803));
    }
}
$copyHintFixture = undef;
die "popup builder rewrites text hints or loses explicit backgrounds\n" unless
    $popupBuild !~ /mov\s+ds:\[bx\].TC_selectedColor/ &&
    $popupBuild =~ /mov\s+cx, size BackgroundColors\n\s*mov\s+ax, HINT_GADGET_BACKGROUND_COLORS\n\s*call\s+CopyHintIfSpecified/;
my @profiles = (undef, [$constant{C_BLUE}, $constant{C_WHITE}],
    [$constant{C_BLUE}, $constant{C_BLUE}, 'custom background']);
for my $file (qw(uiFont.ui uiPointSize.ui)) {
    my $ui = source('../../Text/UI/' . $file);
    $ui =~ /HINT_GADGET_TEXT_COLOR\s*\{\s*byte\s+(C_\w+)\s*byte\s+(C_\w+)/s or die "missing $file text colours\n";
    push @profiles, [$constant{$1}, $constant{$2}];
}
for my $variant (qw(motif isui isui2000)) {
    $isui = $variant ne 'motif'; $isui2000 = $variant eq 'isui2000';
    for my $profile (@profiles) {
        $textColors = $profile;
        $backgroundColors = defined $profile && @$profile > 2 ? [0x0f07, 0x0803] : undef;
        for my $pressed (0, 1) {
            %reg = (ax => 22, bx => $constant{'mask OLBSS_MENU_DOWN_MARK'} |
                $pressed * $constant{'mask OLBSS_DEPRESSED'}, si => 1, di => 66, cx => 80, dx => 24, ds => 1);
            %mem = ('ds:[1]' => 1, 'ds:[1].Vis_offset' => 0, 'ds:[1].OLBI_genChunk' => 2,
                'ds:[1].VI_attrs' => 1);
            my %before = %reg;
            my $normal = defined $profile ? $profile->[0] : $constant{C_BLACK};
            my $selected = defined $profile ? $profile->[1] : $constant{C_WHITE};
            if ($isui2000) {
                @pen = (10, 20); @paintFill = (); @solidFrame = (); $mask = 6;
                run('OLButtonDrawISUI2000DropDown');
                my $pair = defined $backgroundColors ? $backgroundColors->[0] : 0x0f0f;
                die "dropdown changed normal background before inversion\n" unless $paintFill[0][0] == ($pair & 255);
                if (defined $backgroundColors) {
                    die "dropdown lost second background colour\n" unless
                        $paintFill[1][0] == ($pair >> 8) &&
                        join(',', @{$paintFill[0]}[1..4]) eq join(',', @{$paintFill[1]}[1..4]);
                }
                die "background painting damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;
            }
            run('OLButtonSetDrawColors');
            my $expected = $pressed && !$isui ? $selected : $normal;
            die "wrong popup moniker colour\n" unless $textColor == $expected && $areaColor == $expected;
            die "popup text painting damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;
            if ($isui2000) {
                @pen = (10, 20); $mask = 6;
                run('OLButtonDrawISUI2000DropDownMark');
                die "dropdown arrow changed moniker ink/mask\n" unless $areaColor == $expected && $mask == 6;
            }
            if ($isui) {
                %reg = %before;
                $mem{'ds:[1].OLBI_specState'} = $reg{bx};
                run('ClassicDropDownBackground');
                die "classic dropdown used selected background before inversion\n" if $backgroundSelected;
            }
        }
    }
}
$backgroundColors = undef;
for my $variant (qw(motif isui isui2000)) {
    $isui = $variant ne 'motif'; $isui2000 = $variant eq 'isui2000';
    for my $excluded (0, map { $constant{"mask $_"} } qw(OLBSS_IN_MENU OLBSS_IN_MENU_BAR OLBSS_SYS_ICON)) {
        for my $enabled (0, 1) {
            for my $pressed (0, 1) {
                for my $small (0, 1, 2) {
                    $bounds = [10, 20, $small == 1 ? 25 : 90, $small == 2 ? 23 : 44];
                    my $right = $bounds->[2] - ($isui2000 ? 18 : 19);
                    my $bottom = $bounds->[3] - 3;
                    my %normal;
                    for my $y (22 .. $bottom) {
                        for my $x (12 .. $right) {
                            # All palette indices, including fixed-colour artwork.
                            $normal{"$x,$y"} = (($x-12) + ($y-22)*60) % 256;
                        }
                    }
                    for my $partial (0, 1) {
                        $paintClip = $partial ? [20, 24, 40, 35] : undef;
                        for (1 .. 2) {
                            # Every redraw starts from the completed normal content.
                            $surface = {%normal};
                            %reg = (ax => 11, bx => 22, cx => 33, dx => 44, bp => 55, si => 1, di => 66);
                            %mem = ('ds:[1]' => 1, 'ds:[1].Vis_offset' => 0, 'ds:[1].VI_attrs' => $enabled,
                                'ds:[1].OLBI_specState' => $constant{'mask OLBSS_MENU_DOWN_MARK'} |
                                    ($pressed * $constant{'mask OLBSS_DEPRESSED'}) | $excluded);
                            my %before = %reg;
                            $mixMode = 5; $mask = 6; $areaColor = 11; @paintFill = ();
                            run('InvertDropDownContent');
                            my $invert = $isui && !$excluded && $enabled && $pressed && !$small;
                            die "wrong inversion rectangle or scope\n" unless @paintFill == ($invert ? 1 : 0);
                            if ($invert) {
                                die "inversion touched frame or arrow\n" unless
                                    join(',', @{$paintFill[0]}[1..4]) eq "12,22,$right,$bottom";
                            }
                            for my $key (keys %normal) {
                                my ($x, $y) = split /,/, $key;
                                my $inside = !$partial || ($x >= 20 && $x <= 40 && $y >= 24 && $y <= 35);
                                my $want = $invert && $inside ? $not[$normal{$key}] : $normal{$key};
                                die "wrong rendered colour inversion\n" unless $surface->{$key} == $want;
                            }
                            die "inversion damaged graphics state\n" unless $mixMode == 5 && $mask == 6 && $areaColor == 11 && !@savedGraphics;
                            die "inversion damaged registers\n" if grep { $reg{$_} != $before{$_} } keys %before;
                        }
                    }
                }
            }
        }
    }
}
$surface = $paintClip = $bounds = undef;
# Saving the GState must retain arbitrary RGB ink and a custom 8x8 mask.
$isui2000 = 1;
my $customMask = [0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55];
%reg = (ax => 11, bx => 22, cx => 80, dx => 24, bp => 55, si => 1, di => 66, ds => 1);
%mem = ('ds:[1].VI_attrs' => 1);
@pen = (10, 20); $mask = $customMask; $areaColor = 0x123456; $mixMode = 5;
run('OLButtonDrawISUI2000DropDownMark');
die "arrow damaged custom mask or RGB ink\n" unless
    $mask == $customMask && $areaColor == 0x123456 && $mixMode == 5 && !@savedGraphics;
$mask = 6;
print "ISUI / ISUI 2000 rendered dropdown inversion and arrow ink checks passed\n";

# Caption slots include the one pixel removed by native colour placement.
$shared =~ /if _ISUI2000\n(?:\t;[^\n]*\n)*CUAS_CAPTION_ICON_WIDTH = (\d+)/ or die "missing ISUI 2000 caption width\n";
die "wrong caption width\n" unless $1-1 == 16;
my $caption = source('CWin/cwinClassCUAS.asm');
die "caption reservation/placement disagree\n" unless
    $caption =~ /notSysMenuButton:\nif _ISUI2000\n\t\tmov\tax, CUAS_CAPTION_ICON_WIDTH/ &&
    $caption =~ /sub\s+ds:\[di\].OLWI_titleBarBounds.R_right, CUAS_CAPTION_ICON_WIDTH\+1/;
print "ISUI 2000 caption width checks passed\n";

# Exercise the actual inset/justification branch, including wider system menus.
my $buttonPaint = source('CButton/copenButtonColor.asm');
$buttonPaint =~ /(\tmov\tdx, 2\t+;assume system icon.*?)(?=^50\$:)/ms
    or die "missing caption moniker placement\n";
$asm .= "\nCaptionMonikerPlacement proc near\n$1\n50\$:\nret\nCaptionMonikerPlacement endp\n";
$constant{'CUAS_CAPTION_ICON_WIDTH-1'} = 16;
$constant{MO_BUTTON_INSET_X} = 6;
for my $variant (qw(isui isui2000)) {
    $isui2000 = $variant eq 'isui2000';
    for my $width (16, 20, 27) {
        for my $sysIcon (0, 1) {
            %reg = (ax => 0, si => 1);
            %mem = ('ds:[1]' => 1, 'ds:[1].Vis_offset' => 0,
                'ds:[1].OLBI_specState' => $sysIcon * $constant{'mask OLBSS_SYS_ICON'},
                'ds:[1].VI_bounds.R_left' => 100, 'ds:[1].VI_bounds.R_right' => 100 + $width);
            run('CaptionMonikerPlacement');
            my $compact = $isui2000 && $sysIcon && $width == 16;
            die "wrong caption moniker placement\n" unless
                $reg{dx} == ($compact ? 0 : $sysIcon ? 2 : 6) &&
                $reg{ax} == ($compact ? $constant{'J_CENTER shl offset DMF_X_JUST'} : 0);
        }
    }
}
print "ISUI / ISUI 2000 caption moniker placement checks passed\n";

# Tab detection must preserve ordinary toolbox/taskbar moniker justification.
my $itemPaint = source('CItem/citemItemColor.asm');
$itemPaint =~ /^87\$:[^\n]*\n(.*?)(?=^checkInMenu:)/ms or die "missing toolbox moniker setup\n";
my $itemInsets = $1;
$itemInsets =~ s/^TAB_\w+ equ \d+\n//gm;
$itemInsets =~ s/andnf/and/g;
$asm .= "\nToolboxMonikerInsets proc near\n$itemInsets\ncheckInMenu:\nret\nToolboxMonikerInsets endp\n";
@constant{qw(TOOLBOX_INSET_X TOOLBOX_INSET_Y TAB_INSET_Y TAB_UNSELECTED_Y_OFFSET OLITS_TAB_TOP),
    'mask OLIER_TAB_STYLE', 'J_CENTER shl offset DMF_X_JUST', 'J_CENTER shl offset DMF_Y_JUST',
    'J_LEFT shl offset DMF_X_JUST', 'J_LEFT shl offset DMF_Y_JUST'} = (2, 2, 4, 2, 1, 7, 2, 8, 0, 0);
for my $variant (qw(motif isui isui2000)) {
    $isui = $variant ne 'motif'; $isui2000 = $variant eq 'isui2000';
    for my $extra (0, 16, 1, 4) { # plain, help flag, top tab, bottom tab
        for my $selected (0, 1) {
            %reg = (ax => ($constant{'mask OLIS_DRAW_AS_TOOLBOX'} << 8) | 8, si => 1);
            %mem = ('ds:[1]' => 1, 'ds:[1].Vis_offset' => 0, 'ds:[1].OLII_extraRecord' => $extra,
                'ds:[1].OLBI_specState' => $selected * $constant{'mask OLBSS_SELECTED'});
            run('ToolboxMonikerInsets');
            my $tab = $extra & 7;
            my $inset = $tab ? ((4 + ($tab == 1 && !$selected ? 2 : 0)) << 8) : 0x0202;
            die "$variant toolbox/taskbar moniker alignment changed\n" unless
                value('al') == ($tab ? 2 : 8) && $reg{dx} == $inset;
        }
    }
}
print "ISUI / ISUI 2000 / Motif toolbox and taskbar moniker alignment checks passed\n";

# Taskbar padding must exceed the frame and reserve space on both sides.
$itemPaint = source('CItem/citemItemColor.asm');
$itemPaint =~ /^90\$:\n(if TOOL_AREA_IS_TASK_BAR.*?^endif)\n/ms or die "missing taskbar padding\n";
$asm .= "\nTaskbarMonikerPadding proc near\n$1\nret\nTaskbarMonikerPadding endp\n";
for my $variant (qw(motif isui isui2000)) {
    $isui = $variant ne 'motif'; $isui2000 = $variant eq 'isui2000';
    for my $kind (qw(taskbar palette orphan ordinary)) {
        $hasParent = $kind ne 'orphan'; $parentIsTaskbar = $kind eq 'taskbar';
        my $oldInset = $isui ? 3 : 2;
        %reg = (ax => 8 | ($kind eq 'ordinary' ? 0 : $constant{'mask OLIS_DRAW_AS_TOOLBOX'} << 8),
            bx => 55, cx => 66, dx => 0x0200 | $oldInset, si => 1, di => 77, ds => 1, es => 41);
        my %before = %reg;
        run('TaskbarMonikerPadding');
        die "$variant $kind horizontal padding wrong\n" unless
            value('dl') == ($kind eq 'taskbar' ? 4 : $oldInset);
        die "taskbar padding damaged drawing state\n" if
            grep { $reg{$_} != $before{$_} } qw(ax bx cx si di ds es);
        die "taskbar padding changed vertical inset or left parent locked\n" if value('dh') != 2 || $parentLocked;
    }
}
# Native moniker arguments copy that inset to both sides before clipping.
my $drawMoniker = source('CButton/copenButtonCommon.asm');
my $clipMoniker = source('CUtils/copenMoniker.asm');
die "taskbar side insets do not reach native clipping\n" unless
    $drawMoniker =~ /mov\s+ss:\[bp\].OMA_leftInset, dx/ &&
    $drawMoniker =~ /mov\s+ss:\[bp\].OMA_rightInset, dx/ &&
    $clipMoniker =~ /sub\s+cx, ss:\[bp\].OMA_rightInset/ &&
    $clipMoniker =~ /sub\s+cx, ss:\[bp\].OMA_leftInset/;
print "ISUI / ISUI 2000 / Motif taskbar horizontal padding checks passed\n";
