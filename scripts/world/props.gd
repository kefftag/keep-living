extends RefCounted
## Geometry, materials and model loading.
##
## Model lookup for a prop called <name>, in order:
##   1. assets/models/<name>/<name>.gltf   CC0 scans from Poly Haven. Fitted
##      (uniform scale, bottom-centre) into the prop's in-game box.
##   2. assets/models/<name>.glb           our Blender kit. Used as authored
##      (metres, origin bottom-centre, front = Blender -Y = Godot +Z); its flat
##      "kl_*" materials are swapped for the textured surfaces and finishes below.
##   3. a grey box.
##
## Surfaces are 2K PBR texture sets in assets/textures (albedo, normal, ORM;
## see tools/textures/fetch_textures.py) drawn by assets/shaders/surface.gdshader:
## triplanar, so boxes and untextured meshes need no UVs, with low-frequency
## macro variation so large areas don't show the tile repeating.
## Finishes are untextured physically based materials (metal, plastic, glass).

const MODEL_DIR := "res://assets/models/"
const TEX_DIR := "res://assets/textures/"
const SURFACE_SHADER := preload("res://assets/shaders/surface.gdshader")
const GLASS_SHADER := preload("res://assets/shaders/glass.gdshader")
const GLASS_REFLECT_SHADER := preload("res://assets/shaders/glass_reflect.gdshader")

## World size (metres) one texture tile covers. Mirrors assets/textures/manifest.json.
const SURFACE_SIZE := {
	"wallpaper": 0.6, "floor_wood": 1.7, "floor_genkan": 1.8, "floor_cushion": 1.8,
	"floor_bath": 1.2, "concrete_floor": 3.0, "balcony_floor": 3.0, "concrete_wall": 2.7,
	"tile_white": 1.27, "wood_light": 1.83, "wood": 1.0, "wood_dark": 1.0, "fabric": 0.4,
	"bath_panel": 0.9, "steel_brushed": 0.5, "asphalt": 3.0,
}

## Per-surface shading. Keys: normal (strength), rough_mul, rough_add, spec,
## tone/mrough/dirt (macro variation), detile, coat (clearcoat), coat_rough,
## rim (fabric sheen), metal.
const SURFACE_LOOK := {
	# クロス: matt vinyl, embossed; tone varies a little with the light falloff anyway.
	"wallpaper": {"normal": 0.4, "spec": 0.4, "tone": 0.03, "mrough": 0.03},
	# Laminate: printed oak under a satin melamine wear layer.
	"floor_wood": {"normal": 0.5, "tone": 0.05, "mrough": 0.06, "coat": 0.35, "coat_rough": 0.25},
	"floor_cushion": {"normal": 0.35, "tone": 0.04, "mrough": 0.05, "coat": 0.3, "coat_rough": 0.3},
	"floor_bath": {"normal": 0.9, "tone": 0.03, "coat": 0.25, "coat_rough": 0.3},
	"floor_genkan": {"normal": 0.8, "tone": 0.05, "dirt": 0.12},
	"concrete_floor": {"normal": 1.0, "tone": 0.08, "dirt": 0.25, "mrough": 0.08, "detile": 0.6},
	"balcony_floor": {"normal": 0.8, "tone": 0.07, "dirt": 0.22, "mrough": 0.08, "detile": 0.7},
	"concrete_wall": {"normal": 0.9, "tone": 0.06, "dirt": 0.12, "detile": 0.5},
	"tile_white": {"normal": 0.8, "coat": 0.8, "coat_rough": 0.05, "tone": 0.02},
	"wood_light": {"normal": 0.4, "coat": 0.25, "coat_rough": 0.3, "tone": 0.03},
	"wood": {"normal": 0.4, "coat": 0.3, "coat_rough": 0.25, "tone": 0.03},
	"wood_dark": {"normal": 0.4, "coat": 0.35, "coat_rough": 0.2, "tone": 0.03},
	"fabric": {"normal": 0.45, "spec": 0.3, "rim": 0.3, "tone": 0.04},
	"bath_panel": {"normal": 0.4, "coat": 0.5, "coat_rough": 0.1, "tone": 0.02},
	"steel_brushed": {"normal": 0.35, "metal": 1.0, "tone": 0.03, "mrough": 0.05},
	"asphalt": {"normal": 1.0, "tone": 0.12, "dirt": 0.3, "mrough": 0.05, "detile": 0.8},
}

