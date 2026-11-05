extends RefCounted
## Geometry, materials and model loading.
##
## Model lookup for a prop called <name>, in order:
##   1. assets/models/<name>/<name>.gltf   CC0 scans from Poly Haven. Fitted
##      (uniform scale, bottom-centre) into the prop's in-game box.
##   2. assets/models/<name>.glb           our Blender kit. Used as authored
##      (metres, origin bottom-centre, front = Blender -Y = Godot +Z); its flat
##      "kl_*" materials are swapped for the textured surfaces below.
##   3. a grey box.
##
## Surfaces are PBR texture sets in assets/textures (see
## tools/textures/fetch_textures.py), mapped triplanar so boxes and untextured
## meshes need no UVs.

const MODEL_DIR := "res://assets/models/"
const TEX_DIR := "res://assets/textures/"

## World size (metres) one texture tile covers. Mirrors assets/textures/manifest.json.
const SURFACE_SIZE := {
	"wallpaper": 0.8, "floor_wood": 2.08, "floor_genkan": 2.0, "floor_cushion": 2.0,
	"floor_bath": 1.8, "concrete_floor": 2.5, "concrete_wall": 2.7, "tile_white": 1.2,
	"wood_light": 1.0, "wood": 1.0, "wood_dark": 1.0, "fabric": 0.6,
}

## Our Blender kit's material names -> [surface, keep the kit colour as a tint?]
const KIT_SURFACES := {
	"kl_wood": ["wood", false], "kl_wood_light": ["wood_light", false], "kl_wood_dark": ["wood_dark", false],
	"kl_fabric_blue": ["fabric", true], "kl_fabric_white": ["fabric", true], "kl_futon_red": ["fabric", true],
	"kl_paper": ["fabric", true], "kl_shirt_dirty": ["fabric", true], "kl_suit": ["fabric", true],
	"kl_stone": ["floor_cushion", true], "kl_white": ["wallpaper", true],
}

static var _materials := {}
static var _surfaces := {}


static func mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


static func has_surface(key: String) -> bool:
	return SURFACE_SIZE.has(key) and ResourceLoader.exists(TEX_DIR + key + "_albedo.jpg")


## A textured PBR material. `world` = triplanar in world space (static
## architecture, so textures line up across pieces); otherwise object space
## (things that move, like doors and falling furniture).
static func surface(key: String, tint: Color = Color.WHITE, world: bool = true, scale_mult: float = 1.0) -> Material:
	var cache_key := "%s|%s|%s|%s" % [key, tint.to_html(), world, scale_mult]
	if _surfaces.has(cache_key):
		return _surfaces[cache_key]
	if not has_surface(key):
		return mat(tint)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_DIR + key + "_albedo.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX_DIR + key + "_normal.jpg")
	m.normal_scale = 0.25 if key == "wallpaper" else 1.0  # クロス emboss is subtle
	m.roughness_texture = load(TEX_DIR + key + "_rough.jpg")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 4.0
	var s: float = 1.0 / (SURFACE_SIZE[key] * scale_mult)
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_surfaces[cache_key] = m
	return m


static func box(size: Vector3, color: Color, center: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = center
	return mi


## A box with a textured surface.
static func sbox(size: Vector3, key: String, center: Vector3 = Vector3.ZERO, tint: Color = Color.WHITE, world: bool = true) -> MeshInstance3D:
	var mi := box(size, tint, center)
	mi.material_override = surface(key, tint, world)
	return mi


static func box_shape(size: Vector3, center: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	return cs


static func _scan_path(model_name: String) -> String:
	return MODEL_DIR + model_name + "/" + model_name + ".gltf"


static func has_model(model_name: String) -> bool:
	return model_name != "" and (ResourceLoader.exists(_scan_path(model_name))
		or ResourceLoader.exists(MODEL_DIR + model_name + ".glb"))


## Returns a Node3D whose origin is at the bottom-centre of `size`.
## `longest_up` rotates a fitted scan so its longest axis points up first
## (for things like the bat that are modelled lying down).
static func visual(model_name: String, size: Vector3, color: Color, longest_up: bool = false) -> Node3D:
	if model_name != "" and ResourceLoader.exists(_scan_path(model_name)):
		var scan: PackedScene = load(_scan_path(model_name))
		if scan:
			return _fit(scan.instantiate(), size, longest_up)
	if model_name != "" and ResourceLoader.exists(MODEL_DIR + model_name + ".glb"):
		var scene: PackedScene = load(MODEL_DIR + model_name + ".glb")
		if scene:
			var inst := scene.instantiate()
			_texture_kit_materials(inst)
			return inst
	var root := Node3D.new()
	root.name = "Greybox"
	root.add_child(box(size, color, Vector3(0, size.y * 0.5, 0)))
	return root


## Uniformly scale `model` to fit inside `size`, centred, sitting on y = 0.
static func _fit(model: Node3D, size: Vector3, longest_up: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Fitted"
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(model)
	var raw := _aabb(model, Transform3D.IDENTITY)
	var rot := Basis()
	if longest_up:
		var s := raw.size
		if s.x >= s.y and s.x >= s.z:
			rot = Basis(Vector3.BACK, PI * 0.5)    # x -> y
		elif s.z >= s.y:
			rot = Basis(Vector3.RIGHT, -PI * 0.5)  # z -> y
	var aabb := Transform3D(rot, Vector3.ZERO) * raw
	if aabb.size.length() < 0.0001:
		return holder
	var k: float = min(size.x / max(aabb.size.x, 0.001), min(size.y / max(aabb.size.y, 0.001), size.z / max(aabb.size.z, 0.001)))
	var c := aabb.get_center()
	pivot.transform = Transform3D(rot.scaled(Vector3.ONE * k), Vector3(-c.x * k, -aabb.position.y * k, -c.z * k))
	return holder


static func _aabb(node: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var box_ := xf * (node as MeshInstance3D).mesh.get_aabb()
		out = box_
		first = false
	for c in node.get_children():
		var sub := _aabb(c, xf)
		if sub.size == Vector3.ZERO and sub.position == Vector3.ZERO:
			continue
		out = sub if first else out.merge(sub)
		first = false
	return out


## Swap the kit's flat colours for textured surfaces (object-space triplanar).
static func _texture_kit_materials(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null or not KIT_SURFACES.has(m.resource_name):
				continue
			var spec: Array = KIT_SURFACES[m.resource_name]
			var tint := Color.WHITE
			if spec[1] and m is BaseMaterial3D:
				tint = (m as BaseMaterial3D).albedo_color
			mi.set_surface_override_material(i, surface(spec[0], tint, false))
	for c in node.get_children():
		_texture_kit_materials(c)


static func label(text: String, height: float, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 32
	l.outline_size = 8
	l.modulate = color
	l.position = Vector3(0, height, 0)
	return l
