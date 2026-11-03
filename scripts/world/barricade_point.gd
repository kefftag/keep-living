extends "res://scripts/world/interactable.gd"
## An entrance zombies can attack: the front door, the balcony door, windows.
## Local +Z points outward. Collision is on layer 2 so the navmesh (which only
## parses layer 1) still has a path through it for when it breaks.

signal breached(point)

const REINFORCE_HP := 100.0
const MAX_LEVEL := 3
const REBOARD_COST := 3
const LAYER_INTACT := 2
const LAYER_BREACHED := 32  # nothing collides with it, but the player's look-ray still finds it

const C_SASH := Color(0.62, 0.63, 0.62)     # aluminium window frames
const C_GLASS := Color(0.75, 0.86, 0.92, 0.14)
const C_FROSTED := Color(0.85, 0.88, 0.9, 0.7)
const C_STEEL_DOOR := Color(0.36, 0.33, 0.3)
const C_WALL := Color(0.9, 0.89, 0.86)

var point_id := ""
var base_hp := 100.0
var opening_height := 2.0  # top of the opening above this node's floor
var sill := 0.0
var style := "window"      # door | window | balcony | barred
var spawn_origins: Array = []  # world positions where attackers appear

var level := 0
var max_hp := 100.0
var hp := 100.0
var broken := false
var last_hit_time := -100.0

var panes: Array = []      # glass / door leaf meshes that vanish when breached
var shards: Node3D
var planks: Array = []
var shape_node: CollisionShape3D
var _next_bang := 0.0


func _ready() -> void:
	add_to_group("barricade")
	max_hp = base_hp
	hp = base_hp
	super._ready()
	collision_layer = LAYER_INTACT


