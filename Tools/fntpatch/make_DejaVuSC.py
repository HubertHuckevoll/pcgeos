#!/usr/bin/env python3
"""Generate a PC/GEOS BSWF bitmap font from a redistributable TrueType font.

This is a new-font generator, unlike fntpatch (which only patches fixed-size glyphs).
Uses GEOS's character order and hinted monochrome rasterization.
"""
import argparse
from pathlib import Path
import struct

from PIL import Image, ImageDraw, ImageFont

FIRST = 32
LAST = 255
CHAR_COUNT = LAST - FIRST + 1
FONTBUF_SIZE = 71
CHAR_ENTRY_SIZE = 8
FONT_ID_DEFAULT = 0x022c  # FID_DEJAVUSC on the ISUI2000 product branch
# Differences from modern MacRoman; see TrueType/Adapter/ttcharmapper.c.
GEOS_OVERRIDES = {
    0xc6: "\u0394",  # capital delta
    0xd7: "\u25c6",  # black diamond
    0xde: "\u00fd",  # small y acute, not fi
    0xdf: "\u00dd",  # capital Y acute, not fl
}


def wbfixed(value):
    """GEOS WBFixed stores a fractional byte before the integral LE word."""
    value = max(0, float(value))
    whole = int(value)
    frac = min(255, int(round((value - whole) * 256)))
    if frac == 256:
        whole += 1
        frac = 0
    if whole > 65535:
        raise ValueError("WBFixed out of range")
    return struct.pack("<BH", frac, whole)


