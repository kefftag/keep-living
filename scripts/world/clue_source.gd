extends "res://scripts/world/interactable.gd"
## Phone, TV, radio, laptop, mail slot, binoculars... Each offers one or more
## clues, gated by time of day, day number and power.
##
## entries: [{clue, from (total minutes), needs_power, night_only, day_only}]

var verb := "Check"
var entries: Array = []
var idle_status := "(nothing new)"
var seen_this_run: Array = []
var buzz := false         # phone: buzzes until checked
var night_static := false # radio: static hiss at night
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
		out.append(entry["clue"])
	return out


func _next_clue() -> String:
	for clue in _available():
		if not (clue in seen_this_run):
			return clue
	return ""


func get_prompt(alt: bool) -> String:
	if alt:
		return ""
	if _next_clue() != "":
		return "%s the %s" % [verb, display_name.to_lower()]
	return ""


func get_status() -> String:
	if _next_clue() != "":
		return "(something new)"
	for entry in entries:
		if entry.get("needs_power", false) and not Game.power_on:
			return "(no power)"
	return idle_status


func get_duration(_alt: bool) -> float:
	return 0.6


func perform(_alt: bool) -> void:
	var clue := _next_clue()
	if clue == "":
		return
	seen_this_run.append(clue)
	Game.find_clue(clue)
