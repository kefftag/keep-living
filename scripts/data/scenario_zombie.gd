extends RefCounted
## Scenario 1 — "Outbreak".
##
## The player is never told what kind of apocalypse this is. They piece it
## together from clues. Every clue is remembered across deaths (knowledge is
## the main roguelite progression), and most clues unlock an *insight*: a
## permanent, mechanical advantage that reflects what the player now knows.

const ID := "zombie"
const TITLE := "Outbreak"
## The correct answer on the journal's theory board.
const THEORY_ANSWER := "infection"
## Survive this many nights; rescue arrives at dawn of the next day.
const NIGHTS_TO_SURVIVE := 5

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
