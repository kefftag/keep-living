extends "res://scripts/world/interactable.gd"
## Phone, TV, radio, laptop, mail slot, binoculars... Each offers one or more
## clues, gated by time of day, day number and power.
##
## entries: [{clue, from (total minutes), needs_power, night_only, day_only,
##            flag (a Game.flags key that must be set), battery (phone % it
##            costs to read; nothing to read while the phone is dead)}]

var verb := "Check"
var entries: Array = []
var idle_status := "(nothing new)"
var seen_this_run: Array = []
var buzz := false         # phone: buzzes until checked
var night_static := false # radio: static hiss at night
## A scenario can give this source a second action (Tide: plugging the phone
## in). Calls alt_prompt / alt_status / alt_flag / alt_perform with this node.
var alt_handler: Object = null
var _buzz_t := 1.0
var _static: AudioStreamPlayer3D


func _process(delta: float) -> void:
	if not Game.is_alive_phase():
		return
	if buzz and _next_clue() != "" and seen_this_run.is_empty():
		_buzz_t -= delta
		if _buzz_t <= 0.0:
			_buzz_t = 4.0
			Sfx.play("phone_buzz", global_position + Vector3(0, 0.5, 0), -6.0, 0.0)
	if night_static:
		var want := Game.phase == Game.Phase.NIGHT
		if want and not is_instance_valid(_static):
			_static = Sfx.loop_on("radio_static", self, -16.0, Vector3(0, 0.45, 0))
		elif not want and is_instance_valid(_static):
			_static.queue_free()


func _available() -> Array:
	var out: Array = []
	for entry in entries:
		if Game.total_minutes() < entry.get("from", 0):
			continue
		if entry.get("needs_power", false) and not Game.power_on:
			continue
		if entry.get("night_only", false) and Game.phase != Game.Phase.NIGHT:
			continue
		if entry.get("day_only", false) and Game.phase != Game.Phase.DAY:
			continue
		if entry.has("flag") and not Game.flags.has(entry["flag"]):
			continue
		if entry.has("battery") and Game.phone_battery <= 0.0:
			continue
		out.append(entry["clue"])
	return out


func _next_clue() -> String:
	for clue in _available():
		if not (clue in seen_this_run):
			return clue
	return ""


func get_prompt(alt: bool) -> String:
	if alt:
		return alt_handler.alt_prompt(self) if alt_handler else ""
	if _next_clue() != "":
		return "%s the %s" % [verb, display_name.to_lower()]
	return ""


func get_status() -> String:
	if _next_clue() != "":
		return "(something new)"
	if alt_handler:
		var s: String = alt_handler.alt_status(self)
		if s != "":
			return s
	for entry in entries:
		if entry.get("needs_power", false) and not Game.power_on:
			return "(no power)"
	return idle_status


func get_flag() -> String:
	return alt_handler.alt_flag(self) if alt_handler else ""


func get_duration(alt: bool) -> float:
	return 1.0 if alt else 0.6


func perform(alt: bool) -> void:
	if alt:
		if alt_handler:
			alt_handler.alt_perform(self)
		return
	var clue := _next_clue()
	if clue == "":
		return
	seen_this_run.append(clue)
	for entry in entries:
		if entry["clue"] == clue and entry.has("battery"):
			if alt_handler and alt_handler.has_method("drain_battery"):
				alt_handler.drain_battery(float(entry["battery"]))  # low-power mode applies
			else:
				Game.phone_battery = max(0.0, Game.phone_battery - float(entry["battery"]))
	Game.find_clue(clue)
