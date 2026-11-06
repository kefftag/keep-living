"""
Keep Living: surface textures.

Downloads CC0 PBR scans from Poly Haven (https://polyhaven.com, CC0, no
attribution required) at 2K, calibrates their albedo to real-world
reflectance, packs AO + roughness into one ORM map, and generates the
surfaces no scan matches well: the embossed vinyl wallpaper (クロス) found in
almost every Japanese apartment, the unit-bath wall panel, brushed stainless,
the window-patterned building facades and a low-frequency "macro" noise the
surface shader uses to break up tiling.

Output per slot, in assets/textures/:
    <slot>_albedo.jpg   sRGB colour
    <slot>_normal.jpg   OpenGL (Y+) normal map
    <slot>_orm.jpg      R = ambient occlusion, G = roughness, B = metal / mask
plus manifest.json (world size in metres one tile covers, source) and CREDITS.md.

    python3 tools/textures/fetch_textures.py              # everything
    python3 tools/textures/fetch_textures.py floor_wood    # some slots
(needs numpy + pillow)
"""

import io
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageFilter, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
CACHE = os.environ.get("KL_TEX_CACHE", os.path.join(ROOT, ".texcache"))

# slot: (poly haven id, metres per tile, resolution, treatment)
# Treatment:
#   gray      desaturate (keeps 15% of the colour unless sat is given)
#   sat       saturation multiplier
#   mean      target mean albedo in *linear* reflectance (real-world calibration)
#   tint      RGB multiplier applied after calibration
#   rough     (lo, hi) remap of the roughness map
SLOTS = {
    # Light oak laminate フローリング (most Tokyo rentals).
    "floor_wood": ("laminate_floor_02", 1.7, 2048, {"mean": 0.30, "sat": 0.9, "rough": (0.32, 0.6)}),
    # Grey cushion-floor vinyl (CF) in the washroom and toilet: stone-print tiles.
    "floor_cushion": ("grey_tiles", 1.8, 2048, {"gray": True, "sat": 0.1, "mean": 0.36, "rough": (0.35, 0.55)}),
    # Unit bath floor: textured anti-slip FRP tiles, light grey.
    "floor_bath": ("anti_skid_tiles", 1.2, 2048, {"gray": True, "sat": 0.05, "mean": 0.48, "rough": (0.35, 0.6)}),
    # Genkan: dark porcelain stone tiles.
    "floor_genkan": ("granite_tile", 1.8, 2048, {"sat": 0.4, "mean": 0.11, "rough": (0.35, 0.7)}),
    # Shared outdoor corridor: worn concrete.
    "concrete_floor": ("concrete_floor_worn_001", 3.0, 2048, {"sat": 0.35, "mean": 0.22}),
    # Balcony: grey urethane-waterproofed concrete.
    "balcony_floor": ("painted_concrete_02", 3.0, 2048, {"sat": 0.2, "mean": 0.2}),
    # Exterior RC walls / parapets: textured spray-painted concrete.
    "concrete_wall": ("concrete_wall_008", 2.7, 2048, {"gray": True, "sat": 0.25, "mean": 0.45}),
    # Kitchen splashback.
    "tile_white": ("long_white_tiles", 1.27, 2048, {"sat": 0.5, "mean": 0.72, "rough": (0.08, 0.5)}),
    # Furniture veneers.
    "wood_light": ("oak_veneer_01", 1.83, 2048, {"mean": 0.36, "rough": (0.4, 0.65)}),
    "wood": ("cherry_veneer", 1.0, 2048, {"mean": 0.2, "rough": (0.4, 0.65)}),
    "wood_dark": ("black_walnut_veneer_01", 1.0, 2048, {"mean": 0.05, "rough": (0.4, 0.65)}),
    "fabric": ("rough_linen", 0.4, 1024, {"gray": True, "sat": 0.0, "mean": 0.55, "contrast": 0.45, "rough": (0.8, 1.0)}),
    # Streets below.
    "asphalt": ("asphalt_02", 3.0, 1024, {"sat": 0.2, "mean": 0.09, "rough": (0.75, 0.95)}),
    # Building facades (window pattern composited on top, see make_facades).
    "facade_tile_base": ("rectangular_facade_tiles", 2.0, 1024, {}),
}