func _frame_box(parent: Node3D, sz: Vector3, pos: Vector3, c: Color = C_SASH) -> void:
	parent.add_child(Props.box(sz, c, pos))


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	var w := size.x
	var top := opening_height
	if sill > 0.0:
		visual.add_child(Props.sbox(Vector3(w, sill, 0.15), "wallpaper", Vector3(0, sill * 0.5, 0)))
	var h := top - sill
	match style:
		"door":
			# Steel apartment door (opens outward), lever, peephole, door guard, mail slot.
			_frame_box(visual, Vector3(w, 0.05, 0.16), Vector3(0, top - 0.025, 0), Color(0.3, 0.3, 0.3))
			var leaf := Props.box(Vector3(w - 0.06, h - 0.06, 0.05), C_STEEL_DOOR, Vector3(0, sill + h * 0.5, 0.02))
			visual.add_child(leaf)
			panes.append(leaf)
			for part in [
				[Vector3(0.14, 0.025, 0.03), Vector3(-w * 0.5 + 0.13, 1.0, -0.03), Color(0.75, 0.75, 0.75)],  # lever
				[Vector3(0.03, 0.03, 0.02), Vector3(0, 1.48, -0.01), Color(0.1, 0.1, 0.1)],                  # peephole
				[Vector3(0.05, 0.22, 0.03), Vector3(-w * 0.5 + 0.06, 1.35, -0.03), Color(0.7, 0.7, 0.72)],     # door guard
				[Vector3(0.28, 0.06, 0.02), Vector3(0, 0.75, -0.01), Color(0.2, 0.2, 0.2)],                  # mail slot
			]:
				var m := Props.box(part[0], part[2], part[1])
				leaf.add_child(m)
				m.position -= leaf.position
		"balcony", "window", "barred":
			# Aluminium sash with two sliding panes.
			_frame_box(visual, Vector3(w, 0.05, 0.12), Vector3(0, sill + 0.025, 0))
			_frame_box(visual, Vector3(w, 0.05, 0.12), Vector3(0, top - 0.025, 0))
			_frame_box(visual, Vector3(0.05, h, 0.12), Vector3(-w * 0.5 + 0.025, sill + h * 0.5, 0))
			_frame_box(visual, Vector3(0.05, h, 0.12), Vector3(w * 0.5 - 0.025, sill + h * 0.5, 0))
			var glass_c := C_FROSTED if style == "barred" else C_GLASS
			for i in 2:
				var px := (-0.25 + 0.5 * i) * (w - 0.1)
				var pane := Props.box(Vector3((w - 0.1) * 0.5, h - 0.1, 0.012), glass_c, Vector3(px, sill + h * 0.5, -0.02 + 0.03 * i))
				visual.add_child(pane)
				panes.append(pane)
				_frame_box(pane, Vector3(0.03, h - 0.1, 0.03), Vector3((w - 0.1) * 0.25 - 0.015, 0, 0))
				_frame_box(pane, Vector3(0.03, h - 0.1, 0.03), Vector3(-(w - 0.1) * 0.25 + 0.015, 0, 0))
			if style == "barred":
				# 面格子: the iron grille outside a corridor-facing bathroom window.
				for i in 7:
					var bx := -w * 0.5 + 0.06 + (w - 0.12) * float(i) / 6.0
					_frame_box(visual, Vector3(0.025, h + 0.1, 0.025), Vector3(bx, sill + h * 0.5, 0.14), Color(0.25, 0.25, 0.27))
				_frame_box(visual, Vector3(w + 0.1, 0.03, 0.04), Vector3(0, sill + 0.02, 0.14), Color(0.25, 0.25, 0.27))
				_frame_box(visual, Vector3(w + 0.1, 0.03, 0.04), Vector3(0, top - 0.02, 0.14), Color(0.25, 0.25, 0.27))
	# Broken glass / a bent door, shown once breached.
	shards = Node3D.new()
	shards.visible = false
	visual.add_child(shards)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(point_id)
	for i in 6:
		var shard := Props.box(Vector3(rng.randf_range(0.05, 0.2), rng.randf_range(0.1, 0.35), 0.01),
			C_STEEL_DOOR if style == "door" else C_GLASS,
			Vector3(rng.randf_range(-w * 0.45, w * 0.45), sill + rng.randf_range(0.0, h), rng.randf_range(-0.03, 0.03)))
		shard.rotation.z = rng.randf_range(-1.0, 1.0)
		shards.add_child(shard)
	# Boards nailed across the inside face, 2 per reinforcement level.
	for i in MAX_LEVEL * 2:
		var y := sill + 0.15 + (h - 0.3) * (float(i) / float(MAX_LEVEL * 2 - 1))
		var plank := Props.sbox(Vector3(w + 0.2, 0.14, 0.03), "wood", Vector3(0, y, -0.11), Color(0.95, 0.9, 0.85), false)
		plank.rotation.z = 0.06 if i % 2 == 0 else -0.06
		plank.visible = false
		visual.add_child(plank)
		planks.append(plank)
	shape_node = Props.box_shape(Vector3(w, 2.4, 0.2), Vector3(0, 1.2, 0))
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
	if Game.run_time >= _next_bang:
		_next_bang = Game.run_time + randf_range(0.55, 1.3)
		Sfx.play("bang_door" if style == "door" else "bang_glass", global_position + Vector3(0, 1.2, 0), 2.0, 0.1, 30.0)
	if hp <= 0.0:
		hp = 0.0
		_break_open()
	_refresh_visual()


func _break_open() -> void:
	broken = true
	level = 0
	max_hp = base_hp
	collision_layer = LAYER_BREACHED
	Sfx.play("door_break" if style == "door" else "glass_break", global_position + Vector3(0, 1.2, 0), 4.0, 0.05, 40.0)
	Sfx.play("shriek", global_position + outward() * 0.6 + Vector3(0, 1.5, 0), 0.0, 0.1, 40.0)
	Game.say("The %s has given way! They're getting in!" % display_name.to_lower(), "danger")
	Game.shake.emit(0.6, 0.5)
	Game.make_noise(global_position, 10.0)
	breached.emit(self)


func _refresh_visual() -> void:
	for p in panes:
		p.visible = not broken
	shards.visible = broken
	for i in planks.size():
		planks[i].visible = not broken and i < level * 2


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


func get_hold_sound(_alt: bool) -> String:
	return "hammer"


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
		collision_layer = LAYER_INTACT
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
