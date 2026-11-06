"""App icon and Steam artwork for Keep Living, drawn in the game's signage style.

    python3 tools/brand/make_icon.py        (needs Pillow)

Writes icon.png (1024) and icon_*.png sizes at the repo root, plus
docs/steam/*.png capsule art. The look follows docs/UI_PLAN.md: a backlit
white station sign in a steel frame with a red SOS-style header, the kanji
生 in heavy poster lettering, and KEEP LIVING underneath.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "assets" / "fonts"
DELA = str(FONTS / "DelaGothicOne-Regular.ttf")
GOTHIC_B = str(FONTS / "BIZUDPGothic-Bold.ttf")

RED = (200, 16, 46)
ALERT = (215, 0, 15)
YELLOW = (245, 196, 0)
INK = (30, 34, 38)
WHITE = (246, 244, 238)
STEEL = (150, 156, 162)
STEEL_DARK = (88, 94, 100)
NIGHT = (16, 20, 34)
JR_GREEN = (0, 140, 60)


def fit_font(path, s, max_w, size):
    while size > 6:
        f = ImageFont.truetype(path, size)
        b = f.getbbox(s)
        if b[2] - b[0] <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, size)


def text_center(d, cx, cy, s, font, fill, stroke=0, stroke_fill=None):
    box = d.textbbox((0, 0), s, font=font, stroke_width=stroke)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((cx - w / 2 - box[0], cy - h / 2 - box[1]), s, font=font, fill=fill,
           stroke_width=stroke, stroke_fill=stroke_fill)


def sign(size: int, with_words: bool = True) -> Image.Image:
    S = size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(S * 0.16)
    # steel frame + backlit face
    d.rounded_rectangle((0, 0, S - 1, S - 1), r, fill=STEEL_DARK)
    d.rounded_rectangle((int(S * .025), int(S * .025), S - int(S * .025), S - int(S * .025)), int(r * .85), fill=STEEL)
    m = int(S * .07)
    d.rounded_rectangle((m, m, S - m, S - m), int(r * .55), fill=WHITE)
    # red header block
    hh = int(S * .30)
    d.rounded_rectangle((m, m, S - m, m + hh), int(r * .55), fill=ALERT)
    d.rectangle((m, m + hh // 2, S - m, m + hh), fill=ALERT)
    label = "KEEP LIVING" if with_words else "生きていく"
    hf = fit_font(DELA if with_words else GOTHIC_B, label, (S - 2 * m) * .82, int(S * .12))
    text_center(d, S / 2, m + hh * .52, label, hf, WHITE)
    # 生 in poster lettering: yellow fill, black stroke, on a dark plate
    body_top = m + hh
    cy = body_top + (S - m - body_top) * .5
    f = ImageFont.truetype(DELA, int(S * .50))
    text_center(d, S / 2, cy + S * .01, "生", f, YELLOW, stroke=max(2, int(S * .03)), stroke_fill=INK)
    # screws
    k = r * .62
    for sx in (k, S - k):
        for sy in (k, S - k):
            rr = max(1, int(S * .012))
            d.ellipse((sx - rr, sy - rr, sx + rr, sy + rr), fill=(200, 204, 208))
    return img


def capsule(w: int, h: int) -> Image.Image:
    """Steam capsule: night city gradient, the sign on the left, the title on the right."""
    img = Image.new("RGB", (w, h), NIGHT)
    d = ImageDraw.Draw(img)
    for y in range(h):  # sky gradient, sodium glow at the bottom
        t = y / h
        c = tuple(int(NIGHT[i] * (1 - t) + (60, 40, 50)[i] * t) for i in range(3))
        d.line((0, y, w, y), fill=c)
    # apartment-block windows silhouette
    import random
    rnd = random.Random(3150)
    x = 0
    while x < w:
        bw = rnd.randint(int(w * .06), int(w * .14)); bh = rnd.randint(int(h * .35), int(h * .8))
        d.rectangle((x, h - bh, x + bw, h), fill=(10, 12, 20))
        for wy in range(h - bh + 8, h - 6, max(8, h // 22)):
            for wx in range(x + 6, x + bw - 6, max(8, w // 90)):
                if rnd.random() < .18:
                    d.rectangle((wx, wy, wx + max(2, w // 220), wy + max(2, h // 120)), fill=(255, 214, 140) if rnd.random() < .8 else (190, 230, 255))
        x += bw + rnd.randint(2, 10)
    s = int(h * .78)
    icon = sign(s, with_words=False)
    img.paste(icon, (int(h * .11), (h - s) // 2), icon)
    tx = int(h * .11) + s + int(h * .08)
    title = ImageFont.truetype(DELA, int(h * .22))
    d.text((tx, h * .20), "KEEP", font=title, fill=WHITE, stroke_width=max(2, h // 90), stroke_fill=INK)
    d.text((tx, h * .44), "LIVING", font=title, fill=YELLOW, stroke_width=max(2, h // 90), stroke_fill=INK)
    sub = ImageFont.truetype(GOTHIC_B, int(h * .085))
    d.text((tx, h * .74), "生きていく", font=sub, fill=WHITE)
    return img


def main():
    big = sign(1024)
    big.save(ROOT / "icon.png")
    for s in (16, 32, 64, 128, 256, 512):
        big.resize((s, s), Image.LANCZOS).save(ROOT / "assets" / "brand" / f"icon_{s}.png")
    steam = ROOT / "docs" / "steam"
    steam.mkdir(parents=True, exist_ok=True)
    for name, (w, h) in {"header_capsule_920x430": (920, 430), "small_capsule_462x174": (462, 174),
                         "main_capsule_1232x706": (1232, 706)}.items():
        capsule(w, h).save(steam / f"{name}.png")
    big.convert("RGB").resize((184, 184), Image.LANCZOS).save(steam / "community_icon_184.png")
    print("wrote icon.png, assets/brand/icon_*.png, docs/steam/*.png")


if __name__ == "__main__":
    (ROOT / "assets" / "brand").mkdir(parents=True, exist_ok=True)
    main()
