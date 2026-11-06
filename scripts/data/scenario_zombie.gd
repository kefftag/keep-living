extends RefCounted
## Scenario 1 — "Outbreak".
##
## The player is never told what kind of apocalypse this is. They piece it
## together from clues. Every clue is remembered across deaths (knowledge is
## the main roguelite progression), and most clues unlock an *insight*: a
## permanent, mechanical advantage that reflects what the player now knows.

const ID := "zombie"
const TITLE := "Outbreak"
const TITLE_JP := "感染"
## One line under the title on the scenario select.
const TAGLINE := "Something is moving in the corridor."
const BLURB := "Five nights of sieges. Reinforce the doors and windows, secure the furniture, keep quiet. Whatever is outside hunts by sound."
## What the core decisions are about: "barricade" (entrances take damage) or
## "seal" (entrances leak ash; see scenario_ash.gd).
const MODE := "barricade"
## Which systems run (scripts/systems/scenario_world.gd builds them).
const DIRECTORS := ["events", "night"]
## A scenario that must be won before this one opens ("" = always open).
const UNLOCK_AFTER_WIN := ""
## The correct answer on the journal's theory board.
const THEORY_ANSWER := "infection"
const THEORY_SOLVED_SAY := "You name it: an infection. Knowing what you're fighting makes every swing count (+15% damage, permanently)."
const THEORY_KNOWN_TEXT := "You know what this is: an infection. The bitten turn. (+15% damage)"
## What a solved theory gives: "damage" (+15% swing damage) or "masks" (masks last 50% longer).
const THEORY_BONUS := "damage"
## Survive this many nights; rescue arrives at dawn of the next day.
const NIGHTS_TO_SURVIVE := 5

const WATER_CUT_AT := 1440 + 6 * 60       # day 2, 06:00 (total minutes)
const POWER_CUT_AT := 2 * 1440 + 8 * 60   # day 3, 08:00

# --- Story text ----------------------------------------------------------------
const INTRO_FIRST := "Tokyo. Monday, 28 October. A third-floor 1LDK in a quiet part of the city.\n\nIt's 07:58, and your phone is screaming. Outside, something has happened. You don't know what yet.\n\nStay inside. Make this apartment safe. Find out what's going on. Keep living."
const INTRO_AGAIN := "You wake up. Monday, 07:58. Your phone is screaming.\n\nAgain.\n\nMorning number {lives}. You remember dying."
const GOAL_TEXT := "Survive %d nights. Days: scavenge, secure and barricade. Nights: they come for the doors and windows.\nAnything you don't secure can kill you too."
const WAKE_MESSAGE := "Your phone is buzzing on the bedside table."
const NIGHT_MESSAGE := "Night falls on day %d. Something is moving in the corridor."
const DAWN_MESSAGE := "Dawn. Day %d. The groaning outside fades."
const RESCUE_JP := "救出"
const RESCUE_EN := "RESCUED"
const RESCUE_TEXT := "Dawn, day %d. Rotor noise grows over the rooftops, and a rope ladder drops past your balcony.\n\nYou kept living."
const RESCUE_SOUND := "helicopter"
## Stats-line counter ("" hides it).
const KILLS_LABEL := "Infected put down"
const DEATHS := {
	"starvation": "Starvation. The cupboards were empty long before the end.",
	"dehydration": "Dehydration.",
	"dehydration_no_tub": "Dehydration. The taps stopped, and the bathtub was never filled.",
}

## Clue sources and containers keep what apartment.gd gives them.
const CLUE_SOURCES := {}
const LOOT := {}

