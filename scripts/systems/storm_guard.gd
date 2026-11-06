extends RefCounted
## Tide's storm guard (台風対策): the entrances against wind-flung debris.
## One handler serves every point through the entrances' `mode_handler` hook
## (barricade_point.gd), like Ash's seal.gd.
##
## Level 0 = bare glass, 1 = an X of tape on every pane (it barely slows the
## damage but holds the shards together), 2 = plywood over the tape.
## The glass keeps the entrance's hp; a hit that empties it blows the window
## in. The front door is steel and the wind can't touch it: it's where Tanaka
## knocks. The balcony door's second action brings the balcony things in, and
## later signals the rescue boats.

const Props := preload("res://scripts/world/props.gd")
const C_TAPE := Color(0.55, 0.78, 0.45)   # light-green curing tape (養生テープ)
const C_PLY := Color(1.0, 0.9, 0.74)      # tint on the wood surface: pale plywood

var scenario: Script
var levels := {}   # point id -> 0..2
var nodes := {}    # point id -> barricade
var director: Node  # TideDirector: Tanaka, balcony things, signalling


func _init(s: Script) -> void:
	scenario = s
	for id in s.STORM_POINTS:
		levels[id] = 0


func attach(node: Node, id: String) -> void:
	nodes[id] = node
	node.mode_handler = self


func _id(o: Node) -> String:
	return o.point_id


func is_glass(id: String) -> bool:
	return id != "front_door"


func factor(id: String) -> float:
	return scenario.LEVEL_DAMAGE[levels.get(id, 0)]


func name_of(id: String) -> String:
	return nodes[id].display_name if nodes.has(id) else id


static func lc(name: String) -> String:
	return name[0].to_lower() + name.substr(1)


## A gust throws something into the point: `amount` before tape and boards.
## Returns the damage done.
func hit(id: String, amount: float) -> float:
	var o = nodes.get(id)
	if o == null or o.broken or not is_glass(id):
		return 0.0
	var dmg := amount * factor(id)
	o.hp -= dmg
	o.last_hit_time = Game.run_time
	var pos: Vector3 = o.global_position + Vector3(0, 1.2, 0)
	Sfx.play("debris_hit", pos, -2.0 + amount * 0.15, 0.12, 30.0)
	if o.hp <= 0.0:
		o.hp = 0.0
		o._break_open()  # calls on_breached below
	return dmg


func status_word(id: String) -> String:
	var o = nodes.get(id)
	if o and o.broken:
		return "BLOWN IN"
	if not is_glass(id):
		return "steel"
	return ["bare glass", "taped", "boarded"][levels[id]]


# --- Interactable calls ------------------------------------------------------

func get_prompt(o: Node, alt: bool) -> String:
	var id := _id(o)
	if not is_glass(id):
		return director.door_prompt(alt) if director else ""
	if o.broken:
		return "" if alt else "Board over the hole (%d materials)" % scenario.REPAIR_COST
	if alt:
		return _alt_prompt(o, id)
	match levels[id]:
		0:
			return "Tape an X across the glass (%d material)" % scenario.TAPE_COST
		1:
			return "Board it over with plywood (%d materials)" % scenario.BOARD_COST
	if o.hp < o.max_hp:
		return "Patch the frame, +%d (%d material)" % [int(scenario.PATCH_HP), scenario.PATCH_COST]
	return ""


func _alt_prompt(o: Node, id: String) -> String:
	if id == "balcony_door" and director:
		var special: String = director.balcony_prompt()
		if special != "":
			return special
	if o.hp < o.max_hp and levels[id] < 2:
		return "Patch the frame, +%d (%d material)" % [int(scenario.PATCH_HP), scenario.PATCH_COST]
	return ""


func get_status(o: Node) -> String:
	var id := _id(o)
	if not is_glass(id):
		return director.door_status() if director else "(locked)"
	if o.broken:
		return "(BLOWN IN, the storm is coming through)"
	var s := status_word(id)
	s += ", %d/%d" % [int(o.hp), int(o.max_hp)]
	if id == "balcony_door" and director and director.loose_on_balcony():
		s += ", pots and a drying rack outside"
	return "(%s)" % s


func get_flag(o: Node) -> String:
	var id := _id(o)
	if not Game.has_insight("prepared_storm") or not is_glass(id) or o.broken:
		return ""
	if id == "balcony_door" and director and director.loose_on_balcony():
		return "LOOSE ITEMS"
	if levels[id] == 0 and id != "bath_window":
		return "BARE GLASS"
	return ""


