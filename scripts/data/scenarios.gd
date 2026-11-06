extends RefCounted
## Every playable scenario, and the teasers for the ones still to come
## (GDD "Scenarios (roadmap)"). Game.scenario holds the active one.

const ZOMBIE := preload("res://scripts/data/scenario_zombie.gd")
const ASH := preload("res://scripts/data/scenario_ash.gd")
const TIDE := preload("res://scripts/data/scenario_tide.gd")
## The final scenario (docs/STORY.md): hidden until scenario_monday.gd's unlock rule passes.
const MONDAY := preload("res://scripts/data/scenario_monday.gd")

const ALL := [ZOMBIE, ASH, TIDE, MONDAY]
const DEFAULT_ID := "zombie"

## Shown locked on the scenario select.
const UPCOMING := [
	{"id": "static", "title": "Static", "title_jp": "雑音", "unlock_after_win": "zombie",
		"blurb": "A signal from the sky. Screens and radios are dangerous to use, and the neighbours act strangely."},
]


static func by_id(id: String) -> Script:
	for s in ALL:
		if s.ID == id:
			return s
	return ZOMBIE


static func title_of(id: String) -> String:
	for s in ALL:
		if s.ID == id:
			return s.TITLE
	return id


## "" when the scenario can be played, otherwise why not. `after_win` is a
## scenario id, or an Array of ids (a rescue in any one of them opens it).
static func lock_reason(after_win: Variant) -> String:
	var ids: Array = after_win if after_win is Array else [after_win]
	var names: Array = []
	for id in ids:
		if id == "" or Meta.wins_in(id) > 0:
			return ""
		names.append(title_of(id))
	if names.is_empty():
		return ""
	return "Unlocks after your first rescue in %s." % " or ".join(names)


## Why scenario `s` can't be played yet ("" = it can).
static func lock_reason_for(s: Script) -> String:
	if s == MONDAY:
		return MONDAY.unlock_reason()
	return lock_reason(s.UNLOCK_AFTER_WIN)


static func monday_unlocked() -> bool:
	return MONDAY.unlock_reason() == ""
