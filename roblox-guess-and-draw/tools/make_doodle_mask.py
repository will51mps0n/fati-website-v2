"""Turns the green background tile into assets/background-doodles.png: just the
doodle lines, in white on a see-through background. The game tints the lines
and colours the background per theme, so one upload covers every theme.

    python3 tools/make_doodle_mask.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
tile = np.asarray(Image.open(ROOT / "assets/background-tile.png").convert("RGB")).astype(float)
luminance = tile @ np.array([0.299, 0.587, 0.114])
# The green background is about 90 bright and the doodle lines about 49.
alpha = np.clip((86 - luminance) / (86 - 52), 0, 1)
out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
out[..., :3] = 255
out[..., 3] = (alpha * 255).round().astype(np.uint8)
Image.fromarray(out, "RGBA").save(ROOT / "assets/background-doodles.png")
print("wrote assets/background-doodles.png")
