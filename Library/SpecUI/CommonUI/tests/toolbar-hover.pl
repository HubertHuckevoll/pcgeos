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
          source('CItem/citemItemColor.asm') . source('CComp/copenCtrlCommon.asm');
my $displayGroup = source('CWin/cwinDisplayControl.asm');
$displayGroup =~ /^else\n\nOLDisplayGroupDraw[^\n]*\n(.*?)^OLDisplayGroupDraw\s+endp/ms
    or die "display-group paint path missing\n";
my $groupDraw = $1;

$groupDraw =~ s/GOTO\s+GrFillRect/call GrFillRect\nret/;
$asm .= "\nDisplayGroupFrame proc near\n$groupDraw\nDisplayGroupFrame endp\n";
my %constant = (TRUE => -1, C_BLACK => 0, C_LIGHT_GRAY => 7, C_DARK_GRAY => 8, C_GRAY_27 => 20, DC_GRAY_1 => 1, C_WHITE => 15, SDM_100 => 0, SDM_50 => 6,
    'mask VA_FULLY_ENABLED' => 0x80, 'mask MF_CALL' => 1,
    'mask MF_FIXUP_DS' => 2, 'mask VOF_IMAGE_INVALID' => 4,
    VUM_DELAYED_VIA_UI_QUEUE => 1, MSG_OL_BUTTON_SET_TOOLBOX_HOVER => 123,
    MSG_OL_WIN_SET_TOOLBOX_HOVER => 124, MSG_VIS_VUP_FIND_OBJECT_OF_CLASS => 125,
    'segment OLWinClass' => 20, 'offset OLWinClass' => 30,
    'segment TaskBarListClass' => 21, 'offset TaskBarListClass' => 31);
