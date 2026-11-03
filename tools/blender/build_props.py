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


def kitchen_base(p, w, kick=0.08, h=0.85, d=0.65):
    """System-kitchen unit: recessed toe kick, doors, stone-look counter."""
    p.box((w, d - 0.06, kick), (0, 0.03, 0), "black")
    p.box((w, d, h - kick - 0.04), (0, 0, kick), "white")
    p.box((w + 0.005, d + 0.02, 0.04), (0, -0.01, h - 0.04), "stone")


def bed():
    p = Prop("bed")
    w, d = 1.2, 1.95
    p.box((w, d, 0.22), (0, 0, 0), "wood_light")
    p.box((w, 0.05, 0.75), (0, d / 2 - 0.025, 0), "wood_light")            # headboard (bed head = +Y)
    p.box((w - 0.06, d - 0.08, 0.2), (0, -0.02, 0.22), "fabric_white")      # mattress
    p.box((w - 0.02, d * 0.62, 0.07), (0, -0.33, 0.4), "fabric_blue")      # duvet
    p.box((0.55, 0.32, 0.1), (0, 0.7, 0.42), "fabric_white")               # pillow
    return p


def wardrobe():
    p = Prop("wardrobe")
    w, h, d = 0.75, 1.8, 0.55
    p.box((w, d, h), (0, 0, 0), "wood")
    p.box((w + 0.02, d + 0.02, 0.03), (0, 0, h - 0.03), "wood_dark")
    for x in (-w / 4, w / 4):
        p.box((w / 2 - 0.015, 0.02, h - 0.12), (x, -d / 2 - 0.01, 0.06), "wood_light")
        handle(p, x * 0.2, h * 0.55, d + 0.02, vertical=True)
    return p


def bookshelf():
    p = Prop("bookshelf")
    rng = random.Random(7)
    w, h, d = 0.8, 1.8, 0.3
    for x in (-w / 2 + 0.015, w / 2 - 0.015):
        p.box((0.03, d, h), (x, 0, 0), "wood")
    p.box((w, 0.015, h), (0, d / 2 - 0.0075, 0), "wood_dark")
    shelves = [0.0, 0.44, 0.88, 1.32, 1.77]
    for z in shelves:
        p.box((w - 0.06, d - 0.02, 0.03), (0, 0, z), "wood")
    book_mats = ["red", "fabric_blue", "paper", "orange", "black", "wood_light"]
    for z in shelves[:-1]:
        x = -w / 2 + 0.05
        while x < w / 2 - 0.07:
            bw = rng.uniform(0.02, 0.05)
            bh = rng.uniform(0.18, 0.36)
            if rng.random() > 0.12:
                p.box((bw, d * 0.75, bh), (x + bw / 2, -0.01, z + 0.03), rng.choice(book_mats))
            x += bw + 0.004
    return p


def side_table():
    p = Prop("side_table")
    p.box((0.4, 0.4, 0.04), (0, 0, 0.41), "wood_light")
    for x in (-0.17, 0.17):
        for y in (-0.17, 0.17):
            p.box((0.035, 0.035, 0.41), (x, y, 0), "wood")
    p.box((0.075, 0.155, 0.009), (0.02, 0, 0.45), "black")
    p.box((0.068, 0.145, 0.003), (0.02, 0, 0.459), "screen")
    p.cyl(0.06, 0.12, (-0.1, 0.08, 0.51), "fabric_white", radius2=0.09)  # little lamp shade
    return p


def closet_builtin():
    """クローゼット: built-in closet with four white folding-door panels."""
    p = Prop("closet_builtin")
    w, h, d = 1.8, 2.0, 0.55
    p.box((w, d, h), (0, 0, 0), "white")
    pw = (w - 0.06) / 4
    for i in range(4):
        x = -w / 2 + 0.03 + pw * (i + 0.5)
        p.box((pw - 0.008, 0.025, h - 0.1), (x, -d / 2 - 0.0125, 0.05), "porcelain")
    for x in (-pw * 0.5 - 0.03, pw * 0.5 + 0.03):
        p.box((0.02, 0.03, 0.12), (x * 1.0, -d / 2 - 0.04, 1.0), "steel")
    p.box((w, 0.03, 0.05), (0, -d / 2 - 0.015, h - 0.05), "white")
    return p


