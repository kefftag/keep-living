extends "res://scripts/world/interactable.gd"
## A cupboard, drawer or bag that can be searched once per run. A search can
## also turn up one new memory (scripts/data/story.gd, source = container_id).
## Monday: no supplies; each search shows the memories kept here again, and
## the bedroom closet's E puts on the suit (one of the two endings).

const Story := preload("res://scripts/data/story.gd")

var container_id := ""
var loot := {}
var clue_id := ""
var search_verb := "Search"
var spoils_without_power := false
var searched := false
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	super._ready()
	if spoils_without_power:
		_hum = Sfx.loop_on("fridge_hum", self, -14.0, Vector3(0, 0.3, 0))
		Game.world_changed.connect(func():
			if not Game.power_on and is_instance_valid(_hum):
				_hum.queue_free())


func get_hold_sound(_alt: bool) -> String:
	return "" if Game.is_monday() else "rummage"


func get_prompt(alt: bool) -> String:
	if Game.is_monday():
		return _monday_prompt(alt)
	if alt or searched:
		return ""
	return "%s the %s" % [search_verb, display_name.to_lower()]


func get_status() -> String:
	if Game.is_monday():
		return "" if _monday_next() != "" else "(you remember)"
	return "(empty)" if searched else ""


# --- Monday ---------------------------------------------------------------------

func _is_suit_closet() -> bool:
	return container_id == "bedroom_closet"


func _monday_next() -> String:
	return Story.next_at(container_id, "monday", Game.run_memories, false)


func _monday_prompt(alt: bool) -> String:
	# The closet: E is the suit, R looks through it. Elsewhere E looks.
	if _is_suit_closet() and not alt:
		return "Put on the suit"
	if alt != _is_suit_closet() or _monday_next() == "":
		return ""
	return "Look through the closet" if _is_suit_closet() else "Look in the %s" % display_name.to_lower()


func _monday_perform(alt: bool) -> void:
	if _is_suit_closet() and not alt:
		Game.ending_requested.emit("suit")
		return
	var id := _monday_next()
	if id != "":
		Game.find_memory(id)


func get_duration(alt: bool) -> float:
	if Game.is_monday():
		return 3.0 if _is_suit_closet() and not alt else 1.0
	return 2.0


func get_noise(_alt: bool) -> float:
	return 0.0 if Game.is_monday() else 0.8


func perform(alt: bool) -> void:
	if Game.is_monday():
		_monday_perform(alt)
		return
	searched = true
	var found := loot.duplicate()
	if Game.weapon_container == container_id:
		found["weapon"] = 1
	if spoils_without_power and not Game.power_on:
		if found.get("food", 0) > 0:
			Game.say("The fridge has been off for hours. The food has spoiled.", "warn")
		found["food"] = 0
	Game.collect_loot(found, display_name, container_id)
	if clue_id != "":
		Game.find_clue(clue_id)
	# At most one new memory per search: the next one this place holds.
	var mem := Story.next_at(container_id, Game.scenario_id(), Game.run_memories, true)
	if mem != "":
		Game.find_memory(mem)
	if visual:
		visual.scale = Vector3(1.0, 0.97, 1.0)  # tiny "rummaged" squash
