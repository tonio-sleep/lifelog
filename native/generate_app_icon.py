#!/usr/bin/env python3
"""Generate the 1024x1024 Lifelog app icon without external dependencies."""
from pathlib import Path
import struct
import zlib

SIZE = 1024
BACKGROUND = (245, 241, 232, 255)  # warm paper
ACCENT = (168, 79, 58, 255)        # terracotta
INK = (253, 251, 246, 255)         # cream page lines

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "Lifelog" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"


def distance_to_segment(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return ((px - x1) ** 2 + (py - y1) ** 2) ** 0.5
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
    cx, cy = x1 + t * dx, y1 + t * dy
    return ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5


def pixel(x, y):
    cx, cy = 512, 512
    radius = 312
    inside = (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
    if not inside:
        return BACKGROUND

    lines = [
        (360, 410, 664, 410),
        (360, 512, 612, 512),
        (360, 614, 680, 614),
    ]
    for line in lines:
        if distance_to_segment(x, y, *line) <= 17:
            return INK
    return ACCENT


def png_chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG filter: none
        for x in range(SIZE):
            rows.extend(pixel(x, y))

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(png_chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)))
    png.extend(png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
    png.extend(png_chunk(b"IEND", b""))
    OUTPUT.write_bytes(png)
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