def desk():
    p = Prop("desk")
    p.box((0.85, 0.5, 0.03), (0, 0, 0.69), "wood_light")
    for x in (-0.4, 0.4):
        p.box((0.03, 0.46, 0.69), (x, 0, 0), "steel")
    p.box((0.32, 0.22, 0.016), (0, -0.04, 0.72), "plastic_grey")
    p.box((0.32, 0.01, 0.21), (0, 0.075, 0.736), "plastic_grey", rot=(-12, 0, 0))
    p.box((0.29, 0.004, 0.18), (0, 0.068, 0.75), "screen", rot=(-12, 0, 0))
    p.box((0.1, 0.1, 0.11), (0.3, 0.12, 0.72), "porcelain")  # mug
    return p


def kitchen_cabinet():
    p = Prop("kitchen_cabinet")
    kitchen_base(p, 0.6)
    p.box((0.56, 0.02, 0.18), (0, -0.335, 0.6), "porcelain")    # drawer
    p.box((0.56, 0.02, 0.48), (0, -0.335, 0.1), "porcelain")    # door
    handle(p, 0, 0.74, 0.69)
    handle(p, 0.22, 0.45, 0.69, vertical=True)
    return p


def kitchen_sink():
    p = Prop("kitchen_sink")
    kitchen_base(p, 0.7)
    p.box((0.5, 0.38, 0.012), (0, -0.04, 0.85), "steel")
    p.box((0.44, 0.32, 0.004), (0, -0.04, 0.861), "black")
    p.cyl(0.018, 0.3, (0.15, 0.22, 1.0), "steel")
    p.box((0.03, 0.2, 0.03), (0.15, 0.13, 1.13), "steel", rot=(-15, 0, 0))
    p.box((0.66, 0.02, 0.7), (0, -0.335, 0.1), "porcelain")
    handle(p, 0, 0.74, 0.69)
    return p


def gas_stove():
    """2-burner tabletop gas stove (ガスコンロ) with the gas cock (ガス栓) beside it."""
    p = Prop("gas_stove")
    kitchen_base(p, 0.65)
    p.box((0.58, 0.45, 0.1), (0, 0.0, 0.85), "black")             # the stove body
    for x in (-0.14, 0.14):
        p.cyl(0.075, 0.015, (x, 0.03, 0.955), "steel")
        p.cyl(0.03, 0.02, (x, 0.03, 0.96), "black")
        for a in range(4):
            p.box((0.12, 0.012, 0.012), (x, 0.03, 0.97), "black", rot=(0, 0, a * 45))
        p.cyl(0.018, 0.03, (x, -0.235, 0.9), "plastic_grey", axis="Y")
    p.box((0.18, 0.02, 0.05), (0, -0.226, 0.88), "glass_dark")     # grill door
    p.box((0.05, 0.05, 0.05), (0.29, 0.29, 0.85), "steel")          # gas cock on the counter...
    p.box((0.07, 0.015, 0.015), (0.29, 0.29, 0.905), "yellow")      # ...with its yellow lever
    p.box((0.61, 0.02, 0.62), (0, -0.335, 0.1), "porcelain")
    handle(p, 0, 0.62, 0.69)
    return p


def fridge():
    p = Prop("fridge")
    w, h, d = 0.6, 1.6, 0.62
    p.box((w, d, h), (0, 0, 0), "white")
    p.box((w - 0.02, 0.02, 0.5), (0, -d / 2 - 0.01, 1.08), "porcelain")
    p.box((w - 0.02, 0.02, 1.0), (0, -d / 2 - 0.01, 0.05), "porcelain")
    handle(p, -0.25, 1.3, d + 0.02, vertical=True)
    handle(p, -0.25, 0.95, d + 0.02, vertical=True)
    p.box((0.45, 0.35, 0.26), (0, 0, h), "black")                    # microwave on top
    p.box((0.3, 0.01, 0.18), (-0.04, -0.176, h + 0.04), "glass_dark")
    return p


def tv_stand():
    p = Prop("tv_stand")
    p.box((1.2, 0.4, 0.38), (0, 0, 0.07), "wood_dark")
    for x in (-0.55, 0.55):
        p.box((0.05, 0.35, 0.07), (x, 0, 0), "black")
    p.box((0.3, 0.18, 0.02), (0, 0.05, 0.45), "black")
    p.box((0.04, 0.04, 0.1), (0, 0.05, 0.47), "black")
    p.box((0.98, 0.05, 0.58), (0, 0.05, 0.55), "black")
    p.box((0.95, 0.01, 0.55), (0, 0.022, 0.565), "glass_dark")
    return p


