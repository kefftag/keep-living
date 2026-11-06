extends RefCounted
## Scenario 2 — "Ash" (降灰).
##
## Mt Fuji erupts at 07:41. Tokyo is 100 km downwind. Nothing comes to the
## door most nights: the threat is the air and what runs out. Ash falls all
## day, every day, and gets in through every gap around the doors, windows and
## vents. Breathing it hurts. The tap water turns grey, the power fails, the
## balcony fills with ash that sets like cement in the rain, and on a couple
## of nights desperate people try the front door.
##
## The core decision moves from "reinforce" to "seal and ration": tape the
## gaps (the entrances become seal points, same ids as Outbreak's barricades),
## spend masks only when you have to, and store water while it's still clean.

const ID := "ash"
const TITLE := "Ash"
const TITLE_JP := "降灰"
const TAGLINE := "The light outside looks wrong."
const BLURB := "Fuji has erupted and the ash is coming down on Tokyo. Seal every gap, ration masks and clean water, clear the balcony before the rain, and keep the door shut when strangers come knocking."
const MODE := "seal"
const DIRECTORS := ["events", "ash", "looters"]
const UNLOCK_AFTER_WIN := ""
const THEORY_ANSWER := "eruption"
const THEORY_SOLVED_SAY := "You name it: the mountain. Knowing what you're breathing, you fit every mask properly (masks last 50% longer, permanently)."
const THEORY_KNOWN_TEXT := "You know what this is: Fuji has erupted. (Masks last 50% longer)"
const THEORY_BONUS := "masks"
const NIGHTS_TO_SURVIVE := 5

const ASH_BEGINS_AT := 10 * 60              # day 1, 10:00: the plume reaches Tokyo
const WATER_TAINT_AT := 1440 + 6 * 60       # day 2, 06:00
const POWER_CUT_AT := 1440 + 15 * 60        # day 2, 15:00: wet ash shorts the lines

# --- Balance (all in game minutes) ---------------------------------------------
## Indoor ash `dust` (0..100; air quality = 100 - dust) follows
##   d(dust)/dt = ASH_K_IN * ashfall * leak - ASH_K_OUT * dust
## where leak is the sum of the gaps' LEAK weights times their seal factor.
## Unsealed (leak 7.1) on a heavy day settles around dust 75 (air 25);
## everything taped once (leak 2.5) around air 65.
const ASH_K_IN := 0.16
const ASH_K_OUT := 0.012
const HARM_BELOW := 65.0        # air quality under this hurts
const HARM_PER_MIN := 0.15      # hp per game minute at air 0 (scaled linearly)
const MASK_MINUTES := 360.0     # one DS2 mask: 6 game hours
const MASK_PROTECTION := 0.8    # fraction of harm a mask stops
const SEAL_FACTOR := [1.0, 0.35, 0.08]  # leak multiplier by seal level
const SEAL_COSTS := [1, 2]      # materials for level 1 (tape), level 2 (sheeting)
const BROKEN_FACTOR := 2.5      # a smashed window or forced door
const REPAIR_COST := 3
const ASH_CM_PER_MIN := 0.006   # depth outside per unit of ashfall
const LOAD_PER_MIN := 0.06      # balcony load per unit of ashfall
const RAIN_LOAD_MULT := 2.5     # wet ash is heavy
const RAIN_AIR_MULT := 0.5      # rain knocks ash out of the air
const LOAD_COLLAPSE := 100.0
const COLLAPSE_DAMAGE := 40.0
const SWEEP_DUST := 10.0        # opening the balcony door to shovel lets ash in
const LOOTER_DPS_BASE := 3.0    # front-door damage per second
const LOOTER_DPS_PER_NIGHT := 0.8
const LOOTER_SECONDS := 60.0    # how long they keep at it
const LOOTER_HIT := 35.0
const LOOTER_HIT_ARMED := 15.0

