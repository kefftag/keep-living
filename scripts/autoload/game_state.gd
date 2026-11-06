extends Node
## Per-run state: clock, survival stats, inventory and world flags.
## Everything here is wiped on death; see meta_progress.gd for what persists.
##
## The active scenario (`scenario`, a script from scripts/data/scenarios.gd)
## is chosen before a run starts. Everything scenario-specific (clues,
## insights, theory, timeline, story text, which directors run) is read from
## it, never hard-wired.

signal stats_changed
signal phase_changed(phase: int)
signal message(text: String, kind: String)  # kind: info | good | warn | danger
signal clue_found(clue_id: String, is_new: bool)
signal player_died(cause: String)
signal run_won
signal earthquake_warning
signal earthquake(strength: float)
signal world_changed  # power / water flags
signal nav_dirty
signal shake(amount: float, duration: float)
## Game minutes passed (also during a rest skip): scenario systems integrate on it.
signal minutes_advanced(m: float)
## Timeline events the shared EventDirector doesn't know (e.g. Ash's "ash_begins").
signal scenario_event(ev: Dictionary)
## A scenario asks the player to choose (Tide: Tanaka at the door). spec:
## {jp, en, text, options: [{label, note, call: Callable, kind}]}; hud.gd shows it.
signal choice_requested(spec: Dictionary)
## The last input came from a gamepad (true) or the keyboard / mouse (false).
signal input_device_changed(pad: bool)

enum Phase { INTRO, DAY, NIGHT, DEAD, WON }

const Scenarios := preload("res://scripts/data/scenarios.gd")
const Perks := preload("res://scripts/data/perks.gd")

const DAY_START := 8 * 60
const REST_UNTIL := 19 * 60 + 30
const NIGHT_START := 20 * 60
const NIGHT_END := 30 * 60  # 06:00 the next morning, counted from the current day
const DAY_MIN_PER_SEC := 3.0
const NIGHT_MIN_PER_SEC := 4.0
const THIRST_PER_MIN := 100.0 / (20.0 * 60.0)
const HUNGER_PER_MIN := 100.0 / (30.0 * 60.0)
const GAS_LEAK_SECONDS := 50.0
const NOISE_MEMORY := 8.0  # seconds a noise lingers for zombie purposes

var scenario: Script = Scenarios.ZOMBIE
## True until the player leaves the title screen this session.
var show_title := true

var phase: int = Phase.INTRO
var day := 1
var minutes := float(DAY_START)
var run_time := 0.0

var max_health := 100.0
var health := 100.0
var hunger := 100.0
var thirst := 100.0

var food := 0
var water := 0
var materials := 0
var medkits := 0
var masks := 0
var has_weapon := false

var water_running := true
var water_note := ""        # why the tap is off, when it isn't simply dry
var power_on := true
var gas_valve_open := true
var gas_leaking := false
var gas_leak_left := 0.0
var bathtub_water := 0
var bathtub_filled_ever := false
var tap_uses := {}  # day -> int

var noise_level := 0.0
var noise_events: Array = []  # [{pos, amount, t}]

# Ash (scenario_ash.gd); idle in other scenarios.
var ash_falling := false
var ash_forecast: Array = []   # ashfall per day (index day - 1)
var rain_window: Array = []    # [start, end] total minutes
var looter_nights: Array = []
var ash_cm := 0.0              # depth outside
var dust := 0.0                # indoor ash, 0..100 (air quality = 100 - dust)
var leak := 0.0                # current sum of gap leaks (set by the AshDirector)
var balcony_load := 0.0        # 0..100, collapses at 100
var mask_left := 0.0           # game minutes left on the mask you're wearing
var looters_active := false

