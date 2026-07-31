#include "svgRendererCore.h"

void
SvgRendererCoreInit(SvgRendererState *stateP, SvgRendererWord windingRule)
{
    stateP->fillRule = windingRule;
    stateP->pathDepth = 0;
    stateP->coordinateDivisor = 1;
}

SvgRendererWord
SvgRendererCoreChooseDivisor(SvgRendererSWord width,
                             SvgRendererSWord height)
{
    long maximum;
    long value;

    maximum = width;
    if (maximum < 0) maximum = -maximum;
    value = height;
    if (value < 0) value = -value;
    if (value > maximum) maximum = value;
    return (maximum > 16383L) ? 4 : ((maximum > 8191L) ? 2 : 1);
}

SvgRendererWord
SvgRendererCoreCompact(SvgRendererPoint *pointsP, SvgRendererWord count,
                       SvgRendererWord divisor)
{
    SvgRendererWord source;
    SvgRendererWord destination;
    SvgRendererSWord x;
    SvgRendererSWord y;

    destination = 0;
    for (source = 0; source < count; source++)
    {
        x = (SvgRendererSWord)(pointsP[source].x /
                               (SvgRendererSWord)divisor);
        y = (SvgRendererSWord)(pointsP[source].y /
                               (SvgRendererSWord)divisor);
        if (destination == 0 || pointsP[destination - 1].x != x ||
            pointsP[destination - 1].y != y)
        {
            pointsP[destination].x = x;
            pointsP[destination].y = y;
            destination++;
        }
    }
    return destination;
}

void
SvgRendererCoreSetFillRule(SvgRendererState *stateP,
                           SvgRendererWord fillRule)
{
    stateP->fillRule = fillRule;
}

int
SvgRendererCoreBeginPath(SvgRendererState *stateP)
{
    stateP->pathDepth++;
    return stateP->pathDepth == 1;
}

int
SvgRendererCoreEndPath(SvgRendererState *stateP)
{
    if (stateP->pathDepth == 0) return 0;
    stateP->pathDepth--;
    return stateP->pathDepth == 0;
}
