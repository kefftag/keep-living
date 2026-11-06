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
var wood := true  # wood-grain leaf (most Japanese interior doors) or plain
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
		var lw := width - 0.01
		var lh := height - 0.01
		# The leaf, as one slab or as rails and stiles around a glazed opening.
		var parts: Array = [[Vector3(lw, lh, 0.035), Vector3(0, height * 0.5, 0)]]
		if glass:
			var gw := width * 0.45
			var g0 := height * 0.35
			var g1 := height * 0.85
			parts = [
				[Vector3(lw, g0, 0.035), Vector3(0, g0 * 0.5, 0)],
				[Vector3(lw, lh - g1, 0.035), Vector3(0, (g1 + lh) * 0.5, 0)],
				[Vector3((lw - gw) * 0.5, g1 - g0, 0.035), Vector3(-(lw + gw) * 0.25, (g0 + g1) * 0.5, 0)],
				[Vector3((lw - gw) * 0.5, g1 - g0, 0.035), Vector3((lw + gw) * 0.25, (g0 + g1) * 0.5, 0)],
			]
		for part in parts:
			if wood:
				leaf.add_child(Props.sbox(part[0], "wood_light", part[1], color, false))
			else:
				leaf.add_child(Props.fbox(part[0], "plastic_white", part[1], color * Color(0.85, 0.85, 0.85)))
		if glass:
			# Glazed panel: frosted (型板) in the bathroom door, clear in the living-room door.
			var pane := Props.box(Vector3(width * 0.45, height * 0.5, 0.005), Color.WHITE, Vector3(0, height * 0.6, 0))
			pane.material_override = Props.glass(not wood)
			leaf.add_child(pane)
			for e in [[Vector3(width * 0.45 + 0.03, 0.015, 0.04), Vector3(0, height * 0.85 + 0.0075, 0)],
					[Vector3(width * 0.45 + 0.03, 0.015, 0.04), Vector3(0, height * 0.35 - 0.0075, 0)],
					[Vector3(0.015, height * 0.5, 0.04), Vector3(-width * 0.225 - 0.0075, height * 0.6, 0)],
					[Vector3(0.015, height * 0.5, 0.04), Vector3(width * 0.225 + 0.0075, height * 0.6, 0)]]:
				leaf.add_child(Props.fbox(e[0], "aluminium" if not wood else "stainless", e[1]))
		var hx := (width * 0.5 - 0.08) * (1.0 if hinge_left else -1.0)
		if kind == "sliding":
			hx = (width * 0.5 - 0.06) * -slide_sign
			leaf.add_child(Props.fbox(Vector3(0.025, 0.2, 0.038), "aluminium_dark", Vector3(hx, 1.0, 0)))  # 引手
		else:
			for z in [-1.0, 1.0]:
				# Lever handle on a round rose (レバーハンドル), satin stainless.
				leaf.add_child(Props.fbox(Vector3(0.055, 0.055, 0.008), "stainless", Vector3(hx, 1.0, z * 0.0215)))
				leaf.add_child(Props.fbox(Vector3(0.02, 0.02, 0.05), "stainless", Vector3(hx, 1.0, z * 0.04)))
				leaf.add_child(Props.fbox(Vector3(0.13, 0.02, 0.018), "stainless", Vector3(hx - 0.055 * sign(hx), 1.0, z * 0.062)))
			# Latch plate on the leaf edge.
			leaf.add_child(Props.fbox(Vector3(0.004, 0.08, 0.025), "stainless", Vector3((width * 0.5 - 0.005) * sign(hx), 1.0, 0)))
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
	if kind == "sliding":
		Sfx.play("slide_door", global_position + Vector3(0, 1.0, 0), -6.0)
	else:
		Sfx.play("door_open" if is_open else "door_close", global_position + Vector3(0, 1.0, 0), -4.0)
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
