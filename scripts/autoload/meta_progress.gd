extends Node
## Persistent progress that survives death: known clues (and the insights they
## grant), Echo perks, solved theories and lifetime stats. Saved as JSON in
## user:// so a run can be killed at any time without losing knowledge.

signal changed

const SAVE_PATH := "user://keep_living_meta.json"
const TEST_SAVE_PATH := "user://keep_living_meta_smoke.json"
const SAVE_VERSION := 1

var runs := 0
var deaths := 0
var wins := 0
var best_day := 0
var known_clues: Dictionary = {}      # scenario_id -> Array[String]
var solved_theories: Dictionary = {}  # scenario_id -> true
var perks: Array = []                 # Array[String]
var last_death := {}                  # {"cause": String, "day": int}
var save_path := SAVE_PATH


func _ready() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args():
		# Automated runs never touch the player's real save.
		save_path = TEST_SAVE_PATH
		reset_all()
	load_data()


# --- Knowledge -------------------------------------------------------------

func knows_clue(scenario_id: String, clue_id: String) -> bool:
	return clue_id in known_clues.get(scenario_id, [])


func known_clue_list(scenario_id: String) -> Array:
	return known_clues.get(scenario_id, [])


## Returns true if the clue is new knowledge.
func learn_clue(scenario_id: String, clue_id: String) -> bool:
	if knows_clue(scenario_id, clue_id):
		return false
	var list: Array = known_clues.get(scenario_id, [])
	list.append(clue_id)
	known_clues[scenario_id] = list
	save_data()
	changed.emit()
	return true


func has_insight(scenario: Script, insight_id: String) -> bool:
	for clue_id in known_clue_list(scenario.ID):
		var clue: Dictionary = scenario.CLUES.get(clue_id, {})
		if clue.get("insight", "") == insight_id:
			return true
	return false


func is_theory_solved(scenario_id: String) -> bool:
	return solved_theories.get(scenario_id, false)


func solve_theory(scenario_id: String) -> void:
	solved_theories[scenario_id] = true
	save_data()
	changed.emit()


# --- Echo perks ------------------------------------------------------------

func has_perk(perk_id: String) -> bool:
	return perk_id in perks


func add_perk(perk_id: String) -> void:
	if not has_perk(perk_id):
		perks.append(perk_id)
		save_data()
		changed.emit()


# --- Stats -----------------------------------------------------------------

func record_run_start() -> void:
	runs += 1
	save_data()


func record_death(cause: String, day: int) -> void:
	deaths += 1
	best_day = max(best_day, day)
	last_death = {"cause": cause, "day": day}
	save_data()
	changed.emit()


func record_win(day: int) -> void:
	wins += 1
	best_day = max(best_day, day)
	last_death = {}
	save_data()
	changed.emit()


func reset_all() -> void:
	runs = 0
	deaths = 0
	wins = 0
	best_day = 0
	known_clues = {}
	solved_theories = {}
	perks = []
	last_death = {}
	save_data()
	changed.emit()


# --- Persistence -----------------------------------------------------------

func save_data() -> void:
	var data := {
		"version": SAVE_VERSION,
		"runs": runs,
		"deaths": deaths,
		"wins": wins,
		"best_day": best_day,
		"known_clues": known_clues,
		"solved_theories": solved_theories,
		"perks": perks,
		"last_death": last_death,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Keep Living: could not write save (%s)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_data() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Keep Living: save file unreadable, starting fresh")
		return
	var data: Dictionary = parsed
	runs = int(data.get("runs", 0))
	deaths = int(data.get("deaths", 0))
	wins = int(data.get("wins", 0))
	best_day = int(data.get("best_day", 0))
	known_clues = data.get("known_clues", {})
	solved_theories = data.get("solved_theories", {})
	perks = data.get("perks", [])
	last_death = data.get("last_death", {})
	if last_death.has("day"):
		last_death["day"] = int(last_death["day"])
