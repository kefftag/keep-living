extends Node
## Persistent progress that survives death: known clues (and the insights they
## grant), Echo perks, solved theories and lifetime stats. Saved as JSON in
## user:// so a run can be killed at any time without losing knowledge.
## Knowledge and records are keyed by scenario id; Echoes are shared.

signal changed

const SAVE_NAME := "keep_living_meta.json"
const SAVE_PATH := "user://" + SAVE_NAME
const TEST_SAVE_PATH := "user://keep_living_meta_smoke.json"
## Where saves lived before project.godot set a custom user dir ("KeepLiving").
const OLD_USER_DIR := "Godot/app_userdata/Keep Living"
const SAVE_VERSION := 2

var runs := 0
var deaths := 0
var wins := 0
var best_day := 0
var known_clues: Dictionary = {}      # scenario_id -> Array[String]
var solved_theories: Dictionary = {}  # scenario_id -> true
var perks: Array = []                 # Array[String]
var last_death := {}                  # {"cause": String, "day": int, "scenario": String}
## Per scenario: {"runs", "deaths", "wins", "best_day", "last_death"}.
var records: Dictionary = {}
var last_scenario := ""
var save_path := SAVE_PATH


func _ready() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args():
		# Automated runs never touch the player's real save.
		save_path = TEST_SAVE_PATH
		reset_all()
	else:
		_migrate_old_save()
	load_data()


## Copy a save from the old default user dir so nobody loses their progress
## when the project switched to a custom one.
func _migrate_old_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		return
	var old := OS.get_data_dir().path_join(OLD_USER_DIR).path_join(SAVE_NAME)
	if OS.get_data_dir() == "" or not FileAccess.file_exists(old):
		return
	var text := FileAccess.get_file_as_string(old)
	if text == "":
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		print("Keep Living: migrated save from ", old)


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

func record(scenario_id: String) -> Dictionary:
	if not records.has(scenario_id):
		records[scenario_id] = {"runs": 0, "deaths": 0, "wins": 0, "best_day": 0, "last_death": {}}
	return records[scenario_id]


func runs_in(scenario_id: String) -> int:
	return int(records.get(scenario_id, {}).get("runs", 0))


func wins_in(scenario_id: String) -> int:
	return int(records.get(scenario_id, {}).get("wins", 0))


func best_day_in(scenario_id: String) -> int:
	return int(records.get(scenario_id, {}).get("best_day", 0))


func last_death_in(scenario_id: String) -> Dictionary:
	return records.get(scenario_id, {}).get("last_death", {})


func set_last_scenario(scenario_id: String) -> void:
	if last_scenario != scenario_id:
		last_scenario = scenario_id
		save_data()


func record_run_start(scenario_id: String = "zombie") -> void:
	runs += 1
	record(scenario_id)["runs"] += 1
	last_scenario = scenario_id
	save_data()


func record_death(cause: String, day: int, scenario_id: String = "zombie") -> void:
	deaths += 1
	best_day = max(best_day, day)
	last_death = {"cause": cause, "day": day, "scenario": scenario_id}
	var r := record(scenario_id)
	r["deaths"] += 1
	r["best_day"] = max(int(r["best_day"]), day)
	r["last_death"] = {"cause": cause, "day": day}
	save_data()
	changed.emit()


func record_win(day: int, scenario_id: String = "zombie") -> void:
	wins += 1
	best_day = max(best_day, day)
	last_death = {}
	var r := record(scenario_id)
	r["wins"] += 1
	r["best_day"] = max(int(r["best_day"]), day)
	r["last_death"] = {}
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
	records = {}
	last_scenario = ""
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
		"records": records,
		"last_scenario": last_scenario,
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
	records = data.get("records", {})
	last_scenario = str(data.get("last_scenario", ""))
	if int(data.get("version", 1)) < 2 and records.is_empty() and runs > 0:
		# v1 saves only had Outbreak: its totals are Outbreak's record.
		records["zombie"] = {"runs": runs, "deaths": deaths, "wins": wins, "best_day": best_day,
			"last_death": last_death.duplicate()}
	for id in records:
		var r: Dictionary = records[id]
		for k in ["runs", "deaths", "wins", "best_day"]:
			r[k] = int(r.get(k, 0))
		var ld: Dictionary = r.get("last_death", {})
		if ld.has("day"):
			ld["day"] = int(ld["day"])
		r["last_death"] = ld
