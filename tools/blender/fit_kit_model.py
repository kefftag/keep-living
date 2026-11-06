"""Turn a high-poly generated model (e.g. a Tripo GLB) into a game kit model.

Run inside Blender (MCP execute_blender_code, or blender -b -P with args set
below). It imports SRC, decimates to TRIS triangles, scales it uniformly so it
fits the W x H x D box from docs/BLENDER_PIPELINE.md (fitting the height
exactly unless that would overflow width/depth), puts the origin at the bottom
centre with the front facing -Y, downsizes textures to TEX px, and exports
assets/models/<NAME>.glb, which Props.visual() uses as authored.

    fit(src, name, size=(w, h, d), tris=30000, tex=2048, yaw_deg=0)

depth_slack lets the depth exceed D by that factor so height/width win.
yaw_deg rotates about Z first, for models whose front isn't already -Y.
"""
import bpy, math, os
from mathutils import Vector, Matrix

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")) if "__file__" in dir() else ""


def _clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures, bpy.data.actions):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def fit(src, name, size, tris=30000, tex=2048, yaw_deg=0.0, depth_slack=1.0, repo="/Users/keffeine/projects/keep-living"):
    _clear()
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == 'VIEW_3D')
    region = next(r for r in area.regions if r.type == 'WINDOW')
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.import_scene.gltf(filepath=os.path.expanduser(src))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    # join into one mesh, apply transforms
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        with bpy.context.temp_override(window=win, area=area, region=region):
            bpy.ops.object.join()
    m = bpy.context.view_layer.objects.active
    for o in list(bpy.data.objects):
        if o is not m:
            bpy.data.objects.remove(o, do_unlink=True)
    m.parent = None
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    n = len(m.data.polygons)
    if n > tris:
        d = m.modifiers.new("dec", 'DECIMATE')
        d.ratio = tris / n
        with bpy.context.temp_override(window=win, area=area, region=region):
            bpy.ops.object.modifier_apply(modifier="dec")
    for p in m.data.polygons:
        p.use_smooth = True
    me = m.data
    if yaw_deg:
        me.transform(Matrix.Rotation(math.radians(yaw_deg), 4, 'Z'))
    vs = [v.co for v in me.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    ext = mx - mn
    w, h, dep = size  # game W x H x D -> Blender X, Z, Y
    # depth_slack > 1 lets deep generated models keep their height and width
    # by poking a little past the nominal depth (against a wall that's fine).
    k = min(w / ext.x, h / ext.z, dep * depth_slack / ext.y)
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    me.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-c))
    me.update()
    for img in bpy.data.images:
        if img.size[0] > tex:
            img.scale(tex, tex)
    m.name = name
    me.name = name
    for i, mat in enumerate(me.materials):
        if mat:
            mat.name = f"{name}_mat{i}"
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image:
                    dst = [l.to_node.type for l in node.outputs[0].links]
                    kind = "normal" if 'NORMAL_MAP' in dst else ("basecolor" if 'BSDF_PRINCIPLED' in dst else "rm")
                    node.image.name = f"{name}_{kind}"
    out = os.path.join(repo, "assets", "models", name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    m.select_set(True)
    with bpy.context.temp_override(window=win, area=area, region=region):
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                                  export_image_format='JPEG', export_jpeg_quality=88, export_yup=True)
    final = (mx - mn) * k
    return {"out": out, "bytes": os.path.getsize(out), "tris": len(me.polygons),
            "size_xyz": tuple(round(x, 3) for x in final), "scale": round(k, 4)}
