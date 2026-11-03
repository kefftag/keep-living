extends RefCounted
## Helpers for building placeholder geometry, and for swapping in Blender
## models when they exist.
##
## Model swap rule: if res://assets/models/<model_name>.glb exists it is used
## instead of the grey-box. Models must be authored in metres with the origin
## at the bottom-centre and the "front" of the object facing Blender's -Y
## (which becomes Godot's +Z). See docs/BLENDER_PIPELINE.md.

const MODEL_DIR := "res://assets/models/"

static var _materials := {}


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


static func box(size: Vector3, color: Color, center: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = center
	return mi


static func box_shape(size: Vector3, center: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	return cs


static func has_model(model_name: String) -> bool:
	return model_name != "" and ResourceLoader.exists(MODEL_DIR + model_name + ".glb")


## Returns a Node3D whose origin is at the bottom-centre of `size`.
static func visual(model_name: String, size: Vector3, color: Color) -> Node3D:
	if has_model(model_name):
		var scene: PackedScene = load(MODEL_DIR + model_name + ".glb")
		if scene:
			return scene.instantiate()
	var root := Node3D.new()
	root.name = "Greybox"
	root.add_child(box(size, color, Vector3(0, size.y * 0.5, 0)))
	# A darker strip on the front face so you can read which way it faces.
	root.add_child(box(Vector3(size.x * 0.9, min(0.06, size.y * 0.2), 0.02), color.darkened(0.45),
		Vector3(0, size.y * 0.85, size.z * 0.5 + 0.01)))
	return root


static func label(text: String, height: float, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 26
	l.outline_size = 8
	l.modulate = color
	l.position = Vector3(0, height, 0)
	return l
