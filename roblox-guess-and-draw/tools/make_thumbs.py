"""Draws the skribbl.io-style thumbs (chunky pixel art, grey outline, pale fills)
into assets/thumbs-up.png and assets/thumbs-down.png:

    python3 tools/make_thumbs.py assets
"""
import sys
from PIL import Image, ImageDraw
out = sys.argv[1]
N = 48  # drawing grid; scaled up with hard pixels at the end
OUTLINE = (85, 85, 85, 255)

def thumb(fill):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Fist: a rounded block with the fingers' bumps on the right.
    d.rounded_rectangle([12, 20, 40, 42], radius=5, fill=OUTLINE)
    for y in (20, 26, 32, 37):
        d.rounded_rectangle([30, y, 44, y + 6], radius=3, fill=OUTLINE)
    # Thumb sticking up, leaning slightly.
    d.polygon([(15, 22), (19, 5), (24, 3), (26, 7), (24, 20)], fill=OUTLINE)
    d.ellipse([18, 1, 27, 9], fill=OUTLINE)
    # Cuff on the left.
    d.rounded_rectangle([4, 21, 13, 43], radius=2, fill=OUTLINE)
    # Fill: the same shapes, shrunk by the outline width.
    d.rounded_rectangle([14, 22, 38, 40], radius=4, fill=fill)
    for y in (22, 28, 34):
        d.rounded_rectangle([31, y, 42, y + 4], radius=2, fill=fill)
    d.rounded_rectangle([31, 38, 41, 41], radius=1, fill=fill)
    d.polygon([(17, 23), (21, 6), (24, 5), (25, 8), (22, 22)], fill=fill)
    d.ellipse([20, 3, 25, 8], fill=fill)
    d.rounded_rectangle([6, 23, 11, 41], radius=1, fill=fill)
    # Finger lines.
    for y in (27, 33, 38):
        d.line([(33, y), (40, y)], fill=OUTLINE, width=1)
    return img.resize((256, 256), Image.NEAREST)

up = thumb((176, 216, 140, 255))
down = thumb((200, 130, 130, 255)).transpose(Image.FLIP_TOP_BOTTOM).transpose(Image.FLIP_LEFT_RIGHT)
up.save(f"{out}/thumbs-up.png")
down.save(f"{out}/thumbs-down.png")