def kotatsu():
    p = Prop("kotatsu")
    p.box((0.86, 0.86, 0.3), (0, 0, 0), "futon_red")
    p.box((0.8, 0.8, 0.03), (0, 0, 0.37), "wood_light")
    p.box((0.78, 0.78, 0.07), (0, 0, 0.3), "futon_red")
    p.box((0.22, 0.09, 0.13), (0.1, 0.05, 0.4), "orange")              # hand-crank radio
    p.cyl(0.035, 0.012, (0.05, -0.0, 0.47), "black", axis="Y")
    p.box((0.008, 0.008, 0.25), (0.19, 0.08, 0.53), "steel", rot=(0, 20, 0))
    p.box((0.03, 0.08, 0.02), (0.22, 0.02, 0.45), "black")             # crank
    return p


def binocular_stand():
    p = Prop("binocular_stand")
    p.cyl(0.18, 0.04, (0, 0, 0.56), "wood_light")
    p.cyl(0.03, 0.54, (0, 0, 0.27), "wood")
    p.cyl(0.14, 0.03, (0, 0, 0.015), "wood")
    for x in (-0.045, 0.045):
        p.cyl(0.035, 0.14, (x, 0, 0.62), "black", axis="Y")
    return p


def vanity():
    """洗面化粧台: basin cabinet + three-way mirror cabinet with a light."""
    p = Prop("vanity")
    w, d = 0.75, 0.5
    p.box((w, d, 0.78), (0, 0, 0), "white")
    p.box((w, d + 0.02, 0.06), (0, -0.01, 0.78), "porcelain")
    p.box((0.5, 0.32, 0.01), (0, -0.04, 0.84), "porcelain")
    p.box((0.44, 0.26, 0.004), (0, -0.04, 0.851), "glass_dark")
    p.cyl(0.015, 0.18, (0, 0.17, 0.93), "steel")
    p.box((w - 0.02, 0.02, 0.66), (0, -d / 2 - 0.01, 0.06), "porcelain")
    handle(p, 0, 0.7, d + 0.02)
    p.box((w, 0.16, 0.7), (0, d / 2 - 0.08, 1.05), "white")           # mirror cabinet
    for x in (-w / 3, 0, w / 3):
        p.box((w / 3 - 0.01, 0.01, 0.6), (x, d / 2 - 0.165, 1.08), "mirror")
    p.box((w, 0.12, 0.05), (0, d / 2 - 0.1, 1.75), "fabric_white")    # light strip
    return p


def washing_machine():
    """Top-loading washer, as most Japanese homes use, on its waterproof pan."""
    p = Prop("washing_machine")
    p.box((0.64, 0.64, 0.06), (0, 0, 0), "porcelain")                  # 防水パン
    p.box((0.56, 0.56, 0.86), (0, 0, 0.06), "white")
    p.box((0.5, 0.36, 0.02), (0, -0.07, 0.92), "glass_dark")           # lid window
    p.box((0.56, 0.14, 0.08), (0, 0.21, 0.92), "porcelain")            # control panel
    p.box((0.3, 0.01, 0.04), (0, 0.14, 0.96), "screen")
    return p


def bathtub():
    p = Prop("bathtub")
    w, d, h = 1.7, 0.7, 0.55
    p.box((w, d, 0.1), (0, 0, 0), "porcelain")
    for y in (-d / 2 + 0.05, d / 2 - 0.05):
        p.box((w, 0.1, h - 0.1), (0, y, 0.1), "porcelain")
    for x in (-w / 2 + 0.05, w / 2 - 0.05):
        p.box((0.1, d - 0.2, h - 0.1), (x, 0, 0.1), "porcelain")
    p.box((w - 0.2, d - 0.2, 0.02), (0, 0, 0.1), "fabric_blue")        # tub floor tint
    p.box((0.5, 0.04, 0.2), (w / 2 - 0.35, d / 2 + 0.01, 0.75), "steel")  # mixer tap on the wall
    p.cyl(0.04, 0.03, (w / 2 - 0.35, d / 2 - 0.01, 1.4), "steel", axis="Y")  # shower head
    p.box((0.2, 0.02, 0.12), (-w / 2 + 0.3, d / 2 + 0.01, 0.9), "plastic_grey")  # 給湯 controller
    return p


