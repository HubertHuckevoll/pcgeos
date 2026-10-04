#!/usr/bin/env perl
# Run the actual path-rendering boundary and cleanup with heap checks.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

sub read_source {
    open my $in, '<:raw', "$FindBin::Bin/../$_[0]" or die $!;
    return do { local $/; <$in> };
}
my $header = read_source('svg.h');
my $parser = read_source('svg.goc');
my $path = read_source('svgPath.goc');
my ($scratch) = $header =~ /(typedef struct _SVGScratch \{.*?\} SVGScratch;)/s;
my ($cleanup) = $parser =~ /(void SvgScratchFree\(.*?)(?=Boolean SvgScratchEnsureTagCapacity)/s;
my ($finish) = $path =~ /(    if \(buildingCompound\) \{.*?\n\})\s*\z/s;
die "Missing scratch code\n" unless $scratch && $cleanup && $finish;

my $dir = tempdir(CLEANUP => 1);
open my $out, '>', "$dir/check.c" or die $!;
print {$out} <<'C';
#include <assert.h>
#include <stddef.h>
#include <string.h>
typedef unsigned short word, MemHandle;
typedef int Boolean, SvgScratchFailure;
typedef struct { short x, y; } Point;
typedef struct { long x, y; } SvgWWPoint;
#define SVG_SCRATCH_OK 0
#define LOGF(args) ((void)0)
C
print {$out} $scratch;
print {$out} <<'C';
static unsigned char storage[4][sizeof(SvgWWPoint)];
static int present[4], locked[4], rendered, expectedFill, expectedStroke;
static void MemUnlock(MemHandle h)
{
    assert(h >= 1 && h <= 4 && present[h-1] && locked[h-1]);
    locked[h-1] = 0;
}
static void MemFree(MemHandle h)
{
    assert(h >= 1 && h <= 4 && present[h-1] && !locked[h-1]);
    present[h-1] = 0;
}
static void SvgRendererEndPath(SVGScratch *sc, Boolean fill, Boolean stroke)
{
    int i;
    assert(!sc->tagP && !sc->dbP && !sc->ptsP && !sc->ptsWWFP);
    for (i = 0; i < 4; i++) {
        assert(!locked[i]);
        /* Model output allocations reusing the old unlocked addresses. */
        memset(storage[i], 0xa5, sizeof(storage[i]));
    }
    assert(fill == expectedFill && stroke == expectedStroke);
    rendered++;
}
C
print {$out} $cleanup;
print {$out} <<'C';
static Boolean finish(SVGScratch *sc, Boolean buildingCompound,
                      Boolean valid, Boolean pathHasStroke)
{
    SVGScratch *contextP = sc; /* renderer shim also checks cleared pointers */
    Boolean pathHasFill = 1;
C
print {$out} $finish, "\n";
print {$out} <<'C';
#define INIT(h,p,c,t,i) \
    state = states % 3; states /= 3; \
    present[i] = state != 0; locked[i] = state == 2; \
    sc.h = present[i] ? i+1 : 0; \
    sc.p = locked[i] ? (t *)storage[i] : (void*)0; \
    sc.c = present[i] ? 1 : 0
int main(void)
{
    SVGScratch sc;
    int mask, mode, states, state, i, result;
    for (mask = 0; mask < 81; mask++) {
        for (mode = 0; mode < 16; mode++) {
            memset(&sc, 0, sizeof(sc));
            states = mask;
            INIT(tagH, tagP, tagCapacity, char, 0);
            INIT(dbH, dbP, dbCapacity, char, 1);
            INIT(ptsH, ptsP, ptsCapacity, Point, 2);
            INIT(ptsWWFH, ptsWWFP, ptsWWFCapacity, SvgWWPoint, 3);
            sc.failure = (mode >> 3) & 1;
            expectedFill = (mode >> 1) & 1;
            expectedStroke = expectedFill && ((mode >> 2) & 1);
            rendered = 0;
            result = finish(&sc, mode & 1, expectedFill, (mode >> 2) & 1);
            assert(result == (expectedFill && !sc.failure));
            assert(rendered == (mode & 1));
            SvgScratchFree(&sc);
            SvgScratchFree(&sc);
            for (i = 0; i < 4; i++) assert(!present[i] && !locked[i]);
        }
    }
    return 0;
}
C
close $out or die $!;
system('cc', '-std=c89', '-Wall', '-Wextra', '-Werror', "$dir/check.c",
       '-o', "$dir/check") == 0 or die "Compile failed\n";
system("$dir/check") == 0 or die "Scratch check failed\n";
print "SVG path scratch checks passed (1296 cases)\n";
