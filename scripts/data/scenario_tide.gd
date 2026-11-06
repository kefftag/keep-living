extends RefCounted
## Scenario 3: "Tide" (水害).
##
## A super typhoon (超大型台風) comes ashore over Tokyo Bay at high tide. The
## storm surge and a breached Arakawa levee flood the eastern wards. The flat
## is on the third floor, above the water, but the building is cut off for
## days: the water stands in the street, rises up the stairwell and drowns the
## basement electrical room and pumps.
##
## Days 1-2 are the storm: wind-flung debris hits the balcony side, so the
## entrances become windows to tape (an X of 養生テープ) and board. Then the
## water: the power dies on the first evening, the phone battery becomes the
## light and the news, the tap runs brown and has to be boiled while the gas
## lasts. One night a neighbour from the flooded floor below knocks.

const ID := "tide"
const TITLE := "Tide"
const TITLE_JP := "水害"
const TAGLINE := "The river is higher than the street."
const BLURB := "A super typhoon and a storm surge have flooded Tokyo's eastern wards. Your third-floor flat is above the water, but the building is cut off. Tape and board the windows, keep your phone alive, boil what you drink, and decide who you open the door to."
const MODE := "storm"
const DIRECTORS := ["events", "tide"]
## Opens after a rescue in either earlier scenario.
const UNLOCK_AFTER_WIN := ["zombie", "ash"]
const THEORY_ANSWER := "flood"
const THEORY_SOLVED_SAY := "You name it: the water. A typhoon and the surge behind it. You know this will last days, so you ration the phone properly (it drains 30% slower, permanently)."
const THEORY_KNOWN_TEXT := "You know what this is: a typhoon and a storm surge. (Phone battery drains 30% slower)"
const THEORY_BONUS := "battery"
## Rescue boats come at dawn on day 5 (an early signal can bring them a day sooner).
const NIGHTS_TO_SURVIVE := 4

# --- Timeline (total game minutes; day 1 starts at 0) ---------------------------
const POWER_CUT_AT := 18 * 60               # day 1, 18:00: the basement electrical room floods
const WATER_TAINT_AT := 1440 + 6 * 60       # day 2, 06:00: flood water in the receiving tank
const GAS_CUT_FROM := 2 * 1440 + 6 * 60     # day 3, 06:00-18:00 (rolled): the gas meter trips
const GAS_CUT_TO := 2 * 1440 + 18 * 60
const SIGNAL_BY := 2 * 1440 + 30 * 60       # a signal before dawn on day 4 brings the boat then

## Wind strength (0..1) through the storm, [minute, level], interpolated.
## The eye passes in the small hours of night 1; the back side of the storm
## (吹き返し) comes round on night 2 at BACKSIDE (rolled) times this curve.
const STORM_CURVE := [
	[9 * 60, 0.0], [11 * 60, 0.2], [15 * 60, 0.4], [19 * 60, 0.65], [23 * 60, 0.9],
	[25 * 60, 1.0], [28 * 60, 1.0], [31 * 60, 0.55], [1440 + 13 * 60, 0.3],
	[1440 + 20 * 60, 0.85], [1440 + 26 * 60, 0.85], [1440 + 30 * 60, 0.35],
	[2 * 1440 + 10 * 60, 0.08], [2 * 1440 + 14 * 60, 0.0],
]
const BACKSIDE := [0.75, 1.0]
## Flood depth in the street (metres), [minute, depth]. 2F floor is 3.4 m up,
## 3F (ours) 6.3 m: the water never reaches the flat.
const FLOOD_CURVE := [
	[19 * 60, 0.0], [22 * 60, 0.8], [26 * 60, 2.9], [30 * 60, 4.1], [1440 + 14 * 60, 4.4],
	[2 * 1440 + 12 * 60, 4.2], [3 * 1440 + 12 * 60, 3.8], [4 * 1440 + 12 * 60, 3.3],
]
const SECOND_FLOOR := 3.4
const OUR_FLOOR := 6.3