# Tide (scenario_tide.gd); idle in other scenarios.
var storm_curve: Array = []    # [[minute, wind 0..1], ...] rolled per life
var storm_level := 0.0         # wind right now, 0..1 (set by the TideDirector)
var flood_depth := 0.0         # metres of water in the street
var tanaka_night := 0
var phone_battery := 100.0     # percent
var phone_plugged := false
var power_banks := 0
var has_crank := false
var light_on := false          # the phone light (set by the player)
var sick_left := 0.0           # game minutes of a bad stomach left
var nights_override := 0       # > 0: rescue comes after this many nights instead
var flags := {}                # per-run story flags ("tanaka", "signal", ...)
var end_note := ""             # extra line on the rescue screen
var _crank_ready_t := 0.0

var scheduled_events: Array = []  # [{at, type, ...}] consumed by EventDirector
var tonight_plan: Array = []      # entrance ids, one per zombie, rolled each morning
var weapon_container := ""
var theory_attempted := false
var zombies_killed := 0
var run_new_clues: Array = []
var death_cause := ""
var player_sleeping := false

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_input()
	var watch := PadWatch.new()
	watch.name = "PadWatch"
	watch.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(watch)
	if "--smoke-test" in OS.get_cmdline_user_args():
		scenario = Scenarios.ZOMBIE
	else:
		var last := Meta.last_scenario if Meta.last_scenario != "" else Scenarios.DEFAULT_ID
		var s: Script = Scenarios.by_id(last)
		scenario = s if Scenarios.lock_reason(s.UNLOCK_AFTER_WIN) == "" else Scenarios.ZOMBIE
	start_run()


## Pick the scenario for the next run (takes effect on start_run / reload).
func select_scenario(id: String) -> void:
	scenario = Scenarios.by_id(id)
	Meta.set_last_scenario(scenario.ID)


func scenario_id() -> String:
	return scenario.ID


func is_seal_mode() -> bool:
	return scenario.MODE == "seal"


func is_storm_mode() -> bool:
	return scenario.MODE == "storm"


## Nights to survive this life (an early rescue signal can shorten it).
func nights_goal() -> int:
	return nights_override if nights_override > 0 else scenario.NIGHTS_TO_SURVIVE


# --- Run lifecycle ---------------------------------------------------------

func start_run() -> void:
	rng.randomize()
	phase = Phase.INTRO
	day = 1
	minutes = float(DAY_START)
	run_time = 0.0
	max_health = 125.0 if Meta.has_perk("thick_skin") else 100.0
	health = max_health
	hunger = 85.0
	thirst = 80.0
	food = 1
	water = 1
	materials = 2
	medkits = 0
	masks = 0
	has_weapon = Meta.has_perk("familiar_grip")
	if Meta.has_perk("hoarder"):
		materials += 3
	if Meta.has_perk("pantry"):
		food += 2
		water += 2
	if Meta.has_perk("first_aid"):
		medkits += 1
	water_running = true
	water_note = ""
	power_on = true
	gas_valve_open = true
	gas_leaking = false
	gas_leak_left = 0.0
	bathtub_water = 0
	bathtub_filled_ever = false
	tap_uses = {}
	noise_level = 0.0
	noise_events = []
	ash_falling = false
	ash_forecast = []
	rain_window = []
	looter_nights = []
	ash_cm = 0.0
	dust = 0.0
	leak = 0.0
	balcony_load = 0.0
	mask_left = 0.0
	looters_active = false
	storm_curve = []
	storm_level = 0.0
	flood_depth = 0.0
	tanaka_night = 0
	phone_battery = 100.0
	phone_plugged = false
	power_banks = 0
	has_crank = false
	light_on = false
	sick_left = 0.0
	nights_override = 0
	flags = {}
	end_note = ""
	_crank_ready_t = 0.0
	theory_attempted = false
	zombies_killed = 0
	run_new_clues = []
	death_cause = ""
	player_sleeping = false
	weapon_container = ["shoe_cabinet", "storage_closet", "bedroom_closet"][rng.randi_range(0, 2)]
	_roll_events()
	roll_tonight_plan()
	scenario.on_run_start(self)


