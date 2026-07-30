#include "../SVG/svgPathSyntax.h"

static int
ExpectValid(const char *dataP)
{
    return SvgPathDataIsValid(dataP);
}

static int
ExpectInvalid(const char *dataP)
{
    return !SvgPathDataIsValid(dataP);
}

int
main(void)
{
    if (!ExpectValid("") ||
        !ExpectValid("M0 0 L10 10 20 20 H3 V4 Z") ||
        !ExpectValid("m.5,-.5 q1 2 3 4 t5 6") ||
        !ExpectValid("M0 0 C1 2 3 4 5 6 S7 8 9 10") ||
        !ExpectValid("M0 0 A5 5 0 0 1 10 10") ||
        !ExpectInvalid("M?") ||
        !ExpectInvalid("M 0 0 L ;") ||
        !ExpectInvalid("M 0") ||
        !ExpectInvalid("M 0 0 X 1 2") ||
        !ExpectInvalid("M 0 0 L 1") ||
        !ExpectInvalid("M 0 0 L 1e 2") ||
        !ExpectInvalid("M 0 0,"))
    {
        return 1;
    }
    return 0;
}
