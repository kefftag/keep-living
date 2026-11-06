"""
Keep Living: import settings for the surface textures.

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

for path in sorted(glob.glob(os.path.join(ROOT, "assets", "textures", "*.import"))):
    with open(path) as f:
        text = f.read()
    want = dict(SET)
    want["compress/normal_map"] = "1" if "_normal." in path else "2"
    for key, value in want.items():
        text, n = re.subn(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, value), text, flags=re.M)
        if n == 0:
            text = text.rstrip("\n") + "\n%s=%s\n" % (key, value)
    with open(path, "w") as f:
        f.write(text)
    print("set", os.path.basename(path))
