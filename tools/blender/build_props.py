"""
Keep Living: low-poly prop kit for the apartment.

Builds every prop the game knows about at its exact in-game size and exports
one .glb per prop into assets/models/. Godot picks a model up automatically
when a .glb with the matching name exists (see scripts/world/props.gd).

Conventions (must hold for every model, hand-made or generated):
  * metres, Z up in Blender
  * origin at the bottom-centre of the footprint
  * the FRONT of the object faces Blender -Y  (becomes Godot +Z on export)
  * size matches the table in docs/BLENDER_PIPELINE.md

Run headless:
    blender -b --factory-startup -P tools/blender/build_props.py -- --out assets/models
Run through Blender MCP (execute_blender_code): paste this file, set
OUT_DIR below to the absolute path of the project's assets/models folder,
and optionally set ONLY = ["fridge"] to rebuild a single prop.
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix

OUT_DIR = ""     # set this when running via Blender MCP
ONLY = []        # e.g. ["bed", "zombie"]; empty = everything
EXPORT = True    # False = just build in the scene so you can look at it

# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

PALETTE = {
    "wood": ((0.45, 0.30, 0.18), 0.7, 0.0),
    "wood_light": ((0.66, 0.50, 0.33), 0.7, 0.0),
    "wood_dark": ((0.25, 0.16, 0.10), 0.7, 0.0),
    "white": ((0.86, 0.86, 0.84), 0.6, 0.0),
    "porcelain": ((0.93, 0.94, 0.96), 0.25, 0.0),
    "steel": ((0.62, 0.64, 0.67), 0.35, 0.8),
    "black": ((0.04, 0.04, 0.05), 0.5, 0.0),
    "plastic_grey": ((0.35, 0.36, 0.38), 0.6, 0.0),
    "stone": ((0.30, 0.30, 0.32), 0.5, 0.0),
    "fabric_blue": ((0.20, 0.28, 0.45), 0.9, 0.0),
    "fabric_white": ((0.88, 0.88, 0.92), 0.9, 0.0),
    "futon_red": ((0.62, 0.18, 0.14), 0.9, 0.0),
    "paper": ((0.92, 0.89, 0.80), 0.9, 0.0),
    "orange": ((0.90, 0.40, 0.08), 0.7, 0.0),
    "red": ((0.70, 0.08, 0.06), 0.5, 0.0),
    "yellow": ((0.95, 0.75, 0.10), 0.5, 0.0),
    "glass_dark": ((0.05, 0.07, 0.09), 0.1, 0.0),
    "mirror": ((0.70, 0.80, 0.85), 0.05, 0.6),
    "screen": ((0.30, 0.55, 0.85), 0.3, 0.0),
    "skin": ((0.85, 0.66, 0.52), 0.8, 0.0),
    "skin_dead": ((0.45, 0.52, 0.42), 0.8, 0.0),
    "hair": ((0.06, 0.05, 0.05), 0.8, 0.0),
    "hoodie": ((0.16, 0.28, 0.50), 0.9, 0.0),
    "jeans": ((0.18, 0.22, 0.32), 0.9, 0.0),
    "shirt_dirty": ((0.70, 0.68, 0.60), 0.9, 0.0),
    "blood": ((0.35, 0.02, 0.02), 0.6, 0.0),
    "suit": ((0.12, 0.12, 0.14), 0.9, 0.0),
}
EMISSIVE = {"screen": 1.5}


def material(name):
    m = bpy.data.materials.get("kl_" + name)
    if m:
        return m
    rgb, rough, metal = PALETTE[name]
    m = bpy.data.materials.new("kl_" + name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    return m


# --------------------------------------------------------------------------
# Tiny modelling kit: everything is boxes and cylinders in one bmesh.
# --------------------------------------------------------------------------

class Prop:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def _mat_index(self, mat_name):
        if mat_name not in self.mats:
            self.mats.append(mat_name)
        return self.mats.index(mat_name)

    def _tag(self, verts, mat_name):
        idx = self._mat_index(mat_name)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = idx

    def box(self, size, pos, mat, rot=(0, 0, 0)):
        """size=(x, y, z); pos=(x, y, z_bottom). rot in degrees, about the box centre."""
        sx, sy, sz = size
        x, y, zb = pos
        m = (Matrix.Translation((x, y, zb + sz / 2))
             @ Matrix.Rotation(math.radians(rot[2]), 4, "Z")
             @ Matrix.Rotation(math.radians(rot[1]), 4, "Y")
             @ Matrix.Rotation(math.radians(rot[0]), 4, "X")
             @ Matrix.Diagonal((sx, sy, sz, 1.0)))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._tag(res["verts"], mat)

    def cyl(self, radius, depth, pos, mat, axis="Z", segments=16, radius2=None):
        """pos is the centre of the cylinder."""
        rot = Matrix.Identity(4)
        if axis == "X":
            rot = Matrix.Rotation(math.radians(90), 4, "Y")
        elif axis == "Y":
            rot = Matrix.Rotation(math.radians(90), 4, "X")
        m = Matrix.Translation(pos) @ rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments,
                                    radius1=radius, radius2=radius if radius2 is None else radius2,
                                    depth=depth, matrix=m)
        self._tag(res["verts"], mat)

    def build(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for name in self.mats:
            mesh.materials.append(material(name))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# --------------------------------------------------------------------------
# Props. Sizes are (W, H, D) in the game = Blender (X, Z, Y). Front is -Y.
# --------------------------------------------------------------------------

def cabinet_body(p, w, h, d, mat="white", top=None):
    p.box((w, d, h), (0, 0, 0), mat)
    if top:
        p.box((w + 0.01, d + 0.02, 0.04), (0, -0.01, h - 0.04), top)


def handle(p, x, z, d, vertical=False, mat="steel"):
    size = (0.025, 0.03, 0.16) if vertical else (0.16, 0.03, 0.025)
    p.box(size, (x, -d / 2 - 0.015, z), mat)


def bed():
    p = Prop("bed")
    p.box((1.4, 2.0, 0.2), (0, 0, 0), "wood_light")
    p.box((1.3, 1.9, 0.18), (0, 0, 0.2), "fabric_white")
    p.box((1.34, 1.25, 0.08), (0, -0.33, 0.37), "fabric_blue")
    p.box((0.6, 0.32, 0.1), (0, 0.72, 0.37), "fabric_white")
    return p


def wardrobe():
    p = Prop("wardrobe")
    p.box((1.0, 0.6, 1.9), (0, 0, 0), "wood")
    for x in (-0.25, 0.25):
        p.box((0.47, 0.02, 1.78), (x, -0.31, 0.06), "wood_light")
        handle(p, x * 0.15, 0.95, 0.64, vertical=True)
    return p


def bookshelf():
    p = Prop("bookshelf")
    rng = random.Random(7)
    w, h, d = 1.0, 1.9, 0.45
    for x in (-w / 2 + 0.015, w / 2 - 0.015):
        p.box((0.03, d, h), (x, 0, 0), "wood")
    p.box((w, 0.02, h), (0, d / 2 - 0.01, 0), "wood_dark")
    shelves = [0.0, 0.47, 0.94, 1.41, 1.87]
    for z in shelves:
        p.box((w - 0.06, d - 0.02, 0.03), (0, 0, z), "wood")
    book_mats = ["red", "fabric_blue", "paper", "orange", "black", "wood_light"]
    for z in shelves[:-1]:
        x = -w / 2 + 0.05
        while x < w / 2 - 0.08:
            bw = rng.uniform(0.025, 0.06)
            bh = rng.uniform(0.22, 0.38)
            if rng.random() > 0.12:
                p.box((bw, d * 0.7, bh), (x + bw / 2, -0.03, z + 0.03), rng.choice(book_mats))
            x += bw + 0.004
    return p


def side_table():
    p = Prop("side_table")
    p.box((0.4, 0.4, 0.04), (0, 0, 0.41), "wood_light")
    for x in (-0.17, 0.17):
        for y in (-0.17, 0.17):
            p.box((0.035, 0.035, 0.41), (x, y, 0), "wood")
    p.box((0.08, 0.16, 0.012), (0.02, 0, 0.45), "black")
    p.box((0.07, 0.14, 0.004), (0.02, 0, 0.462), "screen")
    return p


def drawer_chest():
    p = Prop("drawer_chest")
    cabinet_body(p, 1.0, 0.9, 0.5, "wood")
    for i, z in enumerate((0.04, 0.33, 0.62)):
        p.box((0.94, 0.02, 0.25), (0, -0.26, z), "wood_light")
        handle(p, 0, z + 0.13, 0.54)
    return p


def desk():
    p = Prop("desk")
    p.box((0.9, 0.55, 0.04), (0, 0, 0.68), "wood_light")
    for x in (-0.42, 0.42):
        p.box((0.04, 0.5, 0.68), (x, 0, 0), "steel")
    p.box((0.34, 0.24, 0.018), (0, -0.04, 0.72), "plastic_grey")
    p.box((0.34, 0.012, 0.22), (0, 0.085, 0.738), "plastic_grey", rot=(-12, 0, 0))
    p.box((0.31, 0.004, 0.19), (0, 0.077, 0.752), "screen", rot=(-12, 0, 0))
    return p


def kitchen_cabinet():
    p = Prop("kitchen_cabinet")
    cabinet_body(p, 1.0, 0.9, 0.55, "white", top="stone")
    for x in (-0.25, 0.25):
        p.box((0.47, 0.02, 0.78), (x, -0.285, 0.04), "porcelain")
        handle(p, x * 0.2, 0.7, 0.59, vertical=True)
    return p


def kitchen_sink():
    p = Prop("kitchen_sink")
    cabinet_body(p, 0.7, 0.9, 0.55, "white", top="stone")
    p.box((0.46, 0.36, 0.015), (0, -0.03, 0.9), "steel")
    p.box((0.4, 0.3, 0.004), (0, -0.03, 0.912), "black")
    p.cyl(0.015, 0.28, (0, 0.2, 1.04), "steel")
    p.box((0.03, 0.18, 0.03), (0, 0.12, 1.16), "steel")
    p.box((0.66, 0.02, 0.78), (0, -0.285, 0.04), "porcelain")
    return p


def gas_stove():
    p = Prop("gas_stove")
    cabinet_body(p, 0.7, 0.9, 0.55, "white", top="stone")
    p.box((0.6, 0.42, 0.03), (0, 0, 0.9), "black")
    for x in (-0.15, 0.15):
        p.cyl(0.08, 0.02, (x, 0.0, 0.94), "steel")
        p.cyl(0.03, 0.025, (x, 0.0, 0.95), "black")
        p.cyl(0.025, 0.03, (x, -0.295, 0.8), "black", axis="Y")
    # The gas main: a yellow valve handle on the front panel.
    p.box((0.12, 0.03, 0.04), (0.2, -0.29, 0.25), "yellow")
    p.box((0.62, 0.02, 0.6), (0, -0.285, 0.05), "porcelain")
    return p


def fridge():
    p = Prop("fridge")
    p.box((0.7, 0.65, 1.8), (0, 0, 0), "white")
    p.box((0.66, 0.02, 0.55), (0, -0.33, 1.22), "porcelain")
    p.box((0.66, 0.02, 1.15), (0, -0.33, 0.04), "porcelain")
    handle(p, -0.28, 1.45, 0.68, vertical=True)
    handle(p, -0.28, 0.95, 0.68, vertical=True)
    return p


def tv_stand():
    p = Prop("tv_stand")
    p.box((1.2, 0.4, 0.4), (0, 0, 0.05), "wood_dark")
    for x in (-0.55, 0.55):
        p.box((0.05, 0.35, 0.05), (x, 0, 0), "black")
    p.box((0.3, 0.18, 0.03), (0, 0.05, 0.45), "black")
    p.box((0.04, 0.04, 0.12), (0, 0.05, 0.48), "black")
    p.box((1.0, 0.05, 0.58), (0, 0.05, 0.58), "black")
    p.box((0.96, 0.01, 0.54), (0, 0.02, 0.6), "glass_dark")
    return p


def kotatsu():
    p = Prop("kotatsu")
    p.box((0.96, 0.96, 0.3), (0, 0, 0), "futon_red")
    p.box((0.9, 0.9, 0.03), (0, 0, 0.36), "wood_light")
    p.box((0.86, 0.86, 0.06), (0, 0, 0.3), "futon_red")
    # Hand-crank radio
    p.box((0.22, 0.09, 0.13), (0.1, 0.05, 0.39), "orange")
    p.cyl(0.035, 0.012, (0.05, -0.0, 0.46), "black", axis="Y")
    p.box((0.008, 0.008, 0.25), (0.19, 0.08, 0.52), "steel", rot=(0, 20, 0))
    return p


def binocular_stand():
    p = Prop("binocular_stand")
    p.cyl(0.18, 0.04, (0, 0, 0.56), "wood_light")
    p.cyl(0.03, 0.54, (0, 0, 0.27), "wood")
    p.cyl(0.14, 0.03, (0, 0, 0.015), "wood")
    for x in (-0.045, 0.045):
        p.cyl(0.035, 0.14, (x, 0, 0.62), "black", axis="Y")
    return p


def bathtub():
    p = Prop("bathtub")
    w, d, h = 1.6, 0.75, 0.55
    p.box((w, d, 0.1), (0, 0, 0), "porcelain")
    for y in (-d / 2 + 0.04, d / 2 - 0.04):
        p.box((w, 0.08, h - 0.1), (0, y, 0.1), "porcelain")
    for x in (-w / 2 + 0.04, w / 2 - 0.04):
        p.box((0.08, d - 0.16, h - 0.1), (x, 0, 0.1), "porcelain")
    p.cyl(0.02, 0.15, (w / 2 - 0.1, d / 2 - 0.05, 0.62), "steel")
    return p


def medicine_cabinet():
    p = Prop("medicine_cabinet")
    p.box((0.6, 0.35, 0.78), (0, 0, 0), "white")
    p.box((0.62, 0.38, 0.04), (0, -0.01, 0.78), "porcelain")
    p.box((0.34, 0.24, 0.01), (0, -0.03, 0.815), "steel")
    p.box((0.56, 0.02, 0.7), (0, -0.18, 0.05), "porcelain")
    p.box((0.5, 0.03, 0.17), (0, 0.15, 0.83), "mirror")
    return p


def toilet():
    p = Prop("toilet")
    p.box((0.36, 0.48, 0.38), (0, -0.08, 0), "porcelain")
    p.box((0.4, 0.46, 0.03), (0, -0.09, 0.39), "white")
    p.box((0.42, 0.18, 0.4), (0, 0.26, 0.4), "porcelain")
    # shelf above
    p.box((0.45, 0.2, 0.025), (0, 0.25, 0.78), "wood_light")
    return p


def storage_closet():
    p = Prop("storage_closet")
    p.box((1.2, 0.5, 1.6), (0, 0, 0), "wood")
    for x in (-0.3, 0.3):
        p.box((0.58, 0.02, 1.5), (x, -0.26 + (0.0 if x < 0 else 0.015), 0.05), "paper")
        p.box((0.6, 0.025, 0.04), (x, -0.27, 0.05), "wood_light")
        p.box((0.6, 0.025, 0.04), (x, -0.27, 1.51), "wood_light")
        p.box((0.04, 0.025, 1.5), (x - 0.28, -0.27, 0.05), "wood_light")
        p.box((0.04, 0.025, 1.5), (x + 0.28, -0.27, 0.05), "wood_light")
    return p


def emergency_bag():
    p = Prop("emergency_bag")
    p.box((0.42, 0.26, 0.33), (0, 0, 0), "orange")
    p.box((0.3, 0.06, 0.16), (0, -0.15, 0.05), "orange")
    p.box((0.43, 0.27, 0.025), (0, 0, 0.22), "fabric_white")
    p.box((0.2, 0.04, 0.04), (0, 0, 0.33), "black")
    return p


def toolbox():
    p = Prop("toolbox")
    p.box((0.5, 0.28, 0.2), (0, 0, 0), "red")
    p.box((0.51, 0.29, 0.02), (0, 0, 0.18), "red")
    p.box((0.03, 0.03, 0.06), (-0.12, 0, 0.2), "black")
    p.box((0.03, 0.03, 0.06), (0.12, 0, 0.2), "black")
    p.box((0.27, 0.03, 0.025), (0, 0, 0.255), "black")
    p.box((0.06, 0.02, 0.04), (0, -0.15, 0.15), "steel")
    return p


def shoe_cabinet():
    p = Prop("shoe_cabinet")
    cabinet_body(p, 1.2, 1.0, 0.4, "wood_light", top="wood")
    for x in (-0.3, 0.3):
        p.box((0.57, 0.02, 0.9), (x, -0.205, 0.04), "wood")
        handle(p, x * 0.1, 0.55, 0.43, vertical=True)
    return p


def mail_slot():
    p = Prop("mail_slot")
    p.box((0.3, 0.1, 0.95), (0, 0.01, 0), "wood")
    p.box((0.3, 0.12, 0.03), (0, 0, 0.95), "wood_dark")
    p.box((0.22, 0.09, 0.015), (0.02, 0, 0.98), "paper", rot=(0, 0, 8))
    p.box((0.2, 0.08, 0.012), (-0.02, 0, 0.995), "fabric_white", rot=(0, 0, -5))
    return p


def dining_chair():
    p = Prop("dining_chair")
    p.box((0.45, 0.45, 0.04), (0, 0, 0.43), "wood_light")
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            p.box((0.04, 0.04, 0.43), (x, y, 0), "wood")
    for x in (-0.19, 0.19):
        p.box((0.04, 0.04, 0.4), (x, 0.19, 0.47), "wood")
    p.box((0.42, 0.03, 0.15), (0, 0.19, 0.7), "wood_light")
    return p


def washing_machine():
    p = Prop("washing_machine")
    p.box((0.6, 0.6, 0.85), (0, 0, 0), "white")
    p.cyl(0.19, 0.03, (0, -0.31, 0.42), "plastic_grey", axis="Y")
    p.cyl(0.15, 0.035, (0, -0.315, 0.42), "glass_dark", axis="Y")
    p.box((0.5, 0.03, 0.1), (0, -0.3, 0.72), "plastic_grey")
    return p


def humanoid(name, skin, top, legs, zombie=False):
    p = Prop(name)
    tilt = 8 if zombie else 0
    for x in (-0.1, 0.1):
        p.box((0.13, 0.15, 0.78), (x, 0, 0), legs)
        p.box((0.14, 0.22, 0.07), (x, -0.03, 0), "black")
    p.box((0.42, 0.22, 0.58), (0, 0, 0.78), top, rot=(tilt, 0, 0))
    p.box((0.2, 0.2, 0.24), (0.0, -0.05 if zombie else 0, 1.38), skin, rot=(tilt * 2, 0, 6 if zombie else 0))
    p.box((0.21, 0.21, 0.07), (0.0, 0.0 if zombie else 0.01, 1.58), "hair", rot=(tilt * 2, 0, 6 if zombie else 0))
    if zombie:
        # Arms out in front, the classic reach.
        for x in (-0.25, 0.25):
            p.box((0.1, 0.55, 0.1), (x, -0.3, 1.18), "shirt_dirty")
            p.box((0.09, 0.12, 0.09), (x, -0.62, 1.19), skin)
        p.box((0.2, 0.05, 0.25), (0.08, -0.12, 0.95), "blood")
        p.box((0.05, 0.03, 0.03), (-0.05, -0.15, 1.46), "blood")
        p.box((0.05, 0.03, 0.03), (0.05, -0.15, 1.46), "blood")
    else:
        p.box((0.1, 0.12, 0.55), (-0.27, 0, 0.82), top)
        p.box((0.09, 0.1, 0.1), (-0.27, 0, 0.72), skin)
        p.box((0.16, 0.03, 0.04), (0, -0.11, 1.45), skin)
    return p


def player():
    return humanoid("player", "skin", "hoodie", "jeans")


def zombie():
    return humanoid("zombie", "skin_dead", "shirt_dirty", "suit", zombie=True)


BUILDERS = {
    "bed": bed, "wardrobe": wardrobe, "bookshelf": bookshelf, "side_table": side_table,
    "drawer_chest": drawer_chest, "desk": desk, "kitchen_cabinet": kitchen_cabinet,
    "kitchen_sink": kitchen_sink, "gas_stove": gas_stove, "fridge": fridge, "tv_stand": tv_stand,
    "kotatsu": kotatsu, "binocular_stand": binocular_stand, "bathtub": bathtub,
    "medicine_cabinet": medicine_cabinet, "toilet": toilet, "storage_closet": storage_closet,
    "emergency_bag": emergency_bag, "toolbox": toolbox, "shoe_cabinet": shoe_cabinet,
    "mail_slot": mail_slot, "dining_chair": dining_chair, "washing_machine": washing_machine,
    "player": player, "zombie": zombie,
}


# --------------------------------------------------------------------------
# Export
# --------------------------------------------------------------------------

def resolve_out_dir():
    if OUT_DIR:
        return OUT_DIR
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--out" in argv:
        return os.path.abspath(argv[argv.index("--out") + 1])
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    return os.path.abspath(os.path.join(here, "..", "..", "assets", "models"))


def export(obj, out_dir):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(out_dir, obj.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    return path


def main():
    names = ONLY or list(BUILDERS)
    out_dir = resolve_out_dir()
    os.makedirs(out_dir, exist_ok=True)
    # Clear previous builds of the same props so re-running is idempotent.
    for n in names:
        old = bpy.data.objects.get(n)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    for i, n in enumerate(names):
        obj = BUILDERS[n]().build()
        if EXPORT:
            print("exported", export(obj, out_dir))
        # Lay them out in a row so they're easy to inspect in the viewport.
        obj.location.x = (i % 8) * 2.0
        obj.location.y = (i // 8) * 2.5


main()
