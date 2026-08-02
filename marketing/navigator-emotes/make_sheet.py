from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PNG_DIR = ROOT / "png"
OUT = ROOT / "navigator-emotes-all.png"

POSES = [
    ("idle", "待機"),
    ("walk", "歩行"),
    ("lookout", "見張り"),
    ("raise", "灯を掲げる"),
    ("hail", "手を振る"),
    ("point", "指差す"),
    ("stargaze", "星を見る"),
    ("rest", "一息つく"),
    ("sit", "座る"),
]

SIZE = 1800
MARGIN = 36
GAP = 24
CELL = 560
BG = "#120B24"
CARD = "#291B42"
CARD_EDGE = "#5B406F"
CORAL = "#F0997B"
SAND = "#EADEBD"
MUTED = "#A99BB9"

font_candidates = sorted(Path("/System/Library/Fonts").glob("*W8.ttc"))
font_path = str(font_candidates[0]) if font_candidates else "/System/Library/Fonts/Arial Unicode.ttf"
font_ja = ImageFont.truetype(font_path, 34)
font_en = ImageFont.truetype(font_path, 21)

sheet = Image.new("RGB", (SIZE, SIZE), BG)
draw = ImageDraw.Draw(sheet)

for index, (key, label) in enumerate(POSES):
    row, col = divmod(index, 3)
    x = MARGIN + col * (CELL + GAP)
    y = MARGIN + row * (CELL + GAP)

    draw.rounded_rectangle(
        (x, y, x + CELL, y + CELL),
        radius=34,
        fill=CARD,
        outline=CARD_EDGE,
        width=3,
    )
    draw.ellipse(
        (x + 100, y + 55, x + CELL - 100, y + 415),
        fill="#33214F",
    )

    model = Image.open(PNG_DIR / f"navigator-{key}.png").convert("RGBA")
    bbox = model.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError(f"No visible pixels in navigator-{key}.png")
    model = model.crop(bbox)
    max_w, max_h = 430, 410
    scale = min(max_w / model.width, max_h / model.height)
    model = model.resize(
        (round(model.width * scale), round(model.height * scale)),
        Image.Resampling.LANCZOS,
    )
    model_x = x + (CELL - model.width) // 2
    model_y = y + 35 + (410 - model.height) // 2
    sheet.paste(model, (model_x, model_y), model)

    label_box = draw.textbbox((0, 0), label, font=font_ja)
    label_w = label_box[2] - label_box[0]
    draw.text(
        (x + (CELL - label_w) / 2, y + 462),
        label,
        fill=SAND,
        font=font_ja,
    )

    key_box = draw.textbbox((0, 0), key.upper(), font=font_en)
    key_w = key_box[2] - key_box[0]
    draw.text(
        (x + (CELL - key_w) / 2, y + 514),
        key.upper(),
        fill=MUTED,
        font=font_en,
    )
    draw.rounded_rectangle(
        (x + 220, y + 542, x + 340, y + 548),
        radius=3,
        fill=CORAL,
    )

sheet.save(OUT, optimize=True)
print(OUT)
