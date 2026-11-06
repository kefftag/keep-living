extends RefCounted
## Every playable scenario, and the teasers for the ones still to come
## (GDD "Scenarios (roadmap)"). Game.scenario holds the active one.

const ZOMBIE := preload("res://scripts/data/scenario_zombie.gd")
const ASH := preload("res://scripts/data/scenario_ash.gd")

const ALL := [ZOMBIE, ASH]
const DEFAULT_ID := "zombie"

## Shown locked on the scenario select.
const UPCOMING := [
	{"id": "static", "title": "Static", "title_jp": "雑音", "unlock_after_win": "zombie",
		"blurb": "A signal from the sky. Screens and radios are dangerous to use, and the neighbours act strangely."},
	{"id": "tide", "title": "Tide", "title_jp": "高潮", "unlock_after_win": "zombie",
		"blurb": "The water is rising. Move what matters upward, and listen to the building groan."},
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


## "" when the scenario can be played, otherwise why not.
static func lock_reason(after_win: String) -> String:
	if after_win == "" or Meta.wins_in(after_win) > 0:
		return ""
	return "Unlocks after your first rescue in %s." % title_of(after_win)
