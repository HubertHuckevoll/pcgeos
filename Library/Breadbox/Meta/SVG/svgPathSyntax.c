#include "svgPathSyntax.h"

static int
SvgPathIsSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static int
SvgPathIsAlpha(char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

static int
SvgPathIsDigit(char c)
{
    return c >= '0' && c <= '9';
}

static const char *
SvgPathSkipSeparator(const char *dataP)
{
    while (SvgPathIsSpace(*dataP))
    {
        dataP++;
    }
    if (*dataP == ',')
    {
        dataP++;
        while (SvgPathIsSpace(*dataP))
        {
            dataP++;
        }
    }
    return dataP;
}

static int
SvgPathParamCount(char command)
{
    switch (command)
    {
    case 'M': case 'm':
    case 'L': case 'l':
    case 'T': case 't':
        return 2;
    case 'H': case 'h':
    case 'V': case 'v':
        return 1;
    case 'Q': case 'q':
    case 'S': case 's':
        return 4;
    case 'C': case 'c':
        return 6;
    case 'A': case 'a':
        return 7;
    case 'Z': case 'z':
        return 0;
    default:
        return -1;
    }
}

static int
SvgPathValidateNumber(const char **dataPP)
{
    const char *dataP;
    int haveDigit;

    dataP = *dataPP;
    if (*dataP == '+' || *dataP == '-')
    {
        dataP++;
    }

    haveDigit = 0;
    while (SvgPathIsDigit(*dataP))
    {
        haveDigit = 1;
        dataP++;
    }
    if (*dataP == '.')
    {
        dataP++;
        while (SvgPathIsDigit(*dataP))
        {
            haveDigit = 1;
            dataP++;
        }
    }
    if (!haveDigit)
    {
        return 0;
    }

    if (*dataP == 'e' || *dataP == 'E')
    {
        dataP++;
        if (*dataP == '+' || *dataP == '-')
        {
            dataP++;
        }
        if (!SvgPathIsDigit(*dataP))
        {
            return 0;
        }
        while (SvgPathIsDigit(*dataP))
        {
            dataP++;
        }
    }

    *dataPP = dataP;
    return 1;
}

int
SvgPathDataIsValid(const char *dataP)
{
    char command;
    int count;
    int i;

    command = 0;
    for (;;)
    {
        while (SvgPathIsSpace(*dataP))
        {
            dataP++;
        }
        if (!*dataP)
        {
            return 1;
        }

        if (SvgPathIsAlpha(*dataP))
        {
            command = *dataP++;
            count = SvgPathParamCount(command);
            if (count < 0)
            {
                return 0;
            }
            if (count == 0)
            {
                command = 0;
                continue;
            }
        }
        else
        {
            if (command == 0)
            {
                return 0;
            }
            count = SvgPathParamCount(command);
        }

        for (i = 0; i < count; i++)
        {
            dataP = SvgPathSkipSeparator(dataP);
            if (!SvgPathValidateNumber(&dataP))
            {
                return 0;
            }
        }
    }
}
