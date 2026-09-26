#!/usr/bin/env python3
"""Small assert demo for inline image viewport fitting."""

from fractions import Fraction


def fit(width, height, viewport_width, viewport_height, hspace=0, vspace=0):
    hspace = min(hspace, (viewport_width - 1) // 2)
    vspace = min(vspace, (viewport_height - 1) // 2)
    max_width = max(1, viewport_width - 2 * hspace)
    max_height = max(1, viewport_height - 2 * vspace)
    factor = min(Fraction(1), Fraction(max_width, width),
                 Fraction(max_height, height))
    fitted_width = max(1, int(width * factor + Fraction(1, 2)))
    fitted_height = max(1, int(height * factor + Fraction(1, 2)))
    return min(fitted_width, max_width), min(fitted_height, max_height)


assert fit(640, 480, 320, 240) == (320, 240)
assert fit(640, 480, 320, 100) == (133, 100)
assert fit(320, 240, 320, 240) == (320, 240)
assert fit(640, 480, 320, 240, 8, 12) == (288, 216)
assert fit(20, 20, 10, 10, 20, 20) == (2, 2)
assert fit(40000, 60000, 1000, 1000) == (667, 1000)
assert fit(65535, 1, 1, 1) == (1, 1)

print("viewport fit self-check passed")
