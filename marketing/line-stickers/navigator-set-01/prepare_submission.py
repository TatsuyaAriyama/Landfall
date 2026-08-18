"""Prepare transparent navigator sticker art for LINE Creators Market."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "stickers"
OUTPUT = ROOT / "submission"
STICKER_OUTPUT = OUTPUT / "stickers"
STICKER_SIZE = (370, 320)
SAFE_PADDING = 10


def remove_green_fringe(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    cleaned = []
    for red, green, blue, alpha in image.getdata():
        dominance = green - max(red, blue)
        if alpha == 0 or dominance >= 70:
            cleaned.append((red, green, blue, 0))
            continue
        if dominance > 8:
            alpha = round(alpha * max(0.0, 1.0 - (dominance - 8) / 62.0))
            green = min(green, max(red, blue) + 6)
        cleaned.append((red, green, blue, alpha))
    image.putdata(cleaned)
    return image


def fit_subject(image: Image.Image, size: tuple[int, int], padding: int) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("Source image has no visible subject")
    subject = image.crop(bounds)
    available = (size[0] - padding * 2, size[1] - padding * 2)
    subject.thumbnail(available, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    origin = ((size[0] - subject.width) // 2, (size[1] - subject.height) // 2)
    canvas.alpha_composite(subject, origin)
    return canvas


def upper_body(image: Image.Image) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Source image has no visible subject")
    left, top, right, bottom = bounds
    upper_bottom = top + round((bottom - top) * 0.64)
    return image.crop((left, top, right, upper_bottom))


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, dpi=(72, 72))


def validate(path: Path, expected_size: tuple[int, int]) -> None:
    image = Image.open(path).convert("RGBA")
    if image.size != expected_size:
        raise ValueError(f"{path.name}: unexpected size {image.size}")
    if image.width % 2 or image.height % 2:
        raise ValueError(f"{path.name}: dimensions must be even")
    alpha = image.getchannel("A")
    if any(alpha.getpixel(point) for point in ((0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1))):
        raise ValueError(f"{path.name}: corners must be transparent")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"{path.name}: no visible pixels")
    left, top, right, bottom = bounds
    if min(left, top, image.width - right, image.height - bottom) < SAFE_PADDING:
        raise ValueError(f"{path.name}: insufficient transparent padding")
    if path.stat().st_size > 1_000_000:
        raise ValueError(f"{path.name}: exceeds 1 MB")


def make_preview(stickers: list[Image.Image], destination: Path) -> None:
    tile = (420, 370)
    preview = Image.new("RGB", (tile[0] * 4, tile[1] * 2), "#103a35")
    draw = ImageDraw.Draw(preview)
    for index, sticker in enumerate(stickers):
        x = (index % 4) * tile[0]
        y = (index // 4) * tile[1]
        card = Image.new("RGBA", (tile[0] - 24, tile[1] - 24), "#1d5148")
        art = sticker.copy()
        art.thumbnail((card.width - 20, card.height - 20), Image.Resampling.LANCZOS)
        card.alpha_composite(art, ((card.width - art.width) // 2, (card.height - art.height) // 2))
        preview.paste(card.convert("RGB"), (x + 12, y + 12))
        draw.rounded_rectangle((x + 12, y + 12, x + tile[0] - 12, y + tile[1] - 12), radius=24, outline="#d5b56d", width=3)
    preview.save(destination, quality=92, optimize=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=INPUT)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument(
        "--preview",
        type=Path,
        default=ROOT / "navigator-sticker-set-preview.jpg",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_directory = args.input.resolve()
    output_directory = args.output.resolve()
    sticker_output = output_directory / "stickers"
    output_directory.mkdir(parents=True, exist_ok=True)
    prepared: list[Image.Image] = []
    for index, source in enumerate(sorted(input_directory.glob("*.png")), start=1):
        cleaned = remove_green_fringe(Image.open(source))
        sticker = fit_subject(cleaned, STICKER_SIZE, SAFE_PADDING)
        destination = sticker_output / f"{index:02d}.png"
        save_png(sticker, destination)
        validate(destination, STICKER_SIZE)
        prepared.append(sticker)

    if len(prepared) != 8:
        raise ValueError(f"Expected 8 stickers, found {len(prepared)}")

    main_image = fit_subject(prepared[0], (240, 240), SAFE_PADDING)
    save_png(main_image, output_directory / "main.png")
    validate(output_directory / "main.png", (240, 240))

    tab_image = fit_subject(upper_body(prepared[0]), (96, 74), SAFE_PADDING)
    save_png(tab_image, output_directory / "tab.png")
    validate(output_directory / "tab.png", (96, 74))
    make_preview(prepared, args.preview.resolve())

    print(f"Prepared {len(prepared)} stickers in {output_directory}")


if __name__ == "__main__":
    main()