## Untextured finishes: [albedo, metallic, roughness, clearcoat, specular].
## Albedo values are real-world reflectance (metals: F0 colour).
const FINISHES := {
	"aluminium": [Color(0.7, 0.7, 0.69), 1.0, 0.45, 0.0, 0.5],      # anodised sash, railings
	"aluminium_dark": [Color(0.22, 0.2, 0.18), 1.0, 0.38, 0.0, 0.5],  # ステンカラー/bronze sash
	"stainless": [Color(0.74, 0.73, 0.71), 1.0, 0.2, 0.0, 0.5],       # door levers, poles
	"chrome": [Color(0.9, 0.9, 0.9), 1.0, 0.06, 0.0, 0.5],
	"steel_painted": [Color(0.23, 0.2, 0.17), 0.0, 0.4, 0.4, 0.5],  # front door (焼付塗装)
	"steel_painted_light": [Color(0.62, 0.62, 0.6), 0.0, 0.45, 0.3, 0.5],  # meter box door
	"iron_black": [Color(0.04, 0.04, 0.045), 0.6, 0.45, 0.0, 0.5],    # window grille
	"plastic_white": [Color(0.8, 0.8, 0.78), 0.0, 0.38, 0.12, 0.5],
	"melamine_white": [Color(0.78, 0.77, 0.74), 0.0, 0.3, 0.2, 0.5],
	"plastic_grey": [Color(0.3, 0.31, 0.32), 0.0, 0.45, 0.0, 0.5],
	"plastic_black": [Color(0.025, 0.025, 0.028), 0.0, 0.35, 0.15, 0.5],
	"porcelain": [Color(0.84, 0.85, 0.86), 0.0, 0.08, 1.0, 0.5],
	"vinyl_white": [Color(0.76, 0.75, 0.72), 0.0, 0.45, 0.0, 0.45],   # skirting (ソフト巾木)
	"board_cream": [Color(0.72, 0.7, 0.64), 0.0, 0.75, 0.0, 0.4],     # balcony partition (隔て板)
	"glass_dark": [Color(0.015, 0.017, 0.02), 0.0, 0.03, 0.0, 0.5],
	"mirror": [Color(0.92, 0.92, 0.92), 1.0, 0.02, 0.0, 0.5],
	"rubber": [Color(0.04, 0.04, 0.04), 0.0, 0.85, 0.0, 0.3],
	"paper": [Color(0.78, 0.76, 0.7), 0.0, 0.85, 0.0, 0.35],
	"screen": [Color(0.02, 0.025, 0.03), 0.0, 0.1, 0.0, 0.5],
	"plastic": [Color(0.5, 0.5, 0.5), 0.0, 0.42, 0.1, 0.5],
}

## Our Blender kit's material names -> [surface or finish, keep the kit colour as a tint?]
const KIT_SURFACES := {
	"kl_wood": ["wood", false], "kl_wood_light": ["wood_light", false], "kl_wood_dark": ["wood_dark", false],
	"kl_fabric_blue": ["fabric", true], "kl_fabric_white": ["fabric", true], "kl_futon_red": ["fabric", true],
	"kl_shirt_dirty": ["fabric", true], "kl_suit": ["fabric", true],
	"kl_paper": ["paper", true],
	"kl_stone": ["steel_brushed", false],     # kitchen worktop: stainless (ステンレス天板)
	"kl_steel": ["steel_brushed", false],
	"kl_white": ["melamine_white", false], "kl_porcelain": ["porcelain", false],
	"kl_plastic_grey": ["plastic_grey", false], "kl_black": ["plastic_black", false],
	"kl_glass_dark": ["glass_dark", false], "kl_mirror": ["mirror", false], "kl_screen": ["screen", false],
	"kl_red": ["plastic", true], "kl_orange": ["plastic", true], "kl_yellow": ["plastic", true],
}

static var _materials := {}
static var _surfaces := {}
static var _macro: Texture2D


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