# --- Balance -----------------------------------------------------------------------
## Flying debris: gusts per game hour at full strength, damage per hit.
const GUSTS_PER_HOUR := 3.0
const DEBRIS_DAMAGE := [8.0, 16.0]
const NIGHT_MULT := 1.3            # the worst of it comes in the dark
## Where the wind throws things: the balcony side takes almost all of it.
const GUST_WEIGHTS := {"balcony_door": 1.5, "bedroom_window": 1.0, "bath_window": 0.2}
## Damage multiplier by level: bare glass, an X of tape, plywood over tape.
## Night 1 throws ~15 hits (~170 raw damage) at the balcony door: bare or
## taped it blows in, boarded it comes through needing a patch or two.
const LEVEL_DAMAGE := [1.0, 0.85, 0.2]
const TAPE_COST := 1
const BOARD_COST := 3
const PATCH_COST := 1
const PATCH_HP := 60.0
const REPAIR_COST := 4             # boarding over a window that blew in
## Flying glass when a window blows in, within SHATTER_RADIUS; tape holds the
## shards (飛散防止), boards stop them.
const SHATTER_HURT := 35.0
const SHATTER_HURT_MULT := [1.0, 0.25, 0.0]
const SHATTER_RADIUS := 3.2
const EXPOSURE_HP_PER_MIN := 0.035 # per broken window (max 2) x wind strength: the storm gets in
## The pots and drying rack on the balcony fly at the first strong gust.
const LOOSE_GUST := 0.55
const LOOSE_HIT := 45.0

## The phone (percent). The flat starts with it half charged.
const PHONE_START := 35.0
const PHONE_CHARGE_PER_MIN := 0.3  # plugged in, while there's power
const PHONE_STANDBY_PER_MIN := 0.01
const PHONE_LIGHT_PER_SEC := 0.1   # real seconds, phone light on
const PHONE_READ_COST := 3.0       # each news push or alert you open
const LOW_POWER_MULT := 0.6        # the "low power mode" insight
const THEORY_BATTERY_MULT := 0.7
const CRANK_GAIN := 3.0            # one turn of the hand-crank charger
const CRANK_THIRST := 2.0
const CRANK_COOLDOWN := 5.0        # real seconds
const POWER_BANK_GAIN := 50.0      # a mobile battery, used automatically
const POWER_BANK_AT := 10.0
const SIGNAL_LIGHT_COST := 10.0    # flashing SOS at night
const DARK_SLOWDOWN := 1.6         # actions at night without a light take longer

## Water.
const BOILS_PER_DAY := 2           # tap pressure from the roof tank
const BOIL_WATER := 2
const RAW_THIRST := 35.0           # drinking it unboiled
const SICK_MINUTES := 720.0
const SICK_HP_PER_MIN := 0.06

## Tanaka from 202: knocks on one of these nights, waits this many real seconds.
const TANAKA_NIGHTS := [1, 2]
const TANAKA_AT := [0.55, 0.7]     # fraction of the night
const TANAKA_WAIT := 75.0
const GUEST_FOOD := 1              # each dawn while he stays
const GUEST_WATER := 1
const GUEST_GIFT := 2              # materials he brings
const GUEST_DAILY := 1             # materials he finds each day

## Storm points: the entrances, same ids as Outbreak's barricades.
const STORM_POINTS := ["balcony_door", "bedroom_window", "bath_window", "front_door"]

