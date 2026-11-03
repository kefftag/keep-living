extends "res://scripts/world/interactable.gd"
## Interior door: hinged (開き戸) or sliding (引き戸). The node sits at the
## centre of the opening at floor level; local X runs along the opening.
## Layer 5 (value 16): the player collides with it, zombies and the navmesh
## don't. Infected that reach a closed door shove it open.

const LAYER_DOOR := 16

var kind := "hinged"     # hinged | sliding
var width := 0.75
var height := 2.0
var swing := 1.0         # hinged: +1 opens towards local -Z, -1 towards +Z
var hinge_left := true   # hinged: hinge at local -X (true) or +X
var slide_sign := -1.0   # sliding: which way along local X it slides
var glass := false
var is_open := false

var _t := 0.0  # 0 closed .. 1 open
var _tween: Tween
var _panel: Node3D
var _shape: CollisionShape3D
var _check := 0.0


func _ready() -> void:
	size = Vector3(width, height, 0.05)
	super._ready()
	collision_layer = LAYER_DOOR
	_apply()


func _build() -> void:
	_panel = Node3D.new()
	add_child(_panel)
	var leaf: Node3D
	if Props.has_model(model_name):
		leaf = Props.visual(model_name, Vector3(width - 0.01, height - 0.01, 0.035), color)
	else:
		leaf = Node3D.new()
		leaf.add_child(Props.box(Vector3(width - 0.01, height - 0.01, 0.035), color, Vector3(0, height * 0.5, 0)))
		if glass:
			leaf.add_child(Props.box(Vector3(width * 0.45, height * 0.5, 0.04), Color(0.7, 0.82, 0.9, 0.45), Vector3(0, height * 0.6, 0)))
		var hx := (width * 0.5 - 0.08) * (1.0 if hinge_left else -1.0)
		if kind == "sliding":
			hx = (width * 0.5 - 0.06) * -slide_sign
			leaf.add_child(Props.box(Vector3(0.02, 0.18, 0.045), Color(0.3, 0.3, 0.3), Vector3(hx, 1.0, 0)))
		else:
			for z in [-0.04, 0.04]:
				leaf.add_child(Props.box(Vector3(0.12, 0.02, 0.025), Color(0.75, 0.75, 0.78), Vector3(hx - 0.04 * sign(hx), 1.0, z)))
	_panel.add_child(leaf)
	visual = _panel
	_shape = Props.box_shape(Vector3(width - 0.02, height, 0.04), Vector3(0, height * 0.5, 0))
	add_child(_shape)


func _leaf_transform(t: float) -> Transform3D:
	if kind == "sliding":
		return Transform3D(Basis(), Vector3(slide_sign * width * 0.95 * t, 0, 0))
	var hinge := Vector3(-width * 0.5 if hinge_left else width * 0.5, 0, 0)
	var angle := t * deg_to_rad(95.0) * swing * (1.0 if hinge_left else -1.0)
	var basis := Basis(Vector3.UP, angle)
	return Transform3D(basis, hinge + basis * -hinge)


func _apply() -> void:
	var xf := _leaf_transform(_t)
	_panel.transform = xf
	_shape.transform = Transform3D(xf.basis, xf * Vector3(0, height * 0.5, 0))


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_t, _t, 1.0 if is_open else 0.0, 0.45)


func _set_t(v: float) -> void:
	_t = v
	_apply()


func _physics_process(delta: float) -> void:
	_check -= delta
	if is_open or _check > 0.0:
		return
	_check = 0.25
	for z in get_tree().get_nodes_in_group("zombie"):
		if z.is_alive() and z.global_position.distance_to(global_position) < 0.9:
			set_open(true)
			Game.make_noise(global_position, 3.0)
			return


func get_prompt(alt: bool) -> String:
	if alt:
		return ""
	return "Close" if is_open else "Open"


func get_duration(_alt: bool) -> float:
	return 0.15


func get_noise(_alt: bool) -> float:
	return 0.5


func perform(_alt: bool) -> void:
	set_open(not is_open)
