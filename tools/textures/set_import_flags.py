"""
Keep Living: import settings for the surface and model textures.

Godot only switches a texture to mipmapped VRAM compression when the *editor*
sees it used in 3D ("detect 3D"), and this project is mostly run headless, so
the defaults left every surface without mipmaps (shimmering, speckled walls).
This sets them explicitly: VRAM compressed, mipmaps, normal maps flagged as
such. Run after fetch_textures.py and a first `godot --import`, then import again.

    python3 tools/textures/set_import_flags.py
"""

import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

SET = {
    "compress/mode": "2",
    "mipmaps/generate": "true",
    "detect_3d/compress_to": "0",
}

PATTERNS = [
    os.path.join(ROOT, "assets", "textures", "*.import"),
    # Textures extracted from the .glb models (Tripo characters, kit, hands):
    # 2K maps that would otherwise ship uncompressed with no mipmaps (~6 MB each).
    os.path.join(ROOT, "assets", "models", "*.jpg.import"),
    os.path.join(ROOT, "assets", "models", "*.png.import"),
    # Poly Haven scans: assets/models/<name>/textures/*_1k.jpg
    os.path.join(ROOT, "assets", "models", "*", "textures", "*.import"),
]
paths = sorted({p for pat in PATTERNS for p in glob.glob(pat)})
for path in paths:
    with open(path) as f:
        text = f.read()
    want = dict(SET)
    want["compress/normal_map"] = "1" if ("_normal." in path or "_nor_gl" in path or "_nor_dx" in path) else "2"
    # Model textures: furniture, appliances and characters rarely fill more than
    # ~1000 px on a 1080p screen, so cap them at 1K (a quarter of the 2K size).
    # The first-person hands fill much of the screen and keep 2K. Surfaces keep 2K.
    want["process/size_limit"] = "1024" if (os.sep + "models" + os.sep in path and "fp_" not in os.path.basename(path)) else "0"
    for key, value in want.items():
        text, n = re.subn(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, value), text, flags=re.M)
        if n == 0:
            text = text.rstrip("\n") + "\n%s=%s\n" % (key, value)
    with open(path, "w") as f:
        f.write(text)
    print("set", os.path.basename(path))
