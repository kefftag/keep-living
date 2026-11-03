extends Node
## Per-run state: clock, survival stats, inventory and world flags.
## Everything here is wiped on death; see meta_progress.gd for what persists.

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

enum Phase { INTRO, DAY, NIGHT, DEAD, WON }

const Scenario := preload("res://scripts/data/scenario_zombie.gd")
const Perks := preload("res://scripts/data/perks.gd")

const DAY_START := 8 * 60
const REST_UNTIL := 19 * 60 + 30
const NIGHT_START := 20 * 60
const NIGHT_END := 30 * 60  # 06:00 the next morning, counted from the current day
const DAY_MIN_PER_SEC := 3.0
const NIGHT_MIN_PER_SEC := 4.0
const THIRST_PER_MIN := 100.0 / (20.0 * 60.0)
const HUNGER_PER_MIN := 100.0 / (30.0 * 60.0)
const WATER_CUT_AT := 1440 + 6 * 60       # day 2, 06:00 (total minutes)
const POWER_CUT_AT := 2 * 1440 + 8 * 60   # day 3, 08:00
const GAS_LEAK_SECONDS := 50.0
const NOISE_MEMORY := 8.0  # seconds a noise lingers for zombie purposes

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
var has_weapon := false

var water_running := true
var power_on := true
var gas_valve_open := true
var gas_leaking := false
var gas_leak_left := 0.0
var bathtub_water := 0
var bathtub_filled_ever := false
var tap_uses := {}  # day -> int

var noise_level := 0.0
var noise_events: Array = []  # [{pos, amount, t}]

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
	start_run()


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
	has_weapon = Meta.has_perk("familiar_grip")
	if Meta.has_perk("hoarder"):
		materials += 3
	if Meta.has_perk("pantry"):
		food += 2
		water += 2
	if Meta.has_perk("first_aid"):
		medkits += 1
	water_running = true
	power_on = true
	gas_valve_open = true
	gas_leaking = false
	gas_leak_left = 0.0
	bathtub_water = 0
	bathtub_filled_ever = false
	tap_uses = {}
	noise_level = 0.0
	noise_events = []
	theory_attempted = false
	zombies_killed = 0
	run_new_clues = []
	death_cause = ""
	player_sleeping = false
	weapon_container = ["shoe_cabinet", "storage_closet", "drawer_chest"][rng.randi_range(0, 2)]
	_roll_events()
	roll_tonight_plan()


## Called when the player dismisses the intro card.
func begin() -> void:
	Meta.record_run_start()
	phase = Phase.DAY
	phase_changed.emit(phase)
	stats_changed.emit()


func _roll_events() -> void:
	scheduled_events = []
	# The first quake always hits on day 1: it is the tutorial for "secure your stuff".
	scheduled_events.append({"at": rng.randi_range(13 * 60, 17 * 60), "type": "quake", "strength": 1.0})
	scheduled_events.append({"at": 2 * 1440 + rng.randi_range(9 * 60, 18 * 60), "type": "quake", "strength": 0.8})
	scheduled_events.append({"at": 3 * 1440 + rng.randi_range(21 * 60, 27 * 60), "type": "quake", "strength": 1.2})
	scheduled_events.append({"at": WATER_CUT_AT, "type": "water_cut"})
	scheduled_events.append({"at": POWER_CUT_AT, "type": "power_cut"})
	scheduled_events.append({"at": 1440 + 7 * 60, "type": "mail", "text": "Something was slid under the front door during the night."})
	scheduled_events.sort_custom(func(a, b): return a["at"] < b["at"])


## Decide which entrances get hit tonight. Rolled in the morning so the
## "they don't climb" insight can show it as a forecast.
func roll_tonight_plan() -> void:
	tonight_plan = []
	var weights := {"front_door": 1.0, "balcony_door": 1.3, "bedroom_window": 0.9, "bath_window": 0.45}
	var count := 2 + day * 2
	for i in count:
		tonight_plan.append(_weighted_pick(weights))