# --- Story text ----------------------------------------------------------------
const INTRO_FIRST := "Tokyo, Koto ward. A third-floor 1LDK, two kilometres from the bay.\n\nIt's 07:58. Your phone is screaming, and rain is hammering sideways on the balcony glass. Typhoon No. 19 comes ashore tonight, at high tide.\n\nStay inside. Keep the glass in the frames. Keep the phone alive. Keep living."
const INTRO_AGAIN := "You wake up. 07:58. Rain on the glass, your phone screaming.\n\nAgain.\n\nYou remember the sound of the water in the stairwell."
const GOAL_TEXT := "Survive %d nights. The storm hits the balcony side hardest: tape and board the glass, bring in what's on the balcony.\nThen the water: the power, the tap and the gas fail one by one. Rescue comes by boat."
const WAKE_MESSAGE := "Your phone is buzzing on the bedside table. The wind is rising."
const NIGHT_MESSAGE := "Night falls on day %d. The wind screams around the building."
const DAWN_MESSAGE := "Dawn. Day %d. Grey light over brown water."
const RESCUE_JP := "救助"
const RESCUE_EN := "RESCUED"
const RESCUE_TEXT := "Dawn, day %d. An outboard motor cuts through the silence. A grey SDF boat noses between the drowned cars, and a crew in orange life jackets shouts up at the balconies.\n\nThey lower you a life jacket. You kept living."
const RESCUE_SOUND := "boat"
const KILLS_LABEL := ""
const DEATHS := {
	"starvation": "Starvation. The cupboards were empty long before the boats came.",
	"starvation_guest": "Starvation. You shared the last of the food with Tanaka.",
	"dehydration": "Dehydration.",
	"dehydration_no_tub": "Dehydration. The tap ran brown, and the bathtub was never filled.",
	"glass": "Cut down by flying glass when the %s blew in.",
	"glass_sleep": "You were asleep when the %s blew in.",
	"exposure": "Cold and soaked through. The storm came in through the broken window and never left.",
	"sick": "Dysentery. The brown tap water was never boiled.",
}

const CLUES := {
	"jalert": {
		"title": "Evacuation alert on your phone",
		"text": "[ 緊急速報  エリアメール ]  07:58\n【警戒レベル5】緊急安全確保  江東区\nLevel 5: EMERGENCY SAFETY MEASURES.\nFlooding is occurring or imminent. It is already too dangerous to go to an evacuation centre.\nMove to the highest floor you can reach NOW (垂直避難).\n(江東区役所 Koto City Office)",
		"insight": "",
	},
	"nhk_typhoon": {
		"title": "NHK typhoon broadcast",
		"text": "NHK General. A reporter in a helmet leans into the wind on the Arakawa embankment. The map in the corner shows the typhoon's track, a red circle swallowing Tokyo Bay.\n\n\"...台風第19号, central pressure 915 hectopascals, maximum gusts of 70 metres per second. It makes landfall tonight, close to high tide. A storm surge special warning (高潮特別警報) is in force for the bay. The strongest winds will be in the small hours, and again from the other side tomorrow night as it passes...\"",
		"insight": "storm_forecast",
	},
	"hazard_map": {
		"title": "Hazard map on the fridge",
		"text": "The ward hazard map (江東5区大規模水害ハザードマップ) is held to the fridge by a magnet shaped like a fish. On the cover, in huge letters: ここにいてはダメです. \"You can't stay here.\"\n\nYour block is shaded dark purple: 3 to 5 metres of water, standing for TWO WEEKS OR MORE. Next to it, in your own handwriting from the day you moved in: \"3F = OK?\"",
		"insight": "water_level",
	},
	"building_notice": {
		"title": "Notice from building management",
		"text": "A sheet pushed under every door yesterday, with the management company's red seal:\n\n\"The building's electrical room (電気室) and water pumps are in the BASEMENT. If the basement floods, power and water to all units will stop.\nThe tank on the roof holds about one night's water. Fill your bath and every container you have TODAY.\nDo not use the lift.\"",
		"insight": "water_time",
	},
	"prep_leaflet": {
		"title": "Ward leaflet: preparing for a typhoon",
		"text": "台風への備え. A ward leaflet in the emergency bag. Someone has ticked the list in red pen:\n\n- Tape windows in an X to stop glass flying (飛散防止). Board them if you can.\n- Bring EVERYTHING in from the balcony: poles, pots, drying racks.\n- Fill the bath.\n- Charge your phone and your mobile battery now.\n- Keep away from the windows during the storm.",
		"insight": "prepared_storm",
	},
	"river_level": {
		"title": "River level on your phone",
		"text": "防災速報. A push from the river app, with a red graph climbing off its own scale:\n\n荒川 岩淵水門(上) 水位 8.62 m  氾濫危険水位 超過\n【氾濫発生情報】 The levee has failed in Adachi ward. Flood water is spreading south.\n\nUnder it, the phone's own notice: \"Battery 20%. Turn on Low Power Mode?\" You turn it on. You should have done that hours ago.",
		"insight": "low_power",
	},
	"balcony_view": {
		"title": "View from the balcony door",
		"text": "Through the binoculars the street is a brown river. Car roofs, a vending machine on its side, a bicycle turning slowly in the current.\n\nA plastic drying rack from the next block cartwheels across the gap and smashes into a balcony two floors down. The wind comes off the bay, straight at your side of the building. The corridor side barely feels it.",
		"insight": "wind_side",
	},
	"radio_rescue": {
		"title": "Radio broadcast",
		"text": "The battery radio, through the hiss. NHK Radio 1, a tired voice reading the same list again:\n\n\"...the Self-Defense Forces will begin boat rescues in Koto, Edogawa and Sumida wards at DAWN ON THE FIFTH DAY, once the wind has dropped and the current has slowed. Residents on upper floors: stay where you are. Do not try to wade. The water is contaminated and there are open manholes...\"",
		"insight": "rescue_day",
	},
	"tanaka_story": {
		"title": "Tanaka's story",
		"text": "Tanaka from 202 sits in your genkan in a borrowed towel, dripping. He's seventy-one.\n\n\"The water came under my door at two. By three it was over the kotatsu. My wife's photographs...\" He stops. \"In the 2019 flood in Nagano, the boats went to the balconies with white sheets first. White cloth, by day. A light, by night. Hang something white once the wind drops. They'll come for you sooner.\"",
		"insight": "signal",
	},
	"tanaka_note": {
		"title": "Tanaka's note",
		"text": "Wet paper, pushed under your door in the night. The pencil has run:\n\n\"I understand. I'm waiting on the stairs. The water is three steps below the landing. If it comes higher I'll go up to the roof.\nThe boats look for white cloth on the balconies. A light at night. Hang a sheet.\nTanaka, 202\"\n\nYou open the door. The stairwell is empty. The water is two steps below the landing.",
		"insight": "signal",
	},
}

