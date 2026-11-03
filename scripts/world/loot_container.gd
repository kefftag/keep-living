extends "res://scripts/world/interactable.gd"
## A cupboard, drawer or bag that can be searched once per run.

var container_id := ""
var loot := {}
var clue_id := ""
var search_verb := "Search"
var spoils_without_power := false
var searched := false


func get_prompt(alt: bool) -> String:
	if alt or searched:
		return ""
	return "%s the %s" % [search_verb, display_name.to_lower()]


func get_status() -> String:
	return "(empty)" if searched else ""


func get_duration(_alt: bool) -> float:
	return 2.0


func get_noise(_alt: bool) -> float:
	return 0.8


func perform(_alt: bool) -> void:
	searched = true
	var found := loot.duplicate()
	if Game.weapon_container == container_id:
		found["weapon"] = 1
	if spoils_without_power and not Game.power_on:
		if found.get("food", 0) > 0:
			Game.say("The fridge has been off for hours. The food has spoiled.", "warn")
		found["food"] = 0
	Game.collect_loot(found, display_name)
	if clue_id != "":
		Game.find_clue(clue_id)
	if visual:
		visual.scale = Vector3(1.0, 0.97, 1.0)  # tiny "rummaged" squash