for my $record (qw(OLButtonSpecState OLButtonMoreAttrs OLButtonFixedAttrs OLWinFixedAttr OLDisplayGroupStates)) {
    my $file = $record eq 'OLDisplayGroupStates' ? 'olDisplayGroupClass.def' :
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
my $isui2000 = 1;
my (%reg, %mem, @frame, @rect, @line, @fill, @invalid, $zero, $carry, $mask, @pen, $bw, $lineColor, $bordered, $areaColor, $faceColor, $parentIsTaskbar, $hasParent, $parentLocked);
$hasParent = 1; $parentIsTaskbar = 1; $parentLocked = 0;
sub value {
    my ($x) = @_;
    $x =~ s/^\s+|\s+$//g;
    return $reg{$x} // 0 if $x =~ /^(?:[abcd]x|[sd]i|bp|[de]s)$/;
    return ($reg{$1 . 'x'} >> ($2 eq 'h' ? 8 : 0)) & 255 if $x =~ /^([abcd])([hl])$/;
    return value($1) * 65536 + value($2) if $x =~ /^(bx|cx)(si|dx)$/;
    return $constant{$x} if exists $constant{$x};
    return $x if $x =~ /^-?\d+$/;
    return value($1) << $2 if $x =~ /^\((.+) shl (\d+)\)$/;
    return value($1) * 16 + value($2) if $x =~ /^ColorScheme <([^,]+),\s*(.+)>$/;
    if ($x =~ / or /) { my $v = 0; $v |= value($_) for split / or /, $x; return $v; }
    return value($1) if $x =~ /^\((.+)\)$/;
    $x =~ s/\[(si|di|bx|bp)\]/'[' . value($1) . ']'/ge;
    return $mem{$x} // 0 if $x =~ /^ds:/;
    die "unknown operand: $x\n";
}
sub assign {
    my ($x, $v) = @_;
    if ($x =~ /^([abcd])([hl])$/) {
        my ($r, $shift) = ($1 . 'x', $2 eq 'h' ? 8 : 0);
        $reg{$r} = (($reg{$r} // 0) & ~(255 << $shift)) | (($v & 255) << $shift);
    } elsif ($x =~ /^(bx|cx)(si|dx)$/) { assign($1, $v >> 16); assign($2, $v & 65535);
    } elsif ($x =~ /^ds:/) {
        $x =~ s/\[(si|di|bx|bp)\]/'[' . value($1) . ']'/ge;
        $mem{$x} = $v;
    } else { $reg{$x} = $v; }
}
sub run {
    my ($name) = @_;
    $asm =~ /^$name\s+(?:proc|method)([^\n]*)\n(.*?)^$name\s+end[pm]/ms or die "missing $name\n";
    my ($declaration, $body) = ($1, $2);
    $body =~ s/\\\n\s*/ /g;
    my $prologue = "$declaration\n$body";
    my @uses = $prologue =~ /(?:^|\s)uses\s+([^;\n]+)/m ? split(/,\s*/, $1) : ();
    my @saved = map { value($_) } @uses;
    my (@code, %label, @stack, @conditions);
    my $active = 1;
    for (split /\n/, $body) {
        s/;.*//; s/^\s+|\s+$//g;
        s/^TABS\s*<(.*?)>/$1/; s/\b(?:LONG|short)\s+//g;
        s/^\s+|\s+$//g;
        if (/^if (.+)$/) {
            my %enabled = (_ISUI => 1, _ISUI2000 => $isui2000, '_MOTIF or _ISUI' => 1, TOOL_AREA_IS_TASK_BAR => 1);
            die "unknown condition $1\n" unless exists $enabled{$1};
            push @conditions, [$active, $enabled{$1}]; $active &&= $enabled{$1}; next;
        } elsif (/^else\b/) { $active = $conditions[-1][0] && !$conditions[-1][1]; next;
        } elsif (/^endif\b/) { $active = (pop @conditions)->[0]; next; }
        next unless $active;
        next if /^(?:$|uses\b|class\b|\.|MSG_)/;
        if (/^([\w\$]+):$/) { $label{$1} = scalar @code; } else { push @code, $_; }
    }
    for (my $i = 0; $i < @code; $i++) {
        my $line = $code[$i];
        if ($line =~ /^(mov(?:dw)?|add|cmp(?:dw)?|test|xchg)\s+(.+?),\s*(.+)$/) {
            my ($op, $a, $b) = ($1, $2, $3);
            my $v = value($b);
            if ($op =~ /^mov/) { assign($a, $v); }
            elsif ($op eq 'add') { assign($a, value($a) + $v); $zero = !value($a); $carry = 0; }
            elsif ($op =~ /^cmp/) { $zero = value($a) == $v; $carry = value($a) < $v; }
            elsif ($op eq 'test') { $zero = !(value($a) & $v); $carry = 0; }
            else { my $old = value($a); assign($a, $v); assign($b, $old); }
        } elsif ($line =~ /^(inc|dec)\s+(.+)$/) {
            my ($op, $a) = ($1, $2); assign($a, value($a) + ($op eq 'inc' ? 1 : -1)); $zero = !value($a);
        } elsif ($line eq 'pushf') { push @stack, [$zero, $carry];
        } elsif ($line eq 'popf') { ($zero, $carry) = @{pop @stack};
        } elsif ($line =~ /^tst\s+(.+)$/) { $zero = !value($1); $carry = 0;
        } elsif ($line =~ /^clr\s+(.+)$/) { assign($_, 0) for split /,\s*/, $1; $zero = 1; $carry = 0;
        } elsif ($line =~ /^(push|pop)\s+(.+)$/) {
            my ($op, @r) = ($1, split /,\s*/, $2);
            if ($op eq 'push') { push @stack, [map { value($_) } @r]; }
            else { my $v = pop @stack or die "stack underflow\n"; assign($r[$_], $v->[$_]) for 0 .. $#r; }
        } elsif ($line =~ /^(jz|je|jnz|jnc|jc|jmp)\s+([\w\$]+)$/) {
            my ($op, $target) = ($1, $2);
            $i = $label{$target} - 1 if $op eq 'jmp' ||
                ($op =~ /^j[ze]$/ ? $zero : $op eq 'jnz' ? !$zero : $op eq 'jc' ? $carry : !$carry);
        } elsif ($line eq 'stc' || $line eq 'clc') { $carry = $line eq 'stc';
        } elsif ($line eq 'ret') { last;
        } elsif ($line =~ /^call\s+(\w+)$/) {
            my $call = $1;
            if ($call eq 'OpenCheckIfBW') { $carry = $bw; }
            elsif ($call eq 'OpenGetBackgroundColor') { $reg{ax} = 0x0707; }
            elsif ($call eq 'GrGetCurPos') { @reg{qw(ax bx)} = @pen; }
            elsif ($call eq 'GrMoveTo') { @pen = @reg{qw(ax bx)}; }
            elsif ($call eq 'GrSetAreaMask') { $mask = value('al'); }
            elsif ($call eq 'GrFillRect') { push @fill, $mask; }
            elsif ($call eq 'GrSetAreaColor') { $areaColor = value('al'); }
            elsif ($call =~ /^GrSet(?:LineMask|TextColor)$/) { }
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
            elsif ($call eq 'OpenGetTextColor') { $carry = 0; }
            elsif ($call eq 'OpenWinCheckIfBordered') { $carry = $bordered; }
            elsif ($call eq 'OpenWinGetBounds') { @reg{qw(ax bx cx dx)} = (0, 0, 100, 80); }
            elsif ($call eq 'FillRectWithBGColors') { $mask = 0; push @fill, 0; @reg{qw(ax bx cx dx)} = (10, 20, 34, 44); }
            elsif ($call eq 'WinDrawBoxFrame') {
                push @frame, $reg{bp} >> 8 == 1 ? 0 : (($reg{bp} & 15) | (($reg{bp} & 240) << 4));
            }
            elsif ($call eq 'VisGetBounds') { @reg{qw(ax bx cx dx)} = (10, 20, 34, 44); }
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
print "ISUI / ISUI 2000 chrome paint and hover checks passed\n";