const INSIGHTS := {
	"storm_forecast": {
		"title": "Storm forecast",
		"desc": "The HUD shows the wind now and when the storm peaks.",
	},
	"water_level": {
		"title": "How high it will go",
		"desc": "The HUD shows the flood depth in the street, floor by floor.",
	},
	"water_time": {
		"title": "The water will turn",
		"desc": "The HUD warns you before the tap water is contaminated.",
	},
	"prepared_storm": {
		"title": "Prepared",
		"desc": "Bare glass, loose balcony things and an unplugged phone are flagged in the world.",
	},
	"low_power": {
		"title": "Low Power Mode",
		"desc": "Your phone uses 40% less battery: light, news and standby.",
	},
	"wind_side": {
		"title": "Where the wind hits",
		"desc": "Each day you can see how hard each window will be hit tonight.",
	},
	"rescue_day": {
		"title": "Boats at dawn, day 5",
		"desc": "The HUD counts down to the rescue.",
	},
	"signal": {
		"title": "White cloth, by day",
		"desc": "Once the wind drops, you can signal the boats from the balcony door for an earlier pickup.",
	},
}

const THEORIES := [
	{"id": "infection", "label": "An infection. The sick are turning."},
	{"id": "invasion", "label": "Something came from the sky."},
	{"id": "radiation", "label": "Fallout. A reactor or a bomb."},
	{"id": "eruption", "label": "The mountain. Fuji has erupted."},
	{"id": "flood", "label": "The water. A typhoon and a storm surge."},
	{"id": "unrest", "label": "Civil unrest. People turned on each other."},
]
const THEORY_MIN_CLUES := 3

