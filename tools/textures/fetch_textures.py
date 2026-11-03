"""
Keep Living: surface textures.

Downloads CC0 PBR textures from Poly Haven (https://polyhaven.com, CC0, no
attribution required) at 1k, optionally re-tones them, and generates the
embossed vinyl wallpaper (クロス) found in almost every Japanese apartment.

Output: assets/textures/<slot>_albedo.jpg, <slot>_normal.jpg, <slot>_rough.jpg
plus assets/textures/manifest.json (world size in metres for each slot, which
the game uses for triplanar scale).

    python3 tools/textures/fetch_textures.py
"""

import io
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
RES = "1k"

# slot: (polyhaven id, world size in metres, treatment)
# treatment: gray = desaturate (so the game can tint), gain = brightness multiplier
SLOTS = {
    "floor_wood": ("laminate_floor_03", 2.08, {}),
    "floor_genkan": ("rubber_tiles", 2.0, {"gray": True, "gain": 1.9}),
    "floor_cushion": ("floor_tiles_04", 2.0, {"gray": True, "gain": 1.25}),
    "floor_bath": ("anti_skid_tiles", 1.8, {"gray": True, "gain": 1.6}),
    "concrete_floor": ("concrete_floor_worn_001", 2.5, {}),
    "concrete_wall": ("concrete_wall_008", 2.7, {"gray": True, "gain": 1.05}),
    "tile_white": ("long_white_tiles", 1.2, {}),
    "wood_light": ("oak_veneer_01", 1.0, {}),
    "wood": ("cherry_veneer", 1.0, {}),
    "wood_dark": ("black_walnut_veneer_01", 1.0, {"gain": 0.55}),
    "fabric": ("rough_linen", 0.6, {"gray": True, "gain": 1.3}),
}

API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "keep-living-texture-fetch/1.0"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def pick(files, *names):
    for n in names:
        if n in files:
            entry = files[n].get(RES) or files[n].get("2k")
            for fmt in ("jpg", "png"):
                if fmt in entry:
                    return entry[fmt]["url"]
    raise KeyError(names)


def save(img, path, size=1024):
    img = img.convert("RGB").resize((size, size), Image.LANCZOS)
    img.save(path, quality=88)


def treat(albedo, opts):
    if opts.get("gray"):
        albedo = ImageOps.grayscale(albedo).convert("RGB")
    if "gain" in opts:
        albedo = ImageEnhance.Brightness(albedo).enhance(opts["gain"])
    return albedo


def fetch(slot, pid, opts):
    files = json.loads(get(API + pid))
    albedo = Image.open(io.BytesIO(get(pick(files, "Diffuse", "diff")))).convert("RGB")
    normal = Image.open(io.BytesIO(get(pick(files, "nor_gl", "Normal"))))
    rough = Image.open(io.BytesIO(get(pick(files, "Rough", "rough"))))
    save(treat(albedo, opts), os.path.join(OUT, slot + "_albedo.jpg"))
    save(normal, os.path.join(OUT, slot + "_normal.jpg"))
    save(ImageOps.grayscale(rough), os.path.join(OUT, slot + "_rough.jpg"))
    print("fetched", slot, "<-", pid)


def height_to_normal(h, strength):
    gy, gx = np.gradient(h)
    n = np.dstack((-gx * strength, gy * strength, np.ones_like(h)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))


def tileable_noise(size, scale, rng):
    """Smooth noise that wraps, by upsampling a small random grid with wrap."""
    small = rng.random((scale, scale))
    big = np.tile(small, (3, 3))
    img = Image.fromarray((big * 255).astype(np.uint8)).resize((size * 3, size * 3), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32)[size:2 * size, size:2 * size] / 255.0
    return a


def make_wallpaper():
    """Embossed white vinyl wallpaper: a fine, slightly woven bumpy surface."""
    rng = np.random.default_rng(1998)
    size = 1024
    h = (tileable_noise(size, 256, rng) * 0.5 + tileable_noise(size, 96, rng) * 0.3
         + tileable_noise(size, 32, rng) * 0.2)
    # Faint horizontal/vertical weave typical of 織物調 wallpaper.
    y, x = np.mgrid[0:size, 0:size]
    h += 0.05 * (np.sin(x * 2 * np.pi / 8) + np.sin(y * 2 * np.pi / 8))
    h = (h - h.min()) / (h.max() - h.min())
    albedo = np.clip(0.93 + (h - 0.5) * 0.05, 0, 1)
    rgb = np.dstack((albedo * 0.995, albedo * 0.985, albedo * 0.96))
    Image.fromarray((rgb * 255).astype(np.uint8)).save(os.path.join(OUT, "wallpaper_albedo.jpg"), quality=90)
    height_to_normal(h, 6.0).save(os.path.join(OUT, "wallpaper_normal.jpg"), quality=90)
    rough = np.clip(0.75 + (h - 0.5) * 0.2, 0, 1)
    Image.fromarray((rough * 255).astype(np.uint8)).save(os.path.join(OUT, "wallpaper_rough.jpg"), quality=90)
    print("generated wallpaper")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    manifest = {"wallpaper": {"size": 0.5, "source": "generated"}}
    for slot, (pid, size, opts) in SLOTS.items():
        manifest[slot] = {"size": size, "source": "polyhaven:" + pid}
        if only and slot not in only:
            continue
        fetch(slot, pid, opts)
    if not only or "wallpaper" in only:
        make_wallpaper()
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Texture credits\n\nAll photo textures are CC0 from [Poly Haven](https://polyhaven.com). "
                "`wallpaper_*` is generated by `tools/textures/fetch_textures.py`.\n\n")
        for slot, info in manifest.items():
            f.write("- `%s`: %s\n" % (slot, info["source"]))


if __name__ == "__main__":
    main()
