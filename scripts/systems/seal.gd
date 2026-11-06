extends RefCounted
## Ash's seal points (目張り): the gaps around the entrances and vents.
## One handler serves every point; entrances call it through their
## `mode_handler` hook (barricade_point.gd), vents through vent.gd.
##
## Level 0 = open gap, 1 = taped (養生テープ), 2 = plastic sheeting and tape.
## The front door keeps its strength (looters) and can still be braced with R;
## the balcony door's R shovels the ash off the balcony.

const Props := preload("res://scripts/world/props.gd")
const C_TAPE := Color(0.55, 0.78, 0.45)      # light-green curing tape
const C_SHEET := Color(0.9, 0.93, 0.95, 0.35)

var scenario: Script
var levels := {}   # point id -> 0..2
var weights := {}  # point id -> leak weight
var nodes := {}    # point id -> node (barricade or vent)
var director: Node  # AshDirector: shovelling, shouting at looters


func _init(s: Script) -> void:
	scenario = s
	for id in s.SEALS:
		levels[id] = 0
		weights[id] = float(s.SEALS[id]["leak"])


func attach(node: Node, id: String) -> void:
	nodes[id] = node
	node.mode_handler = self


func _id(o: Node) -> String:
	return o.point_id


func _broken(o: Node) -> bool:
	return o.get("broken") == true


func factor(id: String) -> float:
	var n = nodes.get(id)
	if n != null and _broken(n):
		return scenario.BROKEN_FACTOR
	return scenario.SEAL_FACTOR[levels.get(id, 0)]


func leak_of(id: String) -> float:
	return weights.get(id, 0.0) * factor(id)


func total_leak() -> float:
	var t := 0.0
	for id in weights:
		t += leak_of(id)
	return t


## A tremor shakes tape loose: up to `count` sealed points drop a level.
func peel(rng: RandomNumberGenerator, count: int) -> Array:
	var sealed: Array = []
	for id in levels:
		if levels[id] > 0:
			sealed.append(id)
	var out: Array = []
	for i in count:
		if sealed.is_empty():
			break
		var id: String = sealed.pop_at(rng.randi_range(0, sealed.size() - 1))
		set_level(id, levels[id] - 1)
		out.append(id)
	return out


func set_level(id: String, lvl: int) -> void:
	levels[id] = clampi(lvl, 0, 2)
	if nodes.has(id):
		_refresh_visual(nodes[id])


func name_of(id: String) -> String:
	return nodes[id].display_name if nodes.has(id) else id


## "LDK air vent" stays as it is, "Balcony door" becomes "balcony door".
static func lc(name: String) -> String:
	if name.length() > 1 and name[1] == name[1].to_upper() and name[1] != " ":
		return name
	return name[0].to_lower() + name.substr(1)


# --- Interactable calls ------------------------------------------------------

func get_prompt(o: Node, alt: bool) -> String:
	var id := _id(o)
	if _broken(o):
		return "" if alt else "Cover the hole with boards and sheeting (%d materials)" % scenario.REPAIR_COST
	if alt:
		return _alt_prompt(o, id)
	match levels[id]:
		0:
			return "Tape the gaps (%d material)" % scenario.SEAL_COSTS[0]
		1:
			return "Seal with plastic sheeting (%d materials)" % scenario.SEAL_COSTS[1]
	return ""


func _alt_prompt(o: Node, id: String) -> String:
	if id == "front_door":
		if Game.looters_active:
			return "Bang the bat on the door and shout" if Game.has_weapon else "Shout that you're armed"
		if o.level < o.MAX_LEVEL:
			return "Brace the door, +%d strength (%d materials)" % [int(o.REINFORCE_HP), 2 + o.level]
		if o.hp < o.max_hp:
			return "Patch the door up (1 material)"
	if id == "balcony_door" and Game.balcony_load >= 5.0:
		return "Shovel the ash off the balcony%s" % (" (peels the tape)" if levels[id] > 0 else "")
	return ""


func get_status(o: Node) -> String:
	var id := _id(o)
	if _broken(o):
		return "(BROKEN, ash pouring in)"
	var s: String = ["unsealed", "taped", "sheeted and taped"][levels[id]]
	if Game.has_insight("leak_meter"):
		s += ", lets in %.1f" % leak_of(id)
	if id == "front_door" and (o.hp < o.max_hp or o.level > 0 or Game.looters_active):
		s += ", door %d/%d" % [int(o.hp), int(o.max_hp)]
	if id == "balcony_door" and Game.balcony_load >= 5.0 and Game.has_insight("wet_ash"):
		s += ", balcony load %d%%" % int(Game.balcony_load)
	return "(%s)" % s


func get_flag(o: Node) -> String:
	if Game.has_insight("prepared") and not _broken(o) and levels.get(_id(o), 0) == 0:
		return "GAP"
	return ""