## Called when the player dismisses the intro card.
func begin() -> void:
	show_title = false
	Meta.record_run_start(scenario.ID)
	phase = Phase.DAY
	phase_changed.emit(phase)
	stats_changed.emit()


func _roll_events() -> void:
	scheduled_events = scenario.roll_events(rng)
	scheduled_events.sort_custom(func(a, b): return a["at"] < b["at"])


## Decide which entrances get hit tonight. Rolled in the morning so the
## "they don't climb" insight can show it as a forecast.
func roll_tonight_plan() -> void:
	tonight_plan = scenario.roll_tonight_plan(rng, day)


# --- Clock -----------------------------------------------------------------

func is_alive_phase() -> bool:
	return phase == Phase.DAY or phase == Phase.NIGHT


func total_minutes() -> float:
	return (day - 1) * 1440.0 + minutes


func clock_string() -> String:
	var m := int(minutes) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


func minutes_per_second() -> float:
	return DAY_MIN_PER_SEC if phase == Phase.DAY else NIGHT_MIN_PER_SEC


func _process(delta: float) -> void:
	if not is_alive_phase():
		return
	run_time += delta
	advance_minutes(delta * minutes_per_second())
	if not is_alive_phase():
		return

	if hunger <= 0.0:
		var starve := "starvation"
		if flags.get("tanaka") == "in" and scenario.DEATHS.has("starvation_guest"):
			starve = "starvation_guest"
		damage(delta * 0.6, death_text(starve))
	if thirst <= 0.0:
		damage(delta * 1.0, death_text("dehydration" if bathtub_filled_ever else "dehydration_no_tub"))

	noise_level = max(0.0, noise_level - delta * 2.5)
	while noise_events.size() > 0 and run_time - noise_events[0]["t"] > NOISE_MEMORY:
		noise_events.pop_front()

	if gas_leaking:
		var before := gas_leak_left
		gas_leak_left -= delta
		if before > 30.0 and gas_leak_left <= 30.0:
			say("The smell of gas is getting stronger. Close the gas valve!", "danger")
		elif before > 10.0 and gas_leak_left <= 10.0:
			say("Your head is swimming. The gas!", "danger")
		if gas_leak_left <= 0.0:
			shake.emit(1.4, 1.5)
			damage(9999.0, "Gas explosion. The gas valve was never closed after the quake.")


func death_text(key: String) -> String:
	return scenario.DEATHS.get(key, key)


func advance_minutes(m: float) -> void:
	var drain := 0.8 if Meta.has_perk("deep_breath") else 1.0
	minutes += m
	thirst = max(0.0, thirst - THIRST_PER_MIN * m * drain)
	hunger = max(0.0, hunger - HUNGER_PER_MIN * m * drain)
	minutes_advanced.emit(m)
	if not is_alive_phase():
		return
	if phase == Phase.DAY and minutes >= NIGHT_START:
		_begin_night()
	elif phase == Phase.NIGHT and minutes >= NIGHT_END:
		_end_night()
	stats_changed.emit()


func _begin_night() -> void:
	phase = Phase.NIGHT
	say(scenario.NIGHT_MESSAGE % day, "warn")
	phase_changed.emit(phase)


func _end_night() -> void:
	day += 1
	minutes = float(DAY_START)
	if day > nights_goal():
		_win()
		return
	phase = Phase.DAY
	roll_tonight_plan()
	say(scenario.DAWN_MESSAGE % day, "good")
	phase_changed.emit(phase)


## Skip ahead (resting). Events and drain still apply.
func skip_to(target_minutes: float) -> void:
	if phase != Phase.DAY or minutes >= target_minutes:
		return
	advance_minutes(target_minutes - minutes)


func _win() -> void:
	phase = Phase.WON
	Meta.record_win(day, scenario.ID)
	phase_changed.emit(phase)
	run_won.emit()


# --- Health & survival -----------------------------------------------------