func _weighted_pick(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]


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
		damage(delta * 0.6, "Starvation. The cupboards were empty long before the end.")
	if thirst <= 0.0:
		if bathtub_filled_ever:
			damage(delta * 1.0, "Dehydration.")
		else:
			damage(delta * 1.0, "Dehydration. The taps stopped, and the bathtub was never filled.")

	noise_level = max(0.0, noise_level - delta * 2.5)
	while noise_events.size() > 0 and run_time - noise_events[0]["t"] > NOISE_MEMORY:
		noise_events.pop_front()

	if gas_leaking:
		var before := gas_leak_left
		gas_leak_left -= delta
		if before > 30.0 and gas_leak_left <= 30.0:
			say("The smell of gas is getting stronger. Close the gas main!", "danger")
		elif before > 10.0 and gas_leak_left <= 10.0:
			say("Your head is swimming. The gas!", "danger")
		if gas_leak_left <= 0.0:
			shake.emit(1.4, 1.5)
			damage(9999.0, "Gas explosion. The gas main was never closed after the quake.")


func advance_minutes(m: float) -> void:
	var drain := 0.8 if Meta.has_perk("deep_breath") else 1.0
	minutes += m
	thirst = max(0.0, thirst - THIRST_PER_MIN * m * drain)
	hunger = max(0.0, hunger - HUNGER_PER_MIN * m * drain)
	if phase == Phase.DAY and minutes >= NIGHT_START:
		_begin_night()
	elif phase == Phase.NIGHT and minutes >= NIGHT_END:
		_end_night()
	stats_changed.emit()


func _begin_night() -> void:
	phase = Phase.NIGHT
	say("Night falls on day %d. Something is moving in the corridor." % day, "warn")
	phase_changed.emit(phase)


func _end_night() -> void:
	day += 1
	minutes = float(DAY_START)
	if day > Scenario.NIGHTS_TO_SURVIVE:
		_win()
		return
	phase = Phase.DAY
	roll_tonight_plan()
	say("Dawn. Day %d. The groaning outside fades." % day, "good")
	phase_changed.emit(phase)


## Skip ahead (resting). Events and drain still apply.
func skip_to(target_minutes: float) -> void:
	if phase != Phase.DAY or minutes >= target_minutes:
		return
	advance_minutes(target_minutes - minutes)


func _win() -> void:
	phase = Phase.WON
	Meta.record_win(day)
	phase_changed.emit(phase)
	run_won.emit()


# --- Health & survival -----------------------------------------------------

func damage(amount: float, cause: String) -> void:
	if not is_alive_phase():
		return
	health -= amount
	if amount >= 5.0:
		shake.emit(0.25, 0.25)
	if health <= 0.0:
		health = 0.0
		_die(cause)
	stats_changed.emit()


func heal(amount: float) -> void:
	health = min(max_health, health + amount)
	stats_changed.emit()


func _die(cause: String) -> void:
	death_cause = cause
	phase = Phase.DEAD
	Meta.record_death(cause, day)
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
	if Meta.is_theory_solved(Scenario.ID):
		dmg *= 1.15
	return dmg


func action_speed() -> float:
	return 1.3 if Meta.has_perk("steady_hands") else 1.0


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
	return Meta.has_insight(Scenario, insight_id)


func find_clue(clue_id: String) -> void:
	var is_new := Meta.learn_clue(Scenario.ID, clue_id)
	if is_new:
		run_new_clues.append(clue_id)
		var insight_id: String = Scenario.CLUES[clue_id].get("insight", "")
		if insight_id != "":
			var insight: Dictionary = Scenario.INSIGHTS[insight_id]
			say("INSIGHT: %s. %s" % [insight["title"], insight["desc"]], "good")
	clue_found.emit(clue_id, is_new)


func can_submit_theory() -> bool:
	return (not theory_attempted
		and not Meta.is_theory_solved(Scenario.ID)
		and Meta.known_clue_list(Scenario.ID).size() >= Scenario.THEORY_MIN_CLUES)


func submit_theory(theory_id: String) -> bool:
	theory_attempted = true
	if theory_id == Scenario.THEORY_ANSWER:
		Meta.solve_theory(Scenario.ID)
		say("You name it: an infection. Knowing what you're fighting makes every swing count (+15% damage, permanently).", "good")
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

func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E],
		"interact_alt": [KEY_R],
		"attack": [KEY_SPACE],
		"sneak": [KEY_SHIFT],
		"eat": [KEY_1],
		"drink": [KEY_2],
		"medkit": [KEY_3],
		"journal": [KEY_J, KEY_TAB],
		"pause": [KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", click)