## Seal points. Entrances reuse Outbreak's barricade ids; vents are added to
## the world by scripts/systems/scenario_world.gd.
const SEALS := {
	"front_door": {"leak": 1.0},
	"balcony_door": {"leak": 1.6},
	"bedroom_window": {"leak": 0.9},
	"bath_window": {"leak": 0.5},
	"vent_ldk": {"leak": 1.0, "label": "LDK air vent", "pos": Vector3(6.27, 1.95, 1.3), "facing": -PI * 0.5, "size": Vector3(0.24, 0.24, 0.05)},
	"vent_bedroom": {"leak": 0.8, "label": "Bedroom air vent", "pos": Vector3(0.1, 1.95, 2.55), "facing": PI * 0.5, "size": Vector3(0.24, 0.24, 0.05)},
	"range_hood": {"leak": 1.2, "label": "Range hood duct", "pos": Vector3(5.325, 1.85, 5.13), "facing": PI, "size": Vector3(0.65, 0.45, 0.5), "hidden": true},
}

# --- Story text ----------------------------------------------------------------
const INTRO_FIRST := "Tokyo. A third-floor 1LDK, a hundred kilometres downwind of Mount Fuji.\n\nIt's 07:58, and your phone is screaming. The light coming through the curtains is the wrong colour.\n\nStay inside. Keep the air in here clean. Find out what's going on. Keep living."
const INTRO_AGAIN := "You wake up. 07:58. Your phone is screaming, and the light is brown.\n\nAgain.\n\nYou remember the taste of grit."
const GOAL_TEXT := "Survive %d days. Seal the gaps before the ash gets in, ration masks and clean water, clear the balcony, and keep the front door shut at night.\nThe mountain isn't finished: expect tremors."
const WAKE_MESSAGE := "Your phone is buzzing on the bedside table. The light outside looks wrong."
const NIGHT_MESSAGE := "Night falls on day %d. Ash hisses softly against the windows."
const DAWN_MESSAGE := "Dawn. Day %d. The light comes up brown and dim."
const RESCUE_JP := "避難"
const RESCUE_EN := "EVACUATED"
const RESCUE_TEXT := "Dawn, day %d. A Toei bus with taped-over vents grinds through the grey drifts below, headlights on at sunrise. Figures in masks wave you down to it.\n\nYou kept living."
const RESCUE_SOUND := ""
const KILLS_LABEL := ""
const DEATHS := {
	"starvation": "Starvation. The cupboards were empty long before the bus came.",
	"dehydration": "Dehydration.",
	"dehydration_no_tub": "Dehydration. The tap water turned grey, and the bathtub was never filled.",
	"ash": "Ash in the lungs. Powdered rock and glass, a little more with every breath.",
	"ash_unsealed": "Ash in the lungs. The gaps around the doors and vents were never sealed.",
	"ash_sleep": "You never woke up. The ash crept in under the door while you slept.",
	"looters": "Beaten by looters who forced the front door on night %d.",
	"balcony": "Cut down by the balcony door when it gave way under wet ash.",
}