func damage(amount: float, cause: String) -> void:
	if not is_alive_phase():
		return
	health -= amount
	if amount >= 5.0:
		shake.emit(0.25, 0.25)
		Sfx.play("bite" if amount < 50.0 else "hit_flesh", null, -2.0)
	if health <= 0.0:
		health = 0.0
		_die(cause)
	stats_changed.emit()


## Slow damage with no hit feedback (breathing ash, even over a rest skip).
func wear_down(amount: float, cause: String) -> void:
	if not is_alive_phase() or amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		health = 0.0
		_die(cause)


func heal(amount: float) -> void:
	health = min(max_health, health + amount)
	stats_changed.emit()


func _die(cause: String) -> void:
	death_cause = cause
	phase = Phase.DEAD
	Meta.record_death(cause, day, scenario.ID)
	phase_changed.emit(phase)
	player_died.emit(cause)


func eat() -> void:
	if food <= 0:
		say("You have nothing to eat.", "warn")
	elif hunger >= 98.0:
		say("You're not hungry.", "info")
	else:
		food -= 1
		hunger = min(100.0, hunger + 35.0)
		say("You eat something cold out of a packet.", "info")
	stats_changed.emit()


func drink() -> void:
	if water <= 0:
		say("You have no water.", "warn")
	elif thirst >= 98.0:
		say("You're not thirsty.", "info")
	else:
		water -= 1
		thirst = min(100.0, thirst + 40.0)
		say("You drink.", "info")
	stats_changed.emit()


func use_medkit() -> void:
	if medkits <= 0:
		say("You have no first-aid kits.", "warn")
	elif health >= max_health:
		say("You're not hurt.", "info")
	else:
		medkits -= 1
		var amount := 40.0 + (20.0 if has_insight("bites_turn") else 0.0)
		heal(amount)
		say("You clean and bandage your wounds.", "good")
	stats_changed.emit()


func mask_minutes() -> float:
	if not is_seal_mode():
		return 0.0
	var m: float = scenario.MASK_MINUTES
	if scenario.THEORY_BONUS == "masks" and Meta.is_theory_solved(scenario.ID):
		m *= 1.5
	return m


## Put on a fresh dust mask (key 4).
func wear_mask() -> void:
	if not is_seal_mode():
		return
	if masks <= 0:
		say("You have no masks left.", "warn")
	elif mask_left > 60.0:
		say("Your mask is still good for %d hours." % int(mask_left / 60.0), "info")
	else:
		masks -= 1
		mask_left = mask_minutes()
		say("You press a fresh DS2 mask over your nose and mouth. (%d hours)" % int(mask_left / 60.0), "good")
	stats_changed.emit()


## The scenario's item key (4 / D-pad left): a mask in Ash, the crank charger in Tide.
func use_item() -> void:
	if is_seal_mode():
		wear_mask()
	elif is_storm_mode():
		crank_phone()


## Tide: one turn of the hand-crank charger.
func crank_phone() -> void:
	if not has_crank:
		say("You have nothing to charge the phone with.", "warn")
		return
	if phone_battery >= 99.5:
		say("The phone is fully charged.", "info")
		return
	if run_time < _crank_ready_t:
		return
	_crank_ready_t = run_time + scenario.CRANK_COOLDOWN
	phone_battery = min(100.0, phone_battery + scenario.CRANK_GAIN)
	thirst = max(0.0, thirst - scenario.CRANK_THIRST)
	Sfx.play("crank", null, -6.0)
	say("You wind the charger until your arm aches. (Phone %d%%)" % int(phone_battery), "info")
	stats_changed.emit()


func air_quality() -> float:
	return 100.0 - dust


func cook_meal() -> bool:
	if food <= 0:
		say("You have nothing to cook.", "warn")
		return false
	food -= 1
	hunger = min(100.0, hunger + 65.0)
	heal(5.0)
	say("A hot meal. For a moment, things feel normal.", "good")
	return true


# --- Inventory ---------------------------------------------------------------

