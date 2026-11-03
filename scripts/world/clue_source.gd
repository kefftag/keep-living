extends "res://scripts/world/interactable.gd"
## Phone, TV, radio, laptop, mail slot, binoculars... Each offers one or more
## clues, gated by time of day, day number and power.
##
## entries: [{clue, from (total minutes), needs_power, night_only, day_only}]

var verb := "Check"
var entries: Array = []
var idle_status := "(nothing new)"
var seen_this_run: Array = []


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