## A physically based untextured finish from FINISHES. `color` (if given)
## replaces the albedo, for coloured plastics and painted parts.
static func finish(key: String, color: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var cache_key := "finish|%s|%s" % [key, color.to_html()]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var spec: Array = FINISHES.get(key, [Color(0.6, 0.6, 0.6), 0.0, 0.45, 0.0, 0.5])
	var m := StandardMaterial3D.new()
	m.albedo_color = spec[0] if color.a == 0.0 else color
	m.metallic = spec[1]
	m.roughness = spec[2]
	m.metallic_specular = spec[4]
	if spec[3] > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = spec[3]
		m.clearcoat_roughness = 0.08
	if key == "screen":
		m.emission_enabled = true
		m.emission = Color(0.05, 0.07, 0.09)
	_materials[cache_key] = m
	return m


## Window glass: a tinted transmissive pass plus an additive reflection pass.
## frosted: the bathroom's obscured glass (型板ガラス), mostly opaque.
static func glass(frosted: bool = false) -> Material:
	var cache_key := "glass|%s" % frosted
	if _materials.has(cache_key):
		return _materials[cache_key]
	var m: Material
	if frosted:
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.82, 0.85, 0.86, 0.82)
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.roughness = 0.35
		f.metallic_specular = 0.5
		f.cull_mode = BaseMaterial3D.CULL_DISABLED
		f.normal_enabled = true
		f.normal_texture = load(TEX_DIR + "wallpaper_normal.jpg")
		f.normal_scale = 1.5
		f.uv1_triplanar = true
		f.uv1_scale = Vector3(3, 3, 3)
		m = f
	else:
		var g := ShaderMaterial.new()
		g.shader = GLASS_SHADER
		var r := ShaderMaterial.new()
		r.shader = GLASS_REFLECT_SHADER
		g.next_pass = r
		m = g
	_materials[cache_key] = m
	return m


static func has_surface(key: String) -> bool:
	return SURFACE_SIZE.has(key) and ResourceLoader.exists(TEX_DIR + key + "_albedo.jpg")


static func macro_texture() -> Texture2D:
	if _macro == null and ResourceLoader.exists(TEX_DIR + "macro.png"):
		_macro = load(TEX_DIR + "macro.png")
	return _macro


## A textured PBR material. `world` = triplanar in world space (static
## architecture, so textures line up across pieces); otherwise object space
## (things that move, like doors and falling furniture).
static func surface(key: String, tint: Color = Color.WHITE, world: bool = true, scale_mult: float = 1.0) -> Material:
	var cache_key := "%s|%s|%s|%s" % [key, tint.to_html(), world, scale_mult]
	if _surfaces.has(cache_key):
		return _surfaces[cache_key]
	if not has_surface(key):
		return finish(key, Color(0, 0, 0, 0) if tint == Color.WHITE else tint) if FINISHES.has(key) else mat(tint)
	var look: Dictionary = SURFACE_LOOK.get(key, {})
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo_tex", load(TEX_DIR + key + "_albedo.jpg"))
	m.set_shader_parameter("normal_tex", load(TEX_DIR + key + "_normal.jpg"))
	m.set_shader_parameter("orm_tex", load(TEX_DIR + key + "_orm.jpg"))
	m.set_shader_parameter("macro_tex", macro_texture())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("world_space", world)
	m.set_shader_parameter("uv_scale", 1.0 / (SURFACE_SIZE[key] * scale_mult))
	m.set_shader_parameter("normal_strength", look.get("normal", 1.0))
	m.set_shader_parameter("rough_mul", look.get("rough_mul", 1.0))
	m.set_shader_parameter("rough_add", look.get("rough_add", 0.0))
	m.set_shader_parameter("specular", look.get("spec", 0.5))
	m.set_shader_parameter("macro_tone", look.get("tone", 0.05))
	m.set_shader_parameter("macro_rough", look.get("mrough", 0.04))
	m.set_shader_parameter("macro_dirt", look.get("dirt", 0.0))
	m.set_shader_parameter("detile", look.get("detile", 0.0))
	m.set_shader_parameter("clearcoat", look.get("coat", 0.0))
	m.set_shader_parameter("clearcoat_roughness", look.get("coat_rough", 0.2))
	m.set_shader_parameter("rim", look.get("rim", 0.0))
	m.set_shader_parameter("metallic", look.get("metal", 0.0))
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


## A box with an untextured finish (see FINISHES).
static func fbox(size: Vector3, key: String, center: Vector3 = Vector3.ZERO, color: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var mi := box(size, Color.WHITE, center)
	mi.material_override = finish(key, color)
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
			if FINISHES.has(spec[0]):
				mi.set_surface_override_material(i, finish(spec[0], tint if spec[1] else Color(0, 0, 0, 0)))
			else:
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
