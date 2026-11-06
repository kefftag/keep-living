extends RefCounted
## The final scenario — "Monday" (月曜日). docs/STORY.md, "The final scenario".
##
## No apocalypse. Monday 28 October, 07:58, and the clock never moves. Sun
## through the balcony door, birds, a train in the distance. No threat
## directors run: scripts/systems/monday_director.gd plays the morning, the
## knocking and the voice at the door, and offers the two endings (the suit at
## the bedroom closet, or opening the front door). Every container, clue
## source and hidden spot shows its memories again, with a line of
## understanding (scripts/data/story.gd "understand").

const Story := preload("res://scripts/data/story.gd")

const ID := "monday"
const TITLE := "Monday"
const TITLE_JP := "月曜日"
const TAGLINE := "A normal Monday."
const BLURB := "07:58 on Monday, 28 October. Nothing has ended. Nothing is coming. Walk the flat and look at what's here. Someone is knocking at the front door."
const MODE := "monday"
const DIRECTORS: Array = []
## Opened by unlock_reason() below, not by a single rescue.
const UNLOCK_AFTER_WIN := ""
const THEORY_ANSWER := ""
const THEORY_SOLVED_SAY := ""
const THEORY_KNOWN_TEXT := ""
const THEORY_BONUS := ""
const NIGHTS_TO_SURVIVE := 1

# --- Unlock --------------------------------------------------------------------
## Rescued in at least this many of these scenarios...
const UNLOCK_RESCUES := 2
const RESCUE_SCENARIOS := ["zombie", "ash", "tide"]
## ...and at least this many memories, including every key one.
const UNLOCK_MEMORIES := 18

## The frozen clock: 07:58 (minutes after midnight).
const CLOCK := 7 * 60 + 58
## Walking speed while something is wrong with you.
const WALK_MULT := 0.6

# --- Story text ------------------------------------------------------------------
const INTRO_FIRST := Story.MONDAY_INTRO
const INTRO_AGAIN := Story.MONDAY_INTRO
const GOAL_TEXT := "There is nothing to survive today. Walk the flat. Look at what's here.\nSomeone is at the front door."
const WAKE_MESSAGE := "The alarm stops. Somewhere below, a bird. Someone is knocking at the front door."
const NIGHT_MESSAGE := ""
const DAWN_MESSAGE := ""
const RESCUE_JP := ""
const RESCUE_EN := ""
const RESCUE_TEXT := ""
const RESCUE_SOUND := ""
const KILLS_LABEL := ""
const DEATHS := {}

## Nothing to learn from the TV or the radio today; the phone and the laptop
## only hold memories (clue_source.gd shows those on its own).
const CLUE_SOURCES := {
	"phone": {"entries": [], "idle": "(the alarm, still going: 電車 08:14)"},
	"tv": {"entries": [], "idle": "(a morning show, the sound turned down. Sunny, 19°C)"},
	"radio": {"entries": [], "idle": "(a weather forecast: clear all day)"},
	"laptop": {"entries": [], "idle": "(the deck, still open on slide 31)"},
	"binoculars": {"entries": [], "idle": "(an ordinary street, and nobody in it)"},
	"mail": {"entries": [], "idle": "(nothing new)"},
}
## Containers hold no supplies today.
const LOOT := {
	"kitchen_cabinets": {"loot": {}, "clue": ""}, "fridge": {"loot": {}, "clue": ""},
	"vanity": {"loot": {}, "clue": ""}, "toilet_shelf": {"loot": {}, "clue": ""},
	"storage_closet": {"loot": {}, "clue": ""}, "emergency_bag": {"loot": {}, "clue": ""},
	"toolbox": {"loot": {}, "clue": ""}, "shoe_cabinet": {"loot": {}, "clue": ""},
	"bedroom_closet": {"loot": {}, "clue": ""},
}

const CLUES := {}
const INSIGHTS := {}
const THEORIES: Array = []
const THEORY_MIN_CLUES := 999


static func unlock_reason() -> String:
	var rescued := 0
	for id in RESCUE_SCENARIOS:
		if Meta.wins_in(id) > 0:
			rescued += 1
	if rescued < UNLOCK_RESCUES:
		return "???"
	if Meta.memories.size() < UNLOCK_MEMORIES:
		return "???"
	for id in Story.key_ids():
		if not Meta.knows_memory(id):
			return "???"
	return ""


static func roll_events(_rng: RandomNumberGenerator) -> Array:
	return []


static func roll_tonight_plan(_rng: RandomNumberGenerator, _day: int) -> Array:
	return []


static func on_run_start(game: Node) -> void:
	game.minutes = float(CLOCK)
	game.hunger = 100.0
	game.thirst = 100.0
	game.food = 0
	game.water = 0
	game.materials = 0
	game.medkits = 0
	game.has_weapon = false
	game.gas_valve_open = false