func collect_loot(loot: Dictionary, source_name: String) -> void:
	var parts: Array = []
	for key in loot:
		var amount: int = loot[key]
		if amount <= 0:
			continue
		match key:
			"food":
				food += amount
				parts.append("%d food" % amount)
			"water":
				water += amount
				parts.append("%d water" % amount)
			"materials":
				materials += amount
				parts.append("%d materials" % amount)
			"medkits":
				medkits += amount
				parts.append("%d first-aid kit" % amount)
			"masks":
				masks += amount
				parts.append("%d dust mask%s" % [amount, "" if amount == 1 else "s"])
			"power_banks":
				power_banks += amount
				parts.append("a charged MOBILE BATTERY" if amount == 1 else "%d mobile batteries" % amount)
			"crank":
				if not has_crank:
					has_crank = true
					parts.append("a HAND-CRANK CHARGER (key %s)" % glyph("mask"))
			"weapon":
				if not has_weapon:
					has_weapon = true
					parts.append("a METAL BAT")
	if parts.is_empty():
		say("%s: nothing useful." % source_name, "info")
	else:
		say("%s: found %s." % [source_name, ", ".join(parts)], "good")
	stats_changed.emit()


func spend_materials(amount: int) -> bool:
	if materials < amount:
		say("Not enough materials (need %d)." % amount, "warn")
		return false
	materials -= amount
	stats_changed.emit()
	return true


func weapon_damage() -> float:
	var dmg := 45.0 if has_weapon else 15.0
	if scenario.THEORY_BONUS == "damage" and Meta.is_theory_solved(scenario.ID):
		dmg *= 1.15
	return dmg


func action_speed() -> float:
	var s := 1.3 if Meta.has_perk("steady_hands") else 1.0
	if is_storm_mode() and phase == Phase.NIGHT and not power_on and not light_on:
		s /= scenario.DARK_SLOWDOWN  # fumbling in the dark
	return s


# --- Noise -------------------------------------------------------------------

func make_noise(pos: Vector3, amount: float) -> void:
	if amount <= 0.0:
		return
	noise_level = min(100.0, noise_level + amount)
	noise_events.append({"pos": pos, "amount": amount, "t": run_time})


func noise_near(pos: Vector3, radius: float = 6.0) -> float:
	var total := 0.0
	for ev in noise_events:
		if (ev["pos"] as Vector3).distance_to(pos) <= radius:
			total += ev["amount"]
	return total


# --- Knowledge -------------------------------------------------------------

func has_insight(insight_id: String) -> bool:
	return Meta.has_insight(scenario, insight_id)


func find_clue(clue_id: String) -> void:
	var is_new := Meta.learn_clue(scenario.ID, clue_id)
	if is_new:
		run_new_clues.append(clue_id)
		var insight_id: String = scenario.CLUES[clue_id].get("insight", "")
		if insight_id != "":
			var insight: Dictionary = scenario.INSIGHTS[insight_id]
			say("INSIGHT: %s. %s" % [insight["title"], insight["desc"]], "good")
	clue_found.emit(clue_id, is_new)


func can_submit_theory() -> bool:
	return (not theory_attempted
		and not Meta.is_theory_solved(scenario.ID)
		and Meta.known_clue_list(scenario.ID).size() >= scenario.THEORY_MIN_CLUES)


func submit_theory(theory_id: String) -> bool:
	theory_attempted = true
	if theory_id == scenario.THEORY_ANSWER:
		Meta.solve_theory(scenario.ID)
		say(scenario.THEORY_SOLVED_SAY, "good")
		return true
	say("It doesn't fit what you've seen. You'll have to think about it next time.", "warn")
	return false


func roll_perk_choices() -> Array:
	var options: Array = []
	for perk_id in Perks.PERKS:
		if not Meta.has_perk(perk_id):
			options.append(perk_id)
	options.shuffle()
	return options.slice(0, 3)


# --- Messages ----------------------------------------------------------------

