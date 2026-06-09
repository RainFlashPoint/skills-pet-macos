#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image


def clean_image(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    width, height = image.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue

            if a < 24:
                pixels[x, y] = (r, g, b, 0)
                continue

            max_channel = max(r, g, b)
            min_channel = min(r, g, b)
            near_white = max_channel > 214 and (max_channel - min_channel) < 28

            if near_white and a < 190:
                a = max(0, a - 110)
                if a < 18:
                    a = 0
            elif a < 90:
                a = max(0, a - 26)

            pixels[x, y] = (r, g, b, a)

    image.save(path)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: clean_sprite_edges.py <png> [<png> ...]")
        return 1

    for arg in argv[1:]:
        path = Path(arg)
        if not path.exists():
            print(f"missing: {path}", file=sys.stderr)
            return 2

        backup = path.with_suffix(path.suffix + ".bak")
        if not backup.exists():
            shutil.copy2(path, backup)
        clean_image(path)
        print(f"cleaned: {path.name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
