#!/usr/bin/env python3
"""Draws icon.png (128x128): a neon pink 'P' mark on Partii's dark purple, no external art.

Run: python3 tools/make-icon.py   (standard library only)
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 128
SS = 4  # supersamples per axis, for smooth edges
BG = (0x12, 0x0A, 0x1F)
FG = (0xFF, 0x3F, 0xA4)


def inside_rounded_square(x, y, r=26):
    cx = min(max(x, r), SIZE - r)
    cy = min(max(y, r), SIZE - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def inside_p(x, y):
    # Stem: a rounded bar on the left.
    stem_l, stem_r, top, bottom = 34, 54, 26, 104
    if stem_l <= x <= stem_r and top <= y <= bottom:
        return True
    # Bowl: a ring centered right of the stem, joined to it.
    cx, cy, outer, inner = 64, 52, 27, 9
    d = math.hypot(x - cx, y - cy)
    if x >= stem_l and inner <= d <= outer and (x >= cx or abs(y - cy) >= inner):
        return True
    # Fill between the stem and the ring's left half (top and bottom bars).
    if stem_r <= x <= cx and (cy - outer <= y <= cy - inner or cy + inner <= y <= cy + outer):
        return True
    return False


def pixel(px, py):
    bg = fg = 0
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            if inside_rounded_square(x, y):
                if inside_p(x, y):
                    fg += 1
                else:
                    bg += 1
    n = SS * SS
    alpha = (bg + fg) / n
    if alpha == 0:
        return (0, 0, 0, 0)
    t = fg / (bg + fg)
    rgb = tuple(round(BG[i] * (1 - t) + FG[i] * t) for i in range(3))
    return (*rgb, round(alpha * 255))


def png(path):
    rows = b""
    for y in range(SIZE):
        rows += b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(SIZE))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(rows, 9))
    out += chunk(b"IEND", b"")
    Path(path).write_bytes(out)


if __name__ == "__main__":
    target = Path(__file__).resolve().parent.parent / "icon.png"
    png(target)
    print(f"wrote {target}")