func say(text: String, kind: String = "info") -> void:
	message.emit(text, kind)


# --- Input map (built in code so project.godot stays readable) ----------------
# Keyboard and mouse, plus a gamepad layout for the Steam Deck (Xbox names):
#   left stick move, right stick look, A use, X second action, RT swing,
#   LB phone light, D-pad eat / drink / first aid / item, Y journal,
#   Start menu, B back (ui_cancel), L3 walk quietly (toggle).

const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"interact_alt": [KEY_R],
	"attack": [KEY_SPACE],
	"sneak": [KEY_SHIFT],
	"flashlight": [KEY_F],
	"eat": [KEY_1],
	"drink": [KEY_2],
	"medkit": [KEY_3],
	"mask": [KEY_4],
	"journal": [KEY_J, KEY_TAB],
	"pause": [KEY_ESCAPE],
}
const PAD_BUTTONS := {
	"interact": [JOY_BUTTON_A],
	"interact_alt": [JOY_BUTTON_X],
	"flashlight": [JOY_BUTTON_LEFT_SHOULDER],
	"eat": [JOY_BUTTON_DPAD_UP],
	"drink": [JOY_BUTTON_DPAD_RIGHT],
	"medkit": [JOY_BUTTON_DPAD_DOWN],
	"mask": [JOY_BUTTON_DPAD_LEFT],
	"journal": [JOY_BUTTON_Y],
	"pause": [JOY_BUTTON_START],
	"sneak_toggle": [JOY_BUTTON_LEFT_STICK],
}
## action -> [axis, direction]
const PAD_AXES := {
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}
## What each action's key cap says, on the keyboard and on a gamepad.
const GLYPHS := {
	"move": ["WASD", "LS"],
	"look": ["Mouse", "RS"],
	"interact": ["E", "A"],
	"interact_alt": ["R", "X"],
	"attack": ["LMB", "RT"],
	"sneak": ["Shift", "L3"],
	"flashlight": ["F", "LB"],
	"eat": ["1", "D↑"],
	"drink": ["2", "D→"],
	"medkit": ["3", "D↓"],
	"mask": ["4", "D←"],
	"journal": ["J", "Y"],
	"pause": ["Esc", "Start"],
	"back": ["Esc", "B"],
	"accept": ["E", "A"],
}
const STICK_DEADZONE := 0.2

## True while the last input came from a gamepad: key caps show pad glyphs.
var using_pad := false


func _setup_input() -> void:
	for action in KEYS:
		_ensure_action(action)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", click)
	for action in PAD_BUTTONS:
		_ensure_action(action)
		for b in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		_ensure_action(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)
		if action.begins_with("move") or action.begins_with("look"):
			InputMap.action_set_deadzone(action, STICK_DEADZONE)
	InputMap.action_set_deadzone("attack", 0.4)
	# Menus: the left stick moves focus too; D-pad, A and B are Godot's
	# defaults for ui_*, but make sure of them.
	for pair in [["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0],
			["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = pair[1]
		ev.axis_value = pair[2]
		if not InputMap.action_has_event(pair[0], ev):
			InputMap.action_add_event(pair[0], ev)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_up", JOY_BUTTON_DPAD_UP],
			["ui_down", JOY_BUTTON_DPAD_DOWN], ["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT]]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], ev):
			InputMap.action_add_event(pair[0], ev)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


## The key cap text for an action ("E" / "A"), for the input device in use.
func glyph(action: String) -> String:
	var g: Array = GLYPHS.get(action, [action, action])
	return g[1] if using_pad else g[0]


## Watches input even while the tree is paused (menus), unlike Game itself.
class PadWatch extends Node:
	func _input(event: InputEvent) -> void:
		Game.watch_input(event)


func watch_input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0:
		pad = false
	if pad != using_pad:
		set_using_pad(pad)


func set_using_pad(pad: bool) -> void:
	using_pad = pad
	input_device_changed.emit(pad)