const CLUES := {
	"jalert": {
		"title": "J-ALERT on your phone",
		"text": "[ 緊急速報  J-ALERT ]  07:58\n【噴火速報】 Eruption at Mount Fuji, 07:41.\nVolcanic ash is expected to fall across the Tokyo metropolitan area from late morning.\nStay indoors. Close all windows and doors. Do not drive.\n(気象庁 Japan Meteorological Agency)",
		"insight": "",
	},
	"nhk_jma": {
		"title": "NHK emergency broadcast",
		"text": "NHK General. The anchor is in a work jacket. A red L-shaped banner frames the picture: 噴火警戒レベル5 (避難), Alert Level 5, evacuate.\n\nLive from the JMA in Toranomon: \"...the first eruption of Mount Fuji since the Hōei eruption of 1707. The plume has passed fifteen thousand metres. We will update the ashfall forecast, 降灰予報, every hour...\"\n\nThe ticker crawls on: 小田急線・京王線 全線運転見合わせ ... 首都高 全線通行止め ... 外出時はマスクを",
		"insight": "ash_forecast",
	},
	"building_notice": {
		"title": "Notice from building management",
		"text": "A fresh sheet, pushed through the mail slot at dawn, with the management company's red seal:\n\n\"This building's water comes from the receiving tank (受水槽) on the roof. Its vents are open to the air, and ash WILL get into it. From tomorrow morning, do NOT drink the tap water.\nFill your bath and every container you have today.\"",
		"insight": "water_time",
	},
	"prep_booklet": {
		"title": "Ward leaflet: preparing for ashfall",
		"text": "降灰への備え. A ward leaflet folded into the emergency bag. Four lines are circled in red pen:\n\n- Seal gaps around doors, windows and vents with tape (目張り).\n- Wear a dust mask (DS2 / N95). A cloth mask is not enough.\n- After shaking stops, close the gas valve.\n- Wet ash conducts electricity. Expect power cuts.",
		"insight": "prepared",
	},
	"radio_wet_ash": {
		"title": "Looping radio message",
		"text": "Static, then a calm recorded voice, on a loop:\n\n\"...volcanic ash is not soot. It is powdered rock and glass. Dry, it is like flour. Wet, it sets like cement: ten centimetres on a balcony weighs as much as a small car. Rain is forecast. Clear balconies and gutters BEFORE it rains, and wear a mask while you do it...\"",
		"insight": "wet_ash",
	},
	"balcony_view": {
		"title": "View from the balcony door",
		"text": "Through the binoculars the street is grey and silent, every car a soft grey lump.\n\nAcross the road a man in shirtsleeves is sweeping ash off a carport roof with no mask. He stops to cough, then sits down in the grey. He doesn't get up.\n\nYou check the gap under your own balcony door. A thin grey line has already drifted in.",
		"insight": "leak_meter",
	},
	"neighbor_note": {
		"title": "Note slid under the door",
		"text": "Pencil on the back of a Lawson receipt:\n\n\"Tanaka, 302. Someone tried our door last night. Twice. They had a bar. They cleaned out 305: water, masks, everything. The police aren't coming.\nThey come after midnight. Brace your door. Don't open it, whatever they say.\"",
		"insight": "looters",
	},
	"konbini_receipt": {
		"title": "Konbini receipt",
		"text": "A Lawson receipt from last night, crumpled into your work shoes:\n\n  23:12   DS2 マスク 3枚入      ¥1,280\n          2L 天然水 ×2            ¥216\n          養生テープ              ¥398\n\nYou remember now. You bought masks and tape on the way home, half joking about the news. The bag is hanging on the shoe cabinet.",
		"insight": "konbini_bag",
	},
	"evac_bus": {
		"title": "Ward disaster page",
		"text": "The laptop is at 4% battery. The ward's disaster page (区の防災ページ) loads one line at a time:\n\n> 避難バス Evacuation buses will run from major roads\n> at DAWN ON DAY 6, once the roads have been cleared.\n> Bring a mask, water and ID. Do not walk to the ward office.\n\nThe page refuses to refresh.",
		"insight": "evac_bus",
	},
}

const INSIGHTS := {
	"ash_forecast": {
		"title": "Ash forecast",
		"desc": "The HUD shows today's and tomorrow's ashfall (降灰予報).",
	},
	"water_time": {
		"title": "The water will turn",
		"desc": "The HUD warns you before the tap water is contaminated.",
	},
	"prepared": {
		"title": "Prepared",
		"desc": "Unsealed gaps and open gas lines are flagged in the world.",
	},
	"wet_ash": {
		"title": "Rain makes cement",
		"desc": "The HUD shows when the rain comes and how heavy the balcony is.",
	},
	"leak_meter": {
		"title": "Where it gets in",
		"desc": "The seals panel shows how much ash each gap lets in.",
	},
	"looters": {
		"title": "They come after midnight",
		"desc": "You know which nights the looters will try the door.",
	},
	"konbini_bag": {
		"title": "The konbini bag",
		"desc": "Every life starts with 2 extra masks and 1 extra material (tape).",
	},
	"evac_bus": {
		"title": "Evacuation bus, dawn day 6",
		"desc": "The HUD counts down to the bus.",
	},
}

