extends RefCounted
## Builds the active scenario on top of the shared apartment: its directors
## (from the scenario's DIRECTORS list) and its world changes (what each clue
## source offers, container loot, seal points and vents). apartment.gd stays
## scenario-agnostic; this is the one place that adapts it.

const NightDirector := preload("res://scripts/systems/night_director.gd")
const EventDirector := preload("res://scripts/systems/event_director.gd")
const AshDirector := preload("res://scripts/systems/ash_director.gd")
const LooterDirector := preload("res://scripts/systems/looter_director.gd")
const Seal := preload("res://scripts/systems/seal.gd")
const Vent := preload("res://scripts/world/vent.gd")


static func build(main: Node3D, zombie_parent: Node3D) -> void:
	var s: Script = Game.scenario
	var apt = main.apartment
	_apply_clue_sources(apt, s.CLUE_SOURCES)
	_apply_loot(apt, s.LOOT)
	var seal = null
	if s.MODE == "seal":
		seal = _build_seals(apt, s)
	for kind in s.DIRECTORS:
		match kind:
			"events":
				var events := EventDirector.new()
				events.name = "EventDirector"
				events.player = main.player
				main.add_child(events)
			"night":
				var night := NightDirector.new()
				night.name = "NightDirector"
				night.barricades = apt.barricades
				night.player = main.player
				night.zombie_parent = zombie_parent
				main.add_child(night)
			"ash":
				var ash := AshDirector.new()
				ash.name = "AshDirector"
				ash.seal = seal
				ash.apartment = apt
				ash.player = main.player
				seal.director = ash
				main.add_child(ash)
			"looters":
				var lo := LooterDirector.new()
				lo.name = "LooterDirector"
				lo.door = apt.barricades.get("front_door")
				lo.player = main.player
				main.add_child(lo)
				var ash_node = main.get_node_or_null("AshDirector")
				if ash_node:
					ash_node.looters = lo


static func _apply_clue_sources(apt: Node, sources: Dictionary) -> void:
	for node_name in sources:
		var src = apt.nav_region.get_node_or_null(node_name)
		if src == null:
			push_warning("scenario: no clue source '%s'" % node_name)
			continue
		var spec: Dictionary = sources[node_name]
		src.entries = spec.get("entries", [])
		if spec.has("idle"):
			src.idle_status = spec["idle"]
		if spec.has("verb"):
			src.verb = spec["verb"]


static func _apply_loot(apt: Node, loot: Dictionary) -> void:
	for node_name in loot:
		var c = apt.nav_region.get_node_or_null(node_name)
		if c == null:
			push_warning("scenario: no container '%s'" % node_name)
			continue
		var spec: Dictionary = loot[node_name]
		if spec.has("loot"):
			c.loot = spec["loot"]
		if spec.has("clue"):
			c.clue_id = spec["clue"]


static func _build_seals(apt: Node, s: Script):
	var seal = Seal.new(s)
	for id in s.SEALS:
		var spec: Dictionary = s.SEALS[id]
		if apt.barricades.has(id):
			seal.attach(apt.barricades[id], id)
			continue
		var v = Vent.new()
		v.name = id
		v.point_id = id
		v.display_name = spec.get("label", id)
		v.size = spec.get("size", Vector3(0.24, 0.24, 0.05))
		v.hidden = spec.get("hidden", false)
		v.position = spec["pos"]
		v.rotation.y = spec.get("facing", 0.0)
		apt.add_child(v)  # not under the nav region: it's on the wall
		seal.attach(v, id)
	return seal