def toilet():
    p = Prop("toilet")
    p.box((0.36, 0.46, 0.38), (0, -0.08, 0), "porcelain")
    p.box((0.4, 0.46, 0.05), (0, -0.09, 0.38), "white")                # washlet seat
    p.box((0.42, 0.18, 0.4), (0, 0.26, 0.4), "porcelain")
    p.box((0.1, 0.03, 0.18), (0.32, 0.0, 0.62), "white")               # washlet remote on the wall
    p.box((0.45, 0.22, 0.025), (0, 0.24, 1.2), "wood_light")           # shelf
    p.box((0.12, 0.12, 0.12), (-0.12, 0.24, 1.225), "fabric_white")    # toilet roll
    return p


def storage_shelf():
    p = Prop("storage_shelf")
    rng = random.Random(3)
    w, h, d = 0.8, 1.8, 0.35
    for x in (-w / 2 + 0.015, w / 2 - 0.015):
        for y in (-d / 2 + 0.015, d / 2 - 0.015):
            p.box((0.025, 0.025, h), (x, y, 0), "steel")
    for z in (0.08, 0.5, 0.95, 1.4, 1.78):
        p.box((w, d, 0.02), (0, 0, z), "steel")
        if z < 1.7:
            x = -w / 2 + 0.06
            while x < w / 2 - 0.15:
                bw = rng.uniform(0.15, 0.3)
                p.box((bw, d * 0.8, rng.uniform(0.15, 0.32)), (x + bw / 2, 0, z + 0.02), rng.choice(["paper", "wood_light", "fabric_white"]))
                x += bw + 0.03
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
    p.box((0.4, 0.23, 0.18), (0, 0, 0), "red")
    p.box((0.41, 0.24, 0.02), (0, 0, 0.17), "red")
    p.box((0.03, 0.03, 0.05), (-0.1, 0, 0.19), "black")
    p.box((0.03, 0.03, 0.05), (0.1, 0, 0.19), "black")
    p.box((0.23, 0.03, 0.02), (0, 0, 0.23), "black")
    return p


def shoe_cabinet():
    """下駄箱."""
    p = Prop("shoe_cabinet")
    cabinet_body(p, 0.75, 0.9, 0.35, "wood_light", top="wood")
    for x in (-0.187, 0.187):
        p.box((0.36, 0.02, 0.8), (x, -0.185, 0.05), "wood")
        handle(p, x * 0.15, 0.55, 0.39, vertical=True)
    p.box((0.2, 0.1, 0.25), (0.2, 0, 0.9), "fabric_white")              # tissue box / keys tray
    return p


def mail_pile():
    p = Prop("mail_pile")
    rng = random.Random(11)
    for i in range(5):
        p.box((rng.uniform(0.14, 0.24), rng.uniform(0.09, 0.15), 0.004), (rng.uniform(-0.05, 0.05), rng.uniform(-0.04, 0.04), i * 0.005),
              rng.choice(["paper", "fabric_white", "porcelain"]), rot=(0, 0, rng.uniform(-30, 30)))
    return p


def dining_table():
    p = Prop("dining_table")
    p.box((0.75, 0.75, 0.03), (0, 0, 0.67), "wood_light")
    for x in (-0.33, 0.33):
        for y in (-0.33, 0.33):
            p.box((0.04, 0.04, 0.67), (x, y, 0), "wood")
    return p


def dining_chair():
    p = Prop("dining_chair")
    p.box((0.42, 0.42, 0.04), (0, 0, 0.43), "wood_light")
    for x in (-0.18, 0.18):
        for y in (-0.18, 0.18):
            p.box((0.035, 0.035, 0.43), (x, y, 0), "wood")
    for x in (-0.18, 0.18):
        p.box((0.035, 0.035, 0.4), (x, 0.18, 0.47), "wood")
    p.box((0.4, 0.03, 0.15), (0, 0.18, 0.7), "wood_light")
    return p


def range_hood():
    p = Prop("range_hood")
    p.box((0.65, 0.5, 0.12), (0, 0, 0), "white")
    p.box((0.35, 0.3, 0.33), (0, 0.08, 0.12), "white")
    p.box((0.5, 0.01, 0.03), (0, -0.255, 0.04), "plastic_grey")
    return p