GENERATED = {
    "wallpaper": 0.6,
    "bath_panel": 0.9,
    "steel_brushed": 0.5,
    "facade_tile": 1.0,   # facades map one texture to 2 bays x 2 floors (see facade.gdshader)
    "facade_paint": 1.0,
    "macro": 8.0,
}

API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "keep-living-texture-fetch/2.0"}


def get(url):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, url.replace("https://", "").replace("/", "_"))
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    with open(path, "wb") as f:
        f.write(data)
    return data


def pick(files, names, res):
    for n in names:
        if n in files:
            entry = files[n].get(res) or files[n].get("2k") or files[n].get("1k")
            for fmt in ("jpg", "png"):
                if fmt in entry:
                    return entry[fmt]["url"]
    return None


# --- colour helpers -----------------------------------------------------------

def to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def arr(img):
    return np.asarray(img, dtype=np.float32) / 255.0


def img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def treat(albedo, opts):
    lin = to_lin(arr(albedo.convert("RGB")))
    lum = lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    sat = opts.get("sat", 0.15 if opts.get("gray") else 1.0)
    lin = lum[..., None] + (lin - lum[..., None]) * sat
    if "mean" in opts:
        lin *= opts["mean"] / max(float(lin.mean()), 1e-4)
    if "contrast" in opts:
        m = lin.mean(axis=(0, 1), keepdims=True)
        lin = m + (lin - m) * opts["contrast"]
    if "tint" in opts:
        lin *= np.array(opts["tint"], dtype=np.float32)
    return img(to_srgb(lin))


def remap(a, lo, hi):
    a0, a1 = np.percentile(a, 1), np.percentile(a, 99)
    a = np.clip((a - a0) / max(a1 - a0, 1e-4), 0, 1)
    return lo + a * (hi - lo)


def save(im, path, size, q=84):
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    im.convert("RGB").save(path, quality=q, optimize=True)


def save_set(slot, albedo, normal, ao, rough, b, size):
    save(img(albedo) if isinstance(albedo, np.ndarray) else albedo, os.path.join(OUT, slot + "_albedo.jpg"), size, 84)
    save(img(normal) if isinstance(normal, np.ndarray) else normal, os.path.join(OUT, slot + "_normal.jpg"), size, 88)
    orm = np.dstack((ao, rough, b))
    save(img(orm), os.path.join(OUT, slot + "_orm.jpg"), size, 86)
    old = os.path.join(OUT, slot + "_rough.jpg")
    for p in (old, old + ".import"):
        if os.path.exists(p):
            os.remove(p)


def fetch(slot, pid, size, opts):
    res = "2k" if size > 1024 else "1k"
    files = json.loads(get(API + pid))
    albedo = Image.open(io.BytesIO(get(pick(files, ("Diffuse", "diff"), res)))).convert("RGB")
    normal = Image.open(io.BytesIO(get(pick(files, ("nor_gl", "Normal"), res)))).convert("RGB")
    rough = arr(ImageOps.grayscale(Image.open(io.BytesIO(get(pick(files, ("Rough", "rough"), res))))))
    ao_url = pick(files, ("AO", "ao"), res)
    ao = arr(ImageOps.grayscale(Image.open(io.BytesIO(get(ao_url))))) if ao_url else np.ones_like(rough)
    if "rough" in opts:
        rough = remap(rough, *opts["rough"])
    albedo = treat(albedo, opts) if opts else albedo
    if slot.endswith("_base"):
        # Raw material for a generated texture: keep it in the cache only.
        return albedo, normal, ao, rough
    save_set(slot, albedo, normal, ao, rough, np.zeros_like(rough), size)
    print("fetched", slot, "<-", pid, res)
    return albedo, normal, ao, rough


