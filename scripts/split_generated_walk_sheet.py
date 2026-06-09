#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def remove_checker_background(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            max_channel = max(r, g, b)
            min_channel = min(r, g, b)
            low_chroma = (max_channel - min_channel) < 20

            if low_chroma and min_channel > 215:
                pixels[x, y] = (r, g, b, 0)
            elif low_chroma and min_channel > 190:
                pixels[x, y] = (r, g, b, max(0, a - 180))
            elif low_chroma and min_channel > 165:
                pixels[x, y] = (r, g, b, max(0, a - 90))

    return image


def crop_visible_bounds(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return image
    return image.crop(bbox)


def place_on_canvas(image: Image.Image, canvas_size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    visible = crop_visible_bounds(image)
    x = (canvas.width - visible.width) // 2
    y = canvas.height - visible.height
    canvas.alpha_composite(visible, (x, y))
    return canvas


def split_sheet(sheet_path: Path, out_dir: Path) -> None:
    sheet = Image.open(sheet_path).convert("RGBA")
    columns = 3
    rows = 2
    frame_width = sheet.width // columns
    frame_height = sheet.height // rows

    raw_frames = []
    for row in range(rows):
        for col in range(columns):
            box = (
                col * frame_width,
                row * frame_height,
                (col + 1) * frame_width,
                (row + 1) * frame_height,
            )
            frame = sheet.crop(box)
            frame = remove_checker_background(frame)
            raw_frames.append(crop_visible_bounds(frame))

    max_width = max(frame.width for frame in raw_frames)
    max_height = max(frame.height for frame in raw_frames)
    canvas_size = (max_width + 40, max_height + 24)

    out_dir.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(raw_frames, start=1):
        placed = place_on_canvas(frame, canvas_size)
        target = out_dir / f"cat_walk_gen_{index:02d}.png"
        placed.save(target)
        print(target)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: split_generated_walk_sheet.py <sheet.png> <out_dir>")
        return 1

    split_sheet(Path(argv[1]), Path(argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