## Clue sources. Phone entries need battery and cost some of it to read.
const CLUE_SOURCES := {
	"phone": {"entries": [{"clue": "jalert", "battery": PHONE_READ_COST},
		{"clue": "river_level", "from": 13 * 60, "battery": PHONE_READ_COST}], "idle": "(no new alerts)"},
	"tv": {"entries": [{"clue": "nhk_typhoon", "needs_power": true}], "idle": "(the typhoon track, over and over)"},
	"radio": {"entries": [{"clue": "radio_rescue", "from": 1440 + 6 * 60}], "idle": "(storm warnings... the news comes later)", "verb": "Listen to"},
	"laptop": {"entries": [], "idle": "(no connection: the router is dead)"},
	"binoculars": {"entries": [{"clue": "balcony_view", "day_only": true, "from": 12 * 60}], "idle": "(only rain on the glass yet)"},
	"mail": {"entries": [{"clue": "building_notice"}, {"clue": "tanaka_note", "flag": "tanaka_note"}], "idle": "(nothing new)"},
}

## Containers: id -> {loot, clue}. Missing keys keep apartment.gd's values.
const LOOT := {
	"emergency_bag": {"loot": {"food": 2, "water": 3, "crank": 1}, "clue": "prep_leaflet"},
	"fridge": {"loot": {"food": 2, "water": 2}, "clue": "hazard_map"},
	"bedroom_closet": {"loot": {"medkits": 1, "materials": 1, "power_banks": 1}},
	"vanity": {"loot": {"medkits": 1}},
	"shoe_cabinet": {"loot": {"materials": 1}},
}


static func roll_events(rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	ev.append({"at": 11 * 60, "type": "say", "kind": "warn", "text": "The rain thickens into grey sheets. The balcony door rattles in its frame."})
	ev.append({"at": POWER_CUT_AT, "type": "power_cut"})
	ev.append({"at": WATER_TAINT_AT, "type": "water_taint", "note": "brown and smells of drains: boil it first",
		"text": "The tap coughs and runs brown. Flood water has got into the tank in the basement. Boil it, or don't drink it."})
	ev.append({"at": rng.randi_range(GAS_CUT_FROM, GAS_CUT_TO), "type": "gas_cut"})
	ev.append({"at": 22 * 60, "type": "flood_rising"})
	return ev


static func roll_tonight_plan(_rng: RandomNumberGenerator, _day: int) -> Array:
	return []  # nobody comes for the windows: the wind does


## Storm strength and Tanaka's night, rolled once per life.
static func on_run_start(game: Node) -> void:
	var rng: RandomNumberGenerator = game.rng
	var back := rng.randf_range(BACKSIDE[0], BACKSIDE[1])
	var curve: Array = []
	for k in STORM_CURVE:
		var v: float = k[1]
		if k[0] >= 1440 + 18 * 60 and k[0] <= 1440 + 30 * 60:
			v *= back
		curve.append([k[0], v])
	game.storm_curve = curve
	game.tanaka_night = TANAKA_NIGHTS[rng.randi_range(0, TANAKA_NIGHTS.size() - 1)]
	game.phone_battery = PHONE_START


## Linear interpolation in a [[minute, value], ...] table.
static func curve_at(curve: Array, minute: float) -> float:
	if curve.is_empty():
		return 0.0
	if minute <= curve[0][0]:
		return curve[0][1]
	for i in range(1, curve.size()):
		if minute < curve[i][0]:
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			return lerpf(a[1], b[1], (minute - a[0]) / float(b[0] - a[0]))
	return curve[curve.size() - 1][1]


## JMA wind wording (強風 / 非常に強い / 猛烈).
static func wind_label(level: float) -> String:
	if level >= 0.8:
		return "猛烈な風 violent"
	if level >= 0.5:
		return "暴風 storm force"
	if level >= 0.2:
		return "強風 strong"
	if level > 0.02:
		return "やや強い風 breezy"
	return "穏やか calm"