func get_duration(o: Node, alt: bool) -> float:
	var id := _id(o)
	if not is_glass(id):
		return 0.6
	if o.broken:
		return 5.0
	if alt:
		if id == "balcony_door" and director and director.balcony_prompt() != "":
			return director.balcony_duration()
		return 2.0
	return [2.0, 4.5, 2.0][levels[id]]


func get_hold_sound(o: Node, alt: bool) -> String:
	var id := _id(o)
	if not is_glass(id):
		return ""
	if o.broken or (not alt and levels[id] >= 1):
		return "hammer"
	if alt:
		return "" if id == "balcony_door" else "hammer"
	return "tape"


func get_noise(o: Node, alt: bool) -> float:
	var id := _id(o)
	if not is_glass(id):
		return 0.0
	if o.broken or (not alt and levels[id] >= 1):
		return 4.0
	return 0.4


func perform(o: Node, alt: bool) -> void:
	var id := _id(o)
	if not is_glass(id):
		if director:
			director.door_perform(alt)
		return
	if o.broken:
		if not Game.spend_materials(scenario.REPAIR_COST):
			return
		o.broken = false
		o.collision_layer = o.LAYER_INTACT
		o.hp = o.base_hp
		o.max_hp = o.base_hp
		o.level = 0
		levels[id] = 2
		Game.say("You nail plywood across the empty frame. The wind stops screaming through the flat.", "good")
		o._refresh_visual()
	elif alt:
		if id == "balcony_door" and director and director.balcony_prompt() != "":
			director.balcony_perform()
		elif o.hp < o.max_hp:
			_patch(o)
	else:
		var lvl: int = levels[id]
		if lvl >= 2:
			if o.hp < o.max_hp:
				_patch(o)
		else:
			var cost: int = scenario.TAPE_COST if lvl == 0 else scenario.BOARD_COST
			if not Game.spend_materials(cost):
				return
			levels[id] = lvl + 1
			if lvl == 0:
				Game.say("You tape a big X across each pane of the %s. If it breaks, the glass should hold together." % lc(o.display_name), "good")
			else:
				Game.say("You screw plywood over the %s. The room goes dim, and the rattling stops." % lc(o.display_name), "good")
	refresh_visual(o)
	Game.stats_changed.emit()


func _patch(o: Node) -> void:
	if not Game.spend_materials(scenario.PATCH_COST):
		return
	o.hp = min(o.max_hp, o.hp + scenario.PATCH_HP)
	Game.say("You wedge and tape the %s's frame. It stops flexing." % lc(o.display_name), "info")


func on_breached(o: Node) -> void:
	var id := _id(o)
	var lvl: int = levels.get(id, 0)
	levels[id] = 0
	refresh_visual(o)
	if director:
		director.on_window_broken(o, lvl)


# --- Visuals -----------------------------------------------------------------

func refresh_visual(o: Node) -> void:
	var old = o.get_node_or_null("StormVisual")
	if old:
		o.remove_child(old)
		old.queue_free()
	var id := _id(o)
	if not is_glass(id) or o.broken:
		return
	var lvl: int = levels.get(id, 0)
	if lvl == 0:
		return
	var vis := Node3D.new()
	vis.name = "StormVisual"
	var w: float = o.size.x
	var y0: float = o.sill + 0.05
	var y1: float = o.opening_height - 0.05
	var h := y1 - y0
	# An X of tape on the inside of each pane (the two sliding panes sit
	# side by side, the inner one at z -0.02).
	var pw := (w - 0.1) * 0.5
	for i in 2:
		var px := (-0.25 + 0.5 * i) * (w - 0.1)
		var pz := -0.02 + 0.03 * i - 0.008
		var diag := sqrt(pw * pw + h * h)
		for sgn in [-1.0, 1.0]:
			var strip := Props.box(Vector3(diag * 0.92, 0.05, 0.003), C_TAPE, Vector3(px, y0 + h * 0.5, pz))
			strip.rotation.z = sgn * atan2(h, pw)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vis.add_child(strip)
	if lvl >= 2:
		# A plywood sheet over the opening on the room side, held by two battens.
		var ply := Props.sbox(Vector3(w + 0.04, h + 0.06, 0.012), "wood_light", Vector3(0, y0 + h * 0.5, -0.1), C_PLY, false)
		vis.add_child(ply)
		for f in [0.2, 0.8]:
			vis.add_child(Props.sbox(Vector3(w + 0.12, 0.07, 0.03), "wood", Vector3(0, y0 + h * f, -0.12), Color(0.95, 0.9, 0.85), false))
	o.add_child(vis)