const CLUES := {
	"jalert": {
		"title": "J-ALERT on your phone",
		"text": "[ J-ALERT ]  07:58\nA national emergency has been declared for the Tokyo metropolitan area.\nRemain indoors. Lock all doors and windows.\nDo NOT approach anyone showing signs of illness or injury.\nAwait further instructions.",
		"insight": "",
	},
	"building_notice": {
		"title": "Notice from building management",
		"text": "A photocopied notice, dated yesterday:\n\n\"In the event of a power failure, the building's water pumps will run on backup power for approximately ONE day. Residents are advised to store water.\"\n\nSomeone has underlined ONE day twice.",
		"insight": "water_will_stop",
	},
	"prep_pamphlet": {
		"title": "Ward disaster-prep booklet",
		"text": "A booklet from the ward office, never opened until now. Three lines are circled in red pen:\n\n- Fill the bathtub while water still runs.\n- After shaking stops, close the gas valve.\n- Fix tall furniture to the wall or ceiling.",
		"insight": "prepared",
	},
	"tv_shibuya": {
		"title": "Emergency broadcast",
		"text": "Shaky helicopter footage over the Shibuya scramble. People are running, and other people are chasing them.\n\nThe anchor's voice cracks: \"...those who have been bitten are urged to isolate immediately... this comes hours after this morning's magnitude 6 earthquake, and aftershocks are expected...\"\n\nThe feed cuts to colour bars.",
		"insight": "aftershocks",
	},
	"radio_sound": {
		"title": "Looping radio message",
		"text": "Static, then a calm recorded voice, on a loop:\n\n\"...they track sound. Not light. Not smell. Sound. Keep your voices down. Do not use power tools. Do not answer your door. If they are at your door, stay quiet and they may lose interest...\"",
		"insight": "drawn_to_sound",
	},
	"balcony_view": {
		"title": "View from the balcony door",
		"text": "Through the binoculars, the street below is full of figures standing perfectly still. One of them tries the wall and gives up.\n\nThey don't climb. They come along the balconies, kicking through the thin emergency partitions between units, and up the stairwell to the corridor.",
		"insight": "they_dont_climb",
	},
	"neighbor_note": {
		"title": "Note slid under the door",
		"text": "Shaky handwriting on the back of a receipt:\n\n\"This is Tanaka from 302. My husband was bitten at the station. He had a fever, and now he won't answer me. He keeps scratching at the bedroom door.\nIf you hear knocking, don't answer it. Clean every wound.\"",
		"insight": "bites_turn",
	},
	"forum_rescue": {
		"title": "Frozen forum thread",
		"text": "The laptop is at 9% battery. A forum thread, last updated two hours ago:\n\n> SDF confirmed rooftop helicopter pickups across Minato and Shinjuku\n> at DAWN ON THE 6TH DAY. Hold out until then. Don't go outside.\n\nThe page refuses to refresh.",
		"insight": "rescue_day",
	},
}

const INSIGHTS := {
	"water_will_stop": {
		"title": "The water will stop",
		"desc": "The HUD warns you before the taps run dry.",
	},
	"prepared": {
		"title": "Prepared",
		"desc": "Unsecured furniture and open gas lines are flagged in the world.",
	},
	"aftershocks": {
		"title": "Aftershocks are coming",
		"desc": "Your phone's earthquake early-warning chime sounds before each quake.",
	},
	"drawn_to_sound": {
		"title": "They hunt by sound",
		"desc": "Noise meter on the HUD. Night-time hammering makes half the noise.",
	},
	"they_dont_climb": {
		"title": "They don't climb",
		"desc": "Each day you can see which entrances will be hit tonight.",
	},
	"bites_turn": {
		"title": "The bitten turn",
		"desc": "You clean wounds properly: first-aid kits heal 20 more.",
	},
	"rescue_day": {
		"title": "Rescue at dawn, day 6",
		"desc": "The HUD counts down to rescue.",
	},
}

## Options on the journal's theory board. Shared between scenarios so the
## player has to actually deduce which one they're in.
const THEORIES := [
	{"id": "infection", "label": "An infection. The bitten turn."},
	{"id": "invasion", "label": "Something came from the sky."},
	{"id": "radiation", "label": "A radiation leak is driving people mad."},
	{"id": "unrest", "label": "Civil unrest. People turned on each other."},
]
## Known clues needed before the player may submit a theory.
const THEORY_MIN_CLUES := 3


## The run's timeline: quakes, utilities failing, mail. Same rolls in the same
## order as before scenarios existed, so Outbreak plays out exactly as it did.
static func roll_events(rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	# The first quake always hits on day 1: it is the tutorial for "secure your stuff".
	ev.append({"at": rng.randi_range(13 * 60, 17 * 60), "type": "quake", "strength": 1.0})
	ev.append({"at": 2 * 1440 + rng.randi_range(9 * 60, 18 * 60), "type": "quake", "strength": 0.8})
	ev.append({"at": 3 * 1440 + rng.randi_range(21 * 60, 27 * 60), "type": "quake", "strength": 1.2})
	ev.append({"at": WATER_CUT_AT, "type": "water_cut"})
	ev.append({"at": POWER_CUT_AT, "type": "power_cut"})
	ev.append({"at": 1440 + 7 * 60, "type": "mail", "text": "Something was slid under the front door during the night."})
	return ev


## Which entrances get hit tonight, one id per infected. Rolled each morning
## so the "they don't climb" insight can show it as a forecast.
static func roll_tonight_plan(rng: RandomNumberGenerator, day: int) -> Array:
	var plan: Array = []
	var weights := {"front_door": 1.0, "balcony_door": 1.3, "bedroom_window": 0.9, "bath_window": 0.45}
	for i in 2 + day * 2:
		plan.append(_weighted_pick(rng, weights))
	return plan


static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]


## Per-run extras after the shared start (none here).
static func on_run_start(_game: Node) -> void:
	pass
