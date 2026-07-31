#include <assert.h>
#include <stdio.h>

#include "../svgRendererCore.h"

int
main(void)
{
    SvgRendererState state;
    SvgRendererPoint points[] = {
        { 0, 0 }, { 1, 1 }, { 2, 2 }, { 2, 2 }, { 8, 4 }
    };
    SvgRendererWord count;

    assert(SvgRendererCoreChooseDivisor(8191, 0) == 1);
    assert(SvgRendererCoreChooseDivisor(8192, 0) == 2);
    assert(SvgRendererCoreChooseDivisor(16383, 0) == 2);
    assert(SvgRendererCoreChooseDivisor(16384, 0) == 4);

    count = SvgRendererCoreCompact(points, 5, 2);
    assert(count == 3);
    assert(points[0].x == 0 && points[0].y == 0);
    assert(points[1].x == 1 && points[1].y == 1);
    assert(points[2].x == 4 && points[2].y == 2);

    SvgRendererCoreInit(&state, 7);
    assert(state.fillRule == 7);
    SvgRendererCoreSetFillRule(&state, 9);
    assert(state.fillRule == 9);
    assert(SvgRendererCoreBeginPath(&state));
    assert(!SvgRendererCoreBeginPath(&state));
    assert(!SvgRendererCoreEndPath(&state));
    assert(SvgRendererCoreEndPath(&state));
    assert(!SvgRendererCoreEndPath(&state));

    puts("svgrenderer_test: ok");
    return 0;
}
