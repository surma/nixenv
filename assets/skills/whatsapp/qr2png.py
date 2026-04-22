#!/usr/bin/env python3
"""Convert a terminal QR code (Unicode half-block characters) to a PNG image.

Reads from a file passed as the first argument (default: /tmp/wa-qr.txt).
Writes the PNG to the path passed as the second argument (default: /tmp/wa-qr.png).

The QR code uses Unicode block characters:
  U+2588 (█) = both rows filled
  U+2580 (▀) = top row filled
  U+2584 (▄) = bottom row filled
  space      = both rows empty

Each text line encodes two pixel rows.
"""

import sys
from PIL import Image, ImageDraw

input_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wa-qr.txt"
output_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/wa-qr.png"

with open(input_path, "r") as f:
    lines = f.readlines()

# Collect QR blocks (contiguous runs of lines containing █)
qr_blocks = []
current_block = []
for line in lines:
    line = line.rstrip("\n")
    if "\u2588" in line:
        current_block.append(line)
    else:
        if current_block:
            qr_blocks.append(current_block)
            current_block = []
if current_block:
    qr_blocks.append(current_block)

if not qr_blocks:
    print("ERROR: no QR code found in input", file=sys.stderr)
    sys.exit(1)

# Use the last complete QR block (the CLI may regenerate QR codes; the
# last one is the most recent and therefore still valid).
qr_lines = qr_blocks[-1]

scale = 8
padding = 40
width = max(len(l) for l in qr_lines)
height = len(qr_lines) * 2

img_w = width * scale + padding * 2
img_h = height * scale + padding * 2
img = Image.new("RGB", (img_w, img_h), "white")
draw = ImageDraw.Draw(img)

for y, line in enumerate(qr_lines):
    for x, ch in enumerate(line):
        px = padding + x * scale
        py_top = padding + y * 2 * scale
        py_bot = padding + (y * 2 + 1) * scale
        if ch == "\u2588":
            draw.rectangle([px, py_top, px + scale - 1, py_bot + scale - 1], fill="black")
        elif ch == "\u2580":
            draw.rectangle([px, py_top, px + scale - 1, py_top + scale - 1], fill="black")
        elif ch == "\u2584":
            draw.rectangle([px, py_bot, px + scale - 1, py_bot + scale - 1], fill="black")

img.save(output_path)
print(f"OK {img.size[0]}x{img.size[1]} ({len(qr_lines)} lines)", file=sys.stderr)