func get_duration(o: Node, alt: bool) -> float:
	var id := _id(o)
	if _broken(o):
		return 4.0
	if alt:
		if id == "balcony_door":
			return 6.0
		return 1.0 if Game.looters_active else 3.0
	return 2.5 if levels[id] == 0 else 3.5


func get_hold_sound(o: Node, alt: bool) -> String:
	if _broken(o) or (alt and _id(o) == "front_door" and not Game.looters_active):
		return "hammer"
	if alt and _id(o) == "balcony_door":
		return "rummage"
	return ""


func get_noise(o: Node, alt: bool) -> float:
	if _broken(o) or (alt and _id(o) == "front_door"):
		return 4.0
	return 0.4


func perform(o: Node, alt: bool) -> void:
	var id := _id(o)
	if _broken(o):
		if not Game.spend_materials(scenario.REPAIR_COST):
			return
		o.broken = false
		o.collision_layer = o.LAYER_INTACT
		o.hp = o.base_hp
		o.max_hp = o.base_hp
		o.level = 0
		levels[id] = 1
		Game.say("You board over the %s and tape sheeting across it." % lc(o.display_name), "good")
		o._refresh_visual()
	elif alt:
		if id == "front_door" and Game.looters_active:
			director.shout_at_looters()
		elif id == "front_door":
			if o.level < o.MAX_LEVEL:
				if not Game.spend_materials(2 + o.level):
					return
				o.level += 1
				o.max_hp += o.REINFORCE_HP
				o.hp += o.REINFORCE_HP
				Game.say("You brace the front door (level %d)." % o.level, "good")
			else:
				if not Game.spend_materials(1):
					return
				o.hp = o.max_hp
				Game.say("You patch up the front door.", "info")
			o._refresh_visual()
		elif id == "balcony_door":
			director.shovel_balcony()
	else:
		var lvl: int = levels[id]
		if lvl >= 2 or not Game.spend_materials(scenario.SEAL_COSTS[lvl]):
			return
		levels[id] = lvl + 1
		if lvl == 0:
			Game.say("You run tape around every edge of the %s." % lc(o.display_name), "good")
		else:
			Game.say("You tape plastic sheeting over the %s. Hardly anything gets past it now." % lc(o.display_name), "good")
	_refresh_visual(o)
	Game.stats_changed.emit()


func on_breached(o: Node) -> void:
	if _id(o) == "front_door":
		Game.say("The front door bursts open!", "danger")
	else:
		Game.say("The %s gives way! Ash is pouring in!" % lc(o.display_name), "danger")
	levels[_id(o)] = 0
	_refresh_visual(o)


# --- Visuals -----------------------------------------------------------------

## The inside face of the opening: [width, bottom, top, z, normal sign].
func _face(o: Node) -> Array:
	if o.get("opening_height") != null:  # an entrance: inside is local -Z
		return [o.size.x, o.sill, o.opening_height, -0.125]
	return [o.size.x, 0.0, o.size.y, o.size.z * 0.5 + 0.006]


func _refresh_visual(o: Node) -> void:
	var old = o.get_node_or_null("SealVisual")
	if old:
		o.remove_child(old)
		old.queue_free()
	var lvl: int = levels.get(_id(o), 0)
	if lvl == 0 or _broken(o):
		return
	var f := _face(o)
	var w: float = f[0]
	var y0: float = f[1]
	var y1: float = f[2]
	var z: float = f[3]
	var h := y1 - y0
	var vis := Node3D.new()
	vis.name = "SealVisual"
	var t := 0.05 if w > 0.5 else 0.03
	for part in [
		[Vector3(w + 0.04, t, 0.004), Vector3(0, y1 - t * 0.5, z)],
		[Vector3(w + 0.04, t, 0.004), Vector3(0, y0 + t * 0.5, z)],
		[Vector3(t, h, 0.004), Vector3(-w * 0.5 + t * 0.5, y0 + h * 0.5, z)],
		[Vector3(t, h, 0.004), Vector3(w * 0.5 - t * 0.5, y0 + h * 0.5, z)],
	]:
		vis.add_child(Props.box(part[0], C_TAPE, part[1]))
	if lvl >= 2:
		var sheet := Props.box(Vector3(w, h, 0.003), C_SHEET, Vector3(0, y0 + h * 0.5, z + (0.004 if z > 0 else -0.004)))
		vis.add_child(sheet)
		# An X of tape holding the sheet, like a taped-up window before a typhoon.
		var diag := sqrt(w * w + h * h)
		for sgn in [-1.0, 1.0]:
			var strip := Props.box(Vector3(diag * 0.95, t, 0.004), C_TAPE, Vector3(0, y0 + h * 0.5, z + (0.008 if z > 0 else -0.008)))
			strip.rotation.z = sgn * atan2(h, w)
			vis.add_child(strip)
	o.add_child(vis)