# --- generated surfaces --------------------------------------------------------

def height_to_normal(h, strength):
    gy, gx = np.gradient(h)
    n = np.dstack((-gx * strength, gy * strength, np.ones_like(h)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def tileable_noise(size, cells, rng):
    """Smooth value noise that wraps: a small random grid upsampled with wrap."""
    small = rng.random((cells, cells)).astype(np.float32)
    big = np.tile(small, (3, 3))
    up = Image.fromarray(big).resize((size * 3, size * 3), Image.BICUBIC)
    return np.asarray(up, dtype=np.float32)[size:2 * size, size:2 * size]


def fbm(size, rng, base, octaves, gain=0.5):
    h = np.zeros((size, size), np.float32)
    amp, tot = 1.0, 0.0
    c = base
    for _ in range(octaves):
        if c > size:
            break
        h += tileable_noise(size, c, rng) * amp
        tot += amp
        amp *= gain
        c *= 2
    return h / tot


def norm01(h):
    return (h - h.min()) / (h.max() - h.min() + 1e-6)


def blur_wrap(a, radius):
    """Gaussian blur that wraps around the edges (keeps tiles seamless)."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * radius) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def make_wallpaper():
    """Japanese vinyl クロス, the 石目調 (stone-grain) emboss: dense fine
    pits and bumps a millimetre or two across, a faint fibrous streak, and
    a very slight warm off-white. Tile = 0.6 m at 2048 px (0.3 mm/px)."""
    rng = np.random.default_rng(1998)
    size = 2048
    fine = fbm(size, rng, 256, 3, 0.55)                       # 1-2 mm grain
    mid = fbm(size, rng, 64, 2, 0.5)                          # 5-10 mm lumps
    # Sparse sharper pits (foamed vinyl bubbles).
    pits = rng.random((size, size)).astype(np.float32)
    pits = (pits > 0.9975).astype(np.float32)
    pits = blur_wrap(pits, 2.2)
    pits /= pits.max()
    # Faint horizontal fibre streaks (print direction).
    streak = tileable_noise(size, 512, rng)
    streak = np.asarray(Image.fromarray(streak).resize((size, 32), Image.BILINEAR).resize((size, size), Image.BILINEAR), np.float32)
    h = fine * 0.5 + mid * 0.4 + streak * 0.08 - pits * 0.15
    h = norm01(h)
    shade = 0.80 + (h - 0.5) * 0.06   # linear reflectance ~0.8
    lin = np.dstack((shade * 1.0, shade * 0.99, shade * 0.965))
    rough = np.clip(0.82 - (h - 0.5) * 0.15, 0, 1)
    ao = np.clip(1.0 - (0.5 - h).clip(0) * 0.5, 0, 1)
    save_set("wallpaper", to_srgb(lin), height_to_normal(h, 4.5), ao, rough, np.zeros_like(h), size)
    print("generated wallpaper")


def make_bath_panel():
    """Unit-bath wall panel: printed steel/FRP, faint marble-ish fleck, satin."""
    rng = np.random.default_rng(1216)
    size = 1024
    h = fbm(size, rng, 128, 3, 0.5)
    vein = norm01(fbm(size, rng, 6, 4, 0.6))
    vein = np.exp(-((vein - 0.5) ** 2) / 0.002)
    shade = 0.74 + (fbm(size, rng, 8, 3) - 0.5) * 0.03 - vein * 0.03
    lin = np.dstack((shade * 1.0, shade * 0.985, shade * 0.95))
    rough = np.clip(0.28 + (h - 0.5) * 0.08, 0, 1)
    save_set("bath_panel", to_srgb(lin), height_to_normal(h, 1.5), np.ones_like(h), rough, np.zeros_like(h), size)
    print("generated bath_panel")


def make_steel():
    """Brushed stainless (sink, worktop, hood): fine horizontal brush lines.
    Albedo is the metal's F0 (~0.6 linear), the game sets metallic = 1."""
    rng = np.random.default_rng(304)
    size = 1024
    lines = rng.random((size, 1)).astype(np.float32)
    lines = np.repeat(lines, size, axis=1)
    lines = blur_wrap(lines + rng.random((size, size)).astype(np.float32) * 0.15, 0.6)
    # Stretch noise along X so streaks run horizontally.
    streak = tileable_noise(size, 256, rng)
    streak = np.asarray(Image.fromarray(streak).resize((8, size), Image.BILINEAR).resize((size, size), Image.BILINEAR), np.float32)
    h = norm01(lines * 0.6 + streak * 0.4)
    smudge = fbm(size, rng, 6, 3)
    lin_v = 0.58 + (h - 0.5) * 0.06 + (smudge - 0.5) * 0.04
    lin = np.dstack((lin_v * 1.0, lin_v * 0.985, lin_v * 0.96))
    rough = np.clip(0.26 + (h - 0.5) * 0.12 + (smudge - 0.5) * 0.12, 0.08, 1)
    save_set("steel_brushed", to_srgb(lin), height_to_normal(h, 1.2), np.ones_like(h), rough, np.ones_like(h), size)
    print("generated steel_brushed")


def make_macro():
    """Low-frequency tileable noise for breaking up repetition on big
    surfaces. R/G/B = three independent octaves (used as tone, dirt, rough)."""
    rng = np.random.default_rng(77)
    size = 512
    chans = [norm01(fbm(size, rng, b, 4, 0.55)) for b in (3, 5, 8)]
    a = np.dstack(chans)
    img(a).save(os.path.join(OUT, "macro.png"), optimize=True)
    print("generated macro")


def make_facades(tile_base):
    """Facades for the skyline: one texture = 2 bays x 2 floors.
    B channel of the ORM is the window-glass mask (lit windows at night).

    facade_tile:  45-二丁掛 tile cladding with punched aluminium windows
                  (corridor side of a mansion block).
    facade_paint: painted concrete with continuous balconies: slab edge,
                  parapet, dark sliding windows behind (balcony side)."""
    size = 1024
    rng = np.random.default_rng(29)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / size  # 0..1, y down
    # Each half (bay x floor) of the texture is one unit.
    fx = (xs * 2) % 1.0
    fy = (ys * 2) % 1.0   # 0 = top of the floor, 1 = floor level

    def box(x0, x1, y0, y1):
        return ((fx >= x0) & (fx < x1) & (fy >= y0) & (fy < y1)).astype(np.float32)

    # --- tile facade ---
    alb_t, nor_t, ao_t, rough_t = tile_base
    base = to_lin(arr(alb_t.resize((size, size), Image.LANCZOS)))
    lum = base @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    base = lum[..., None] + (base - lum[..., None]) * 0.6
    base *= 0.16 / base.mean()
    base *= np.array([1.05, 0.97, 0.88], np.float32)  # warm brown-grey tile
    nrm = arr(nor_t.resize((size, size), Image.LANCZOS))
    rough = np.asarray(Image.fromarray(rough_t).resize((size, size)), np.float32) if isinstance(rough_t, np.ndarray) else np.full((size, size), 0.7, np.float32)
    glass = box(0.18, 0.82, 0.18, 0.62)
    frame = box(0.16, 0.84, 0.16, 0.64) - glass
    sill = box(0.15, 0.85, 0.64, 0.67)
    mull = box(0.495, 0.505, 0.18, 0.62) * glass
    win_col = np.array([0.025, 0.03, 0.035], np.float32)
    var = (tileable_noise(size, 4, rng)[..., None] - 0.5) * 0.02
    lin = base * (1 - frame - sill - glass)[..., None]
    lin += frame[..., None] * np.array([0.33, 0.33, 0.32]) + sill[..., None] * 0.3
    lin += (glass - mull)[..., None] * (win_col + var) + mull[..., None] * 0.3
    flat = np.array([0.5, 0.5, 1.0], np.float32)
    keep = (1 - frame - sill - glass)[..., None]
    nrm = nrm * keep + flat * (1 - keep)
    r = rough * keep[..., 0] + (frame + sill) * 0.35 + glass * 0.05
    save_set("facade_tile", to_srgb(lin), nrm, np.ones_like(r), r, glass - mull, size)

    # --- painted concrete with balconies ---
    rng = np.random.default_rng(31)
    paint = 0.5 + (fbm(size, rng, 64, 3) - 0.5) * 0.04
    dirt = fbm(size, rng, 4, 3)
    slab = box(0.0, 1.0, 0.0, 0.07)               # slab edge band at the top of each floor
    parapet = box(0.0, 1.0, 0.63, 1.0)            # balcony parapet (top 1.1 m of the next floor's view)
    divider = box(0.0, 0.03, 0.07, 0.63)          # partition walls between units
    glassb = box(0.08, 0.92, 0.1, 0.6) * (1 - divider)
    frameb = box(0.07, 0.93, 0.09, 0.61) - glassb
    mullb = (box(0.495, 0.505, 0.1, 0.6) + box(0.29, 0.3, 0.1, 0.6) + box(0.7, 0.71, 0.1, 0.6)) * glassb
    recess = np.clip(1 - slab - parapet - divider - glassb - frameb, 0, 1)  # soffit wall inside the balcony
    grime = (1 - fy * 0.0) * (dirt - 0.5) * 0.08
    v = paint + grime
    lin = np.dstack((v, v * 0.985, v * 0.95))
    lin = lin * (slab + parapet + divider)[..., None] + lin * 0.35 * recess[..., None]
    lin += frameb[..., None] * 0.3 + (glassb - mullb)[..., None] * win_col + mullb[..., None] * 0.3
    # parapet drip stains under the slab
    stain = np.clip((fy - 0.63) * 6, 0, 1) * parapet * (tileable_noise(size, 96, rng) > 0.7) * 0.05
    lin -= stain[..., None]
    ph = fbm(size, rng, 128, 2)
    hgt = ph * 0.3 * (slab + parapet) + (slab + parapet) * 0.6 + divider * 0.6
    nrm = height_to_normal(blur_wrap(hgt.astype(np.float32), 1.0), 18.0)
    r = (slab + parapet + divider + recess) * 0.85 + frameb * 0.4 + glassb * 0.05
    save_set("facade_paint", to_srgb(lin), nrm, np.ones_like(r), np.clip(r, 0, 1), glassb - mullb, size)
    print("generated facades")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    manifest = {}
    bases = {}
    for slot, (pid, metres, size, opts) in SLOTS.items():
        if not slot.endswith("_base"):
            manifest[slot] = {"size": metres, "res": size, "source": "polyhaven:" + pid}
        if only and slot not in only and not (slot.endswith("_base") and any(o.startswith("facade") for o in only)):
            continue
        bases[slot] = fetch(slot, pid, size, opts)
    for slot, metres in GENERATED.items():
        src = "generated"
        if slot == "facade_tile":
            src = "generated over polyhaven:rectangular_facade_tiles"
        elif slot == "facade_paint":
            src = "generated"
        manifest[slot] = {"size": metres, "source": src}
    gens = {
        "wallpaper": make_wallpaper, "bath_panel": make_bath_panel, "steel_brushed": make_steel,
        "macro": make_macro,
    }
    for slot, fn in gens.items():
        if not only or slot in only:
            fn()
    if not only or any(o.startswith("facade") for o in only):
        make_facades(bases["facade_tile_base"])
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Texture credits\n\nAll photo textures are CC0 scans from [Poly Haven](https://polyhaven.com) "
                "(2K, albedo re-calibrated to real-world reflectance, AO + roughness packed as `<slot>_orm.jpg`). "
                "Generated sets are made by `tools/textures/fetch_textures.py`.\n\n")
        for slot, info in manifest.items():
            f.write("- `%s`: %s (%.2f m per tile)\n" % (slot, info["source"], info["size"]))


if __name__ == "__main__":
    main()
