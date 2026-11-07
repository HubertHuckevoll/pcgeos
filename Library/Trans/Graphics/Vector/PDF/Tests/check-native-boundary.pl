#!/usr/bin/env perl
# Execute the small native dispatch/error branches with distinct input states.
use strict;
use warnings;
use FindBin;
use File::Spec;
my $root = File::Spec->rel2abs("$FindBin::Bin/../../../../../..");
sub source {
    open my $fh, '<', "$root/$_[0]" or die "$root/$_[0]: $!";
    local $/;
    my $text = <$fh>;
    $text =~ s/\r//g;
    return $text;
}
my $graphics = source('Library/Kernel/Graphics/graphicsC.asm');
$graphics =~ /GRGETTEXTMASK\s+proc\s+far\s+mov\s+cx,\s*(\d+)/
    or die "Text mask wrapper not recognized\n";
my $selector = $1;
$graphics =~ /CallLineMaskRoutine\s+proc.*?jcxz\s+(\w+)\s+cmp\s+cx,\s*(\d+)\s+jz\s+(\w+)\s+call\s+(\w+).*?CallLineMaskRoutine\s+endp/s
    or die "Mask dispatch not recognized\n";
my ($zero, $area_value, $area, $other) = ($1, $2, $3, $4);
my $target = $other;
if ($selector == 0 || $selector == $area_value) {
    my $label = $selector == 0 ? $zero : $area;
    $graphics =~ /^\Q$label\E:\s+call\s+(\w+)/m
        or die "Mask dispatch label missing\n";
    $target = $1;
}
my %masks = (GrGetLineMask => 11, GrGetAreaMask => 22, GrGetTextMask => 33);
defined($masks{$target}) && $masks{$target} == 33
    or die "C text getter did not return the independent text mask\n";

my $spool = source('Library/Spool/Process/processThread.asm');
$spool =~ /ExitPrinterDriver proc.*?\.enter[^\n]*\n(.*?)saveJobData:/s
    or die "EndJob error boundary not recognized\n";
my $branch = $1;
$branch =~ s/;[^\n]*//g;
my @instructions = grep /\S/, split /\n/, $branch;
for my $write_error (0, 1) {
    for my $interrupted (0, 1) {
        my ($carry, $recorded, $reported) = (0, 0, 0);
        for my $instruction (@instructions) {
            if ($instruction =~ /call\s+curJob\.SJI_pDriver/) {
                $carry = $write_error;
            } elsif ($instruction =~ /call\s+CheckForErrors/) {
                $carry = $interrupted;
            } elsif ($instruction =~ /call\s+StoppedByError/) {
                $recorded++;
            } elsif ($instruction =~ /call\s+SpoolErrorBox/) {
                $reported++;
            } elsif ($instruction =~ /\b(jc|jnc)\s+saveJobData/) {
                last if $1 eq 'jc' ? $carry : !$carry;
            } elsif ($instruction !~ /^\s*mov\s/) {
                die "Unhandled EndJob instruction: $instruction\n";
            }
        }
        my $expected = $write_error && !$interrupted ? 1 : 0;
        $recorded == $expected && $reported == $expected
            or die "EndJob failed: error=$write_error interrupted=$interrupted\n";
    }
}
print "Native boundary: independent text mask and late EndJob errors passed\n";

# GrGetPath moves the saved transform before BeginPath. Retain its metadata,
# including fill rule and page-coordinate flags, when writing the new header.
my $paths = source('Library/Kernel/Graphics/graphicsPath.asm');
$paths =~ /mov\s+ax, ds:\[si\]\.OBP_combine(.*?)pop\s+di, si/s
    or die "Native path copy not recognized\n";
my $copy = $1;
$copy =~ s/;[^\n]*//g;
my @copy_ops;
while ($copy =~ /(?:mov\s+dx, \{word\} ds:\[si\]\.OBP_flags|mov\s+ax, dx|stosw)/g) {
    push @copy_ops, $&;
}
for my $flags (0..63) {
    my ($ax, $dx, @written) = (1, 0);
    for my $op (@copy_ops) {
        if ($op =~ /OBP_flags/) {$dx=$flags;}
        elsif ($op =~ /mov/) {$ax=$dx;}
        else {push @written,$ax;}
    }
    @written==2 && $written[0]==1 && $written[1]==$flags
        or die "GrGetPath lost section flags $flags\n";
}
print "Native path copy: combine and all fill/coordinate flags preserved\n";

my $pdf_header = source('Library/Trans/Graphics/Vector/PDF/pdfWriter.h');
my $pdf_device = source('Driver/Printer/PDF/pdfDriverInfo.asm');
$pdf_header =~ /#define PDF_DEVICE_DPI (\d+)/ or die "PDF DPI missing\n";
my $dpi = $1;
$pdf_device =~ /pdfGraphics GraphicsProperties <\Q$dpi\E, \Q$dpi\E,/
    or die "PDF device grid differs from advertised printer DPI\n";
$dpi == 300 or die "Update the exact 0.24-point device matrix for changed DPI\n";
print "PDF device grid: 300 dpi agrees with driver properties\n";