def render_glyph(font, ascent, char, canvas, origin, top):
    # MacRoman has Apple's private-use logo at 0xF0, not in DejaVu.
    if 0xe000 <= ord(char) <= 0xf8ff:
        return None
    left, right = font.getbbox(char, mode="1", anchor="ls")[::2]
    advance = font.getlength(char, mode="1")
    canvas = canvas.crop((origin + left, 0, origin + max(left + 1, right), canvas.height))
    ink = canvas.getbbox()
    if ink is None:
        return (advance, 0, 0, 0, 0, b"")
    x1, y1, x2, y2 = ink
    iw, ih = x2 - x1, y2 - y1
    xoff = left + x1
    yoff = ascent + top + y1
    if not (0 <= iw <= 255 and 0 <= ih <= 255 and -128 <= xoff <= 127 and -128 <= yoff <= 127):
        raise ValueError("glyph exceeds GEOS bitmap limits: U+%04X" % ord(char))
    bits = bytearray(((iw + 7) // 8) * ih)
    pix = canvas.load()
    pitch = (iw + 7) // 8
    for y in range(ih):
        for x in range(iw):
            if pix[x1 + x, y1 + y]:
                bits[y * pitch + x // 8] |= 0x80 >> (x % 8)
    return (advance, iw, ih, xoff, yoff, bytes(bits))


def build_strike(ttf_path, point_size, dpi):
    pixels = int(round(point_size * dpi / 72))
    # BASIC keeps the hinted, whole-pixel advances used by GEOS bitmaps.
    font = ImageFont.truetype(str(ttf_path), pixels,
                             layout_engine=ImageFont.Layout.BASIC)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent
    # Render a single spaced line: standalone Pillow masks can place glyphs
    # differently when outline bounds and hinted bitmap bounds disagree.
    # Modern MacRoman maps C_EURO_CHAR (0xdb) to U+20AC.
    characters = [GEOS_OVERRIDES.get(c, bytes([c]).decode("mac_roman"))
                  for c in range(FIRST, LAST + 1)]
    boxes = [font.getbbox(c, mode="1", anchor="ls") for c in characters]
    space_width = font.getlength(" ", mode="1")
    if space_width <= 0:
        raise ValueError("source font must have a positive space width")
    gap = " " * (int(2 * max(b[2] - b[0] for b in boxes) / space_width) + 1)
    text = gap.join(characters)
    left, top, right, bottom = font.getbbox(text, mode="1", anchor="ls")
    canvas = Image.new("1", (right - left, bottom - top), 0)
    ImageDraw.Draw(canvas).text((-left, -top), text, font=font, anchor="ls", fill=255)
    glyphs = []
    prefix = ""
    for char in characters:
        origin = int(font.getlength(prefix + char, mode="1") -
                     font.getlength(char, mode="1") + 0.5) - left
        glyphs.append(render_glyph(font, ascent, char, canvas, origin, top))
        prefix += char + gap
    widths = [g[0] for g in glyphs if g is not None]
    average_width = sum(widths) / len(widths)
    max_width = max(widths)
    # ATTENTION: These metrics assume Latin UI fonts with flat-baseline n
    # and representative H/x. Other scripts need font-specific metrics.
    normal = glyphs[ord("n") - FIRST]
    baseline = normal[4] + normal[2]
    accent = glyphs[ord("H") - FIRST][4]
    x_height = glyphs[ord("x") - FIRST][2]
    table_end = FONTBUF_SIZE + CHAR_COUNT * CHAR_ENTRY_SIZE
    char_table = bytearray()
    data = bytearray()
    for g in glyphs:
        if g is None:
            # CHAR_NOT_EXIST is 0; CHAR_MISSING (3) is only a threshold.
            char_table += struct.pack("<HBHBH", 0, 0, 0, 8, 0)
            continue
        advance, width, rows, xoff, yoff, pixels_data = g
        glyph_offset = table_end + len(data)
        if glyph_offset > 65535:
            raise ValueError("glyph offsets exceed GEOS 16-bit limit")
        advance_bytes = wbfixed(max(1, advance))
        # CharTableFlags from Include/Internal/fontDr.def.
        flags = ((0x40 if xoff < 0 else 0) |
                 (0x20 if yoff < 0 else 0) |
                 (0x10 if yoff + rows > line_height else 0))
        char_table += (struct.pack("<H", glyph_offset) + advance_bytes +
                       struct.pack("<BH", flags, 0))
        data += struct.pack("<BBbb", width, rows, yoff, xoff) + pixels_data
    strike_size = table_end + len(data)
    if strike_size > 65535:
        raise ValueError("strike exceeds 64 KiB: %d pt" % point_size)
    # FontBuf metrics based on Tools/mkuc/berkeley_09.def (fntpatch branch).
    metrics = [average_width, max_width, 0, line_height, accent,
               x_height, 0, baseline, line_height - baseline, 0]
    header = bytearray(struct.pack("<HH", strike_size, 0))
    for val in metrics:
        header += wbfixed(val)
    header += struct.pack("<HHHBBB", 0, table_end, table_end, FIRST, LAST, 0x3f)
    header += wbfixed(baseline + 1)  # underline from top
    header += wbfixed(1)
    header += wbfixed(max(0, baseline - x_height // 2))
    header += wbfixed(0) + wbfixed(0)
    visible = [g for g in glyphs if g is not None and g[1] and g[2]]
    bounds = (min(g[3] for g in visible), min(g[4] for g in visible),
              max(g[4] + g[2] for g in visible),
              max(g[3] + g[1] for g in visible))
    header += struct.pack("<hhhhHBH", *bounds, line_height, 0, 666)
    if len(header) != FONTBUF_SIZE:
        raise AssertionError("bad FontBuf header: %d" % len(header))
    strike = bytes(header + char_table + data)
    assert len(strike) == strike_size
    return strike, len([g for g in glyphs if g is not None]), pixels


def build_font(ttf, output, name, font_id, sizes, dpi):
    if len(name.encode("ascii")) > 19:
        raise ValueError("GEOS font name must fit 19 ASCII characters")
    if len(sizes) == 0 or len(set(sizes)) != len(sizes):
        raise ValueError("point sizes must be distinct and nonempty")
    name_bytes = name.encode("ascii").ljust(20, b"\0")
    strike_table = bytearray()
    strike_data = bytearray()
    header_size = 41 + len(sizes) * 10
    for pt in sizes:
        strike, total, pixels = build_strike(ttf, pt, dpi)
        position = header_size + len(strike_data)
        strike_table += struct.pack("<B", 0) + wbfixed(pt)
        strike_table += struct.pack("<HI", len(strike), position)
        strike_data += strike
        print("%2d pt (%2d px): %3d glyphs, %5d bytes" % (pt, pixels, total, len(strike)))
    head = struct.pack("<4sHHHHB20sHHHH", b"BSWF", 0x0100, header_size - 8,
                       font_id, 0, 0x81, name_bytes, 35, 35 + len(strike_table), 0, 0)
    assert len(head) == 41
    result = head + strike_table + strike_data
    output.write_bytes(result)
    print("wrote %s (%d bytes)" % (output, len(result)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ttf", type=Path, help="path to DejaVuSansCondensed.ttf")
    parser.add_argument("output", type=Path, help="destination .fnt")
    parser.add_argument("--name", default="DejaVuSC", help="new GEOS family name")
    parser.add_argument("--font-id", type=lambda s: int(s, 0), default=FONT_ID_DEFAULT)
    parser.add_argument("--sizes", default="8,9,10,12,14", help="comma-separated point sizes")
    parser.add_argument("--dpi", type=int, default=80)
    args = parser.parse_args()
    sizes = [int(s) for s in args.sizes.split(",")]
    if not args.ttf.is_file():
        parser.error("source TTF does not exist")
    if args.dpi < 36 or args.dpi > 240 or any(s < 4 or s > 40 for s in sizes):
        parser.error("point sizes or DPI out of supported range")
    if not (0 <= args.font_id <= 65535):
        parser.error("font ID must fit 16 bits")
    build_font(args.ttf, args.output, args.name, args.font_id, sizes, args.dpi)


if __name__ == "__main__":
    main()