def wall_cabinet():
    p = Prop("wall_cabinet")
    p.box((1.3, 0.35, 0.6), (0, 0, 0), "white")
    for x in (-0.325, 0.325):
        p.box((0.64, 0.02, 0.58), (x, -0.185, 0.01), "porcelain")
    return p


def ac_indoor():
    p = Prop("ac_indoor")
    p.box((0.8, 0.25, 0.28), (0, 0, 0), "white")
    p.box((0.76, 0.02, 0.06), (0, -0.13, 0.02), "plastic_grey")       # louvre
    p.box((0.05, 0.01, 0.015), (0.32, -0.126, 0.2), "screen")         # status LED
    return p


def ac_outdoor():
    p = Prop("ac_outdoor")
    p.box((0.7, 0.28, 0.55), (0, 0, 0.0), "white")
    p.cyl(0.19, 0.02, (-0.1, -0.141, 0.28), "plastic_grey", axis="Y")
    p.cyl(0.05, 0.025, (-0.1, -0.145, 0.28), "black", axis="Y")
    return p


def curtain():
    p = Prop("curtain")
    for i in range(5):
        p.box((0.075, 0.06, 2.0), (-0.14 + i * 0.07, 0.012 * (i % 2), 0), "fabric_blue")
    p.box((0.4, 0.04, 0.03), (0, 0, 2.0), "steel")
    return p


def intercom():
    p = Prop("intercom")
    p.box((0.18, 0.04, 0.13), (0, 0, 0), "white")
    p.box((0.08, 0.005, 0.06), (-0.035, -0.021, 0.04), "glass_dark")
    for z in (0.03, 0.065, 0.1):
        p.box((0.03, 0.006, 0.018), (0.055, -0.021, z - 0.005), "porcelain")
    return p


def breaker_panel():
    p = Prop("breaker_panel")
    p.box((0.35, 0.1, 0.3), (0, 0, 0), "porcelain")
    p.box((0.33, 0.005, 0.12), (0, -0.051, 0.16), "plastic_grey")
    return p


def zombie():
    p = Prop("zombie")
    skin, top, legs = "skin_dead", "shirt_dirty", "suit"
    for x in (-0.1, 0.1):
        p.box((0.13, 0.15, 0.78), (x, 0, 0), legs)
        p.box((0.14, 0.22, 0.07), (x, -0.03, 0), "black")
    p.box((0.42, 0.22, 0.58), (0, 0, 0.78), top, rot=(8, 0, 0))
    p.box((0.2, 0.2, 0.24), (0.0, -0.05, 1.38), skin, rot=(16, 0, 6))
    p.box((0.21, 0.21, 0.07), (0.0, 0.0, 1.58), "hair", rot=(16, 0, 6))
    for x in (-0.25, 0.25):
        p.box((0.1, 0.55, 0.1), (x, -0.3, 1.18), "shirt_dirty")
        p.box((0.09, 0.12, 0.09), (x, -0.62, 1.19), skin)
    p.box((0.2, 0.05, 0.25), (0.08, -0.12, 0.95), "blood")
    p.box((0.05, 0.03, 0.03), (-0.05, -0.15, 1.46), "blood")
    p.box((0.05, 0.03, 0.03), (0.05, -0.15, 1.46), "blood")
    return p


BUILDERS = {
    "bed": bed, "wardrobe": wardrobe, "bookshelf": bookshelf, "side_table": side_table,
    "closet_builtin": closet_builtin, "desk": desk, "kitchen_cabinet": kitchen_cabinet,
    "kitchen_sink": kitchen_sink, "gas_stove": gas_stove, "fridge": fridge, "tv_stand": tv_stand,
    "kotatsu": kotatsu, "binocular_stand": binocular_stand, "vanity": vanity,
    "washing_machine": washing_machine, "bathtub": bathtub, "toilet": toilet,
    "storage_shelf": storage_shelf, "emergency_bag": emergency_bag, "toolbox": toolbox,
    "shoe_cabinet": shoe_cabinet, "mail_pile": mail_pile, "dining_table": dining_table,
    "dining_chair": dining_chair, "range_hood": range_hood, "wall_cabinet": wall_cabinet,
    "ac_indoor": ac_indoor, "ac_outdoor": ac_outdoor, "curtain": curtain, "intercom": intercom,
    "breaker_panel": breaker_panel, "zombie": zombie,
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