const THEORIES := [
	{"id": "infection", "label": "An infection. The sick are turning."},
	{"id": "invasion", "label": "Something came from the sky."},
	{"id": "radiation", "label": "Fallout. A reactor or a bomb."},
	{"id": "eruption", "label": "The mountain. Fuji has erupted."},
	{"id": "unrest", "label": "Civil unrest. People turned on each other."},
]
const THEORY_MIN_CLUES := 3

## Clue sources (apartment.gd node names) and what they offer in this scenario.
const CLUE_SOURCES := {
	"phone": {"entries": [{"clue": "jalert"}], "idle": "(no new messages)"},
	"tv": {"entries": [{"clue": "nhk_jma", "needs_power": true}], "idle": "(the same banner, over and over)"},
	"radio": {"entries": [{"clue": "radio_wet_ash", "night_only": true}], "idle": "(static... maybe at night)"},
	"laptop": {"entries": [{"clue": "evac_bus", "from": 1440 + 7 * 60, "needs_power": true}], "idle": "(the ward site won't load yet)"},
	"binoculars": {"entries": [{"clue": "balcony_view", "day_only": true, "from": ASH_BEGINS_AT + 60}], "idle": "(nothing to see yet)"},
	"mail": {"entries": [{"clue": "building_notice"}, {"clue": "neighbor_note", "from": 1440 + 7 * 60}], "idle": "(nothing new)"},
}

## Containers: id -> {loot, clue}. Missing keys keep apartment.gd's values.
const LOOT := {
	"emergency_bag": {"loot": {"food": 2, "water": 3, "masks": 2}, "clue": "prep_booklet"},
	"vanity": {"loot": {"medkits": 1, "masks": 1}},
	"shoe_cabinet": {"loot": {"materials": 1}, "clue": "konbini_receipt"},
	"bedroom_closet": {"loot": {"medkits": 1, "materials": 1, "masks": 1}},
}


static func roll_events(rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	ev.append({"at": ASH_BEGINS_AT, "type": "ash_begins"})
	# The mountain shakes the ground too: same rhythm as Outbreak's quakes.
	ev.append({"at": rng.randi_range(13 * 60, 17 * 60), "type": "quake", "strength": 0.9})
	ev.append({"at": 2 * 1440 + rng.randi_range(9 * 60, 18 * 60), "type": "quake", "strength": 0.8})
	ev.append({"at": 3 * 1440 + rng.randi_range(21 * 60, 27 * 60), "type": "quake", "strength": 1.2})
	ev.append({"at": WATER_TAINT_AT, "type": "water_taint", "note": "grey and gritty: undrinkable"})
	ev.append({"at": POWER_CUT_AT, "type": "power_cut"})
	ev.append({"at": 1440 + 7 * 60, "type": "mail", "text": "Something was slid under the front door during the night."})
	return ev


static func roll_tonight_plan(_rng: RandomNumberGenerator, _day: int) -> Array:
	return []  # nobody walks to the windows in this one


## Forecast, rain and looter nights, rolled once per life.
static func on_run_start(game: Node) -> void:
	var rng: RandomNumberGenerator = game.rng
	var mid := [1.15, 0.95, 0.65]
	for i in range(mid.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = mid[i]
		mid[i] = mid[j]
		mid[j] = t
	game.ash_forecast = [0.45, mid[0], mid[1], mid[2], 0.35]
	var rain_day := rng.randi_range(3, 4)
	game.rain_window = [(rain_day - 1) * 1440 + 13 * 60, (rain_day - 1) * 1440 + 19 * 60]
	game.looter_nights = [rng.randi_range(2, 3), rng.randi_range(4, 5)]
	if game.has_insight("konbini_bag"):
		game.masks += 2
		game.materials += 1


## JMA ashfall-forecast wording (降灰予報: 少量 / やや多量 / 多量).
static func forecast_label(rate: float) -> String:
	if rate >= 0.9:
		return "多量 heavy"
	if rate >= 0.5:
		return "やや多量 moderate"
	return "少量 light"
