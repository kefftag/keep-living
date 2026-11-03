"""
Keep Living: photoscanned / hand-made CC0 models from Poly Haven.

Each slot is saved to assets/models/<slot>/ as glTF (+ .bin + 1k textures).
The game fits these into the slot's in-game box (uniform scale, bottom-centre),
so they don't need to match the size table exactly. Poly Haven assets are CC0.

    python3 tools/models/fetch_models.py            # everything
    python3 tools/models/fetch_models.py tv bat     # some slots
"""

import json
import os
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "keep-living-model-fetch/1.0"}

# slot -> poly haven id
SLOTS = {
    "toolbox": "metal_toolbox",
    "side_table": "side_table_01",
    "ac_outdoor": "exterior_aircon_unit",
    "storage_shelf": "steel_frame_shelves_01",
    "dining_chair": "dining_chair_02",
    # Dressing that sits on/around other furniture.
    "bat": "baseball_bat",
    "binoculars": "binoculars",
    "laptop": "classic_laptop",
    "television": "television_02",
    "alarm_clock": "alarm_clock_01",
    "kettle": "vintage_electric_kettle",
    "water_jug": "plastic_bottle_gallon",
    "trashbag": "trashbag",
    "boots": "rubber_boots",
    "cardboard_box": "cardboard_box_01",
    "plant": "potted_plant_02",
    "wall_clock": "wall_clock",
    "food_cans": "russian_food_cans_01",
    "broom": "plastic_broom",
    "desk_lamp": "desk_lamp_arm_01",
    "pillows": "throw_pillows_01",
}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def fetch(slot, pid, res="1k"):
    files = json.loads(get(API + pid))
    entry = files["gltf"].get(res) or files["gltf"]["2k"]
    gltf = entry["gltf"]
    folder = os.path.join(OUT, slot)
    os.makedirs(folder, exist_ok=True)
    for rel, inc in gltf.get("include", {}).items():
        path = os.path.join(folder, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(get(inc["url"]))
    with open(os.path.join(folder, slot + ".gltf"), "wb") as f:
        f.write(get(gltf["url"]))
    print("fetched", slot, "<-", pid)


def main():
    only = sys.argv[1:]
    for slot, pid in SLOTS.items():
        if only and slot not in only:
            continue
        fetch(slot, pid)
    with open(os.path.join(OUT, "POLYHAVEN_CREDITS.md"), "w") as f:
        f.write("# Model credits\n\nCC0 models from [Poly Haven](https://polyhaven.com), fetched by "
                "`tools/models/fetch_models.py`:\n\n")
        for slot, pid in SLOTS.items():
            f.write("- `%s/`: [%s](https://polyhaven.com/a/%s)\n" % (slot, pid, pid))


if __name__ == "__main__":
    main()
