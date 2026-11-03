extends "res://scripts/world/interactable.gd"
## An entrance zombies can attack: the front door, the balcony door, windows.
## Local +Z points outward. Collision is on layer 2 so the navmesh (which only
## parses layer 1) still has a path through it for when it breaks.

signal breached(point)

const REINFORCE_HP := 100.0
const MAX_LEVEL := 3
const REBOARD_COST := 3
const CUT_HEIGHT := 1.25  # visuals are sliced like the walls (dollhouse view)

var point_id := ""
var base_hp := 100.0
var opening_height := 2.1
var sill := 0.0
var is_door := false
var spawn_origins: Array = []  # world positions where attackers appear

var level := 0
var max_hp := 100.0
var hp := 100.0
var broken := false
var last_hit_time := -100.0

var panel: MeshInstance3D
var planks: Array = []
var shape_node: CollisionShape3D


func _ready() -> void:
	add_to_group("barricade")
	max_hp = base_hp
	hp = base_hp
	super._ready()
	collision_layer = 2


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	var w := size.x
	var top: float = min(opening_height, CUT_HEIGHT)
	if sill > 0.0:
		visual.add_child(Props.box(Vector3(w, sill, 0.16), Color(0.82, 0.8, 0.76), Vector3(0, sill * 0.5, 0)))
	var panel_h: float = max(top - sill, 0.1)
	var panel_color := Color(0.45, 0.47, 0.5) if is_door else Color(0.55, 0.75, 0.85, 0.55)
	panel = Props.box(Vector3(w - 0.08, panel_h, 0.05), panel_color, Vector3(0, sill + panel_h * 0.5, 0))
	visual.add_child(panel)
	# Frame
	var frame_c := Color(0.25, 0.25, 0.27)
	visual.add_child(Props.box(Vector3(0.06, top, 0.12), frame_c, Vector3(-w * 0.5 + 0.03, top * 0.5, 0)))
	visual.add_child(Props.box(Vector3(0.06, top, 0.12), frame_c, Vector3(w * 0.5 - 0.03, top * 0.5, 0)))
	# Boards, shown per reinforcement level (2 per level), on the inside face.
	for i in MAX_LEVEL * 2:
		var y := sill + 0.12 + (panel_h - 0.24) * (float(i) / float(MAX_LEVEL * 2 - 1))
		var plank := Props.box(Vector3(w + 0.1, 0.12, 0.04), Color(0.55, 0.38, 0.22), Vector3(0, y, -0.08))
		plank.rotation.z = 0.08 if i % 2 == 0 else -0.08
		plank.visible = false
		visual.add_child(plank)
		planks.append(plank)
	shape_node = Props.box_shape(Vector3(w, 2.6, 0.2), Vector3(0, 1.3, 0))
	add_child(shape_node)


func outward() -> Vector3:
	return global_transform.basis.z.normalized()


## Where the n-th attacker stands, outside.
func attack_position(slot: int) -> Vector3:
	var side := global_transform.basis.x.normalized()
	var offset: float = (float(slot % 3) - 1.0) * min(size.x * 0.3, 0.45)
	return global_position + outward() * 0.55 + side * offset


func inside_position() -> Vector3:
	return global_position - outward() * 0.8


func is_under_attack() -> bool:
	return Game.run_time - last_hit_time < 1.0


func take_damage(amount: float) -> void:
	if broken:
		return
	hp -= amount
	last_hit_time = Game.run_time
	if hp <= 0.0:
		hp = 0.0
		_break_open()
	_refresh_visual()


func _break_open() -> void:
	broken = true
	level = 0
	max_hp = base_hp
	shape_node.disabled = true
	Game.say("The %s has given way! They're getting in!" % display_name.to_lower(), "danger")
	Game.shake.emit(0.6, 0.5)
	Game.make_noise(global_position, 10.0)
	breached.emit(self)


func _refresh_visual() -> void:
	panel.visible = not broken
	for i in planks.size():
		planks[i].visible = not broken and i < level * 2
	var t: float = clamp(hp / max_hp, 0.0, 1.0)
	var base_color := Color(0.45, 0.47, 0.5) if is_door else Color(0.55, 0.75, 0.85, 0.55)
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color.lerp(Color(0.8, 0.15, 0.1, base_color.a), 1.0 - t)
	if base_color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel.material_override = m


func _zombie_blocking() -> bool:
	for z in get_tree().get_nodes_in_group("zombie"):
		if z.is_alive() and (z.global_position - global_position).length() < 1.3:
			return true
	return false


# --- Interactable ------------------------------------------------------------

func _reinforce_cost() -> int:
	return 2 + level


func get_prompt(alt: bool) -> String:
	if broken:
		if alt or _zombie_blocking():
			return ""
		return "Board it back up (%d materials)" % REBOARD_COST
	if alt:
		if hp < max_hp:
			return "Patch up to full (1 material)"
		return ""
	if level < MAX_LEVEL:
		return "Reinforce, +%d strength (%d materials)" % [int(REINFORCE_HP), _reinforce_cost()]
	if hp < max_hp:
		return "Patch up to full (1 material)"
	return ""


func get_status() -> String:
	if broken:
		return "(BREACHED%s)" % (", blocked!" if _zombie_blocking() else "")
	return "(%d/%d, level %d/%d)" % [int(hp), int(max_hp), level, MAX_LEVEL]


func get_duration(alt: bool) -> float:
	if broken:
		return 4.0
	if alt or level >= MAX_LEVEL:
		return 2.0
	return 3.0


func get_noise(_alt: bool) -> float:
	var n := 4.0
	if Game.phase == Game.Phase.NIGHT and Game.has_insight("drawn_to_sound"):
		n *= 0.5
	return n


func perform(alt: bool) -> void:
	if broken:
		if not Game.spend_materials(REBOARD_COST):
			return
		broken = false
		shape_node.disabled = false
		hp = base_hp
		max_hp = base_hp
		Game.say("You board up the %s." % display_name.to_lower(), "good")
	elif alt or level >= MAX_LEVEL:
		if not Game.spend_materials(1):
			return
		hp = max_hp
		Game.say("You patch up the %s." % display_name.to_lower(), "info")
	else:
		if not Game.spend_materials(_reinforce_cost()):
			return
		level += 1
		max_hp += REINFORCE_HP
		hp += REINFORCE_HP
		Game.say("The %s is stronger now (level %d)." % [display_name.to_lower(), level], "good")
	_refresh_visual()
	Game.stats_changed.emit()
