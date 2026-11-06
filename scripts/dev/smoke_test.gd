extends Node
## Scripted playthrough used for automated checks:
##   godot --headless -- --smoke-test
## Optionally saves screenshots when a renderer is available:
##   godot -- --smoke-test --shots=/some/dir
## Prints "SMOKE OK" and exits 0 on success, exits 1 on the first failure.

const Scenarios := preload("res://scripts/data/scenarios.gd")

var main: Node
var _shots_dir := ""
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.substr(8)
	if DisplayServer.get_name() != "headless":
		# Screenshot runs open a real window: keep it from taking focus or
		# catching clicks, so the person at the computer can keep working.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	_run()


## The run is driven by direct calls, never by real input. Swallow every real
## keyboard / mouse / focus event (this node is added last, so it sees them
## first) so a stray key or click on the window can't skip the intro or move
## the player.
func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_failed = true
		printerr("  FAIL ", what)


func _shot(name: String) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join(name + ".png"))
	print("  shot ", name)


## Put the player at `pos` looking at `target` (yaw on the body, pitch on the head).
func _pose(player, pos: Vector3, target: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var eye: Vector3 = pos + Vector3(0, player.EYE_HEIGHT, 0)
	var d := target - eye
	player.rotation.y = atan2(-d.x, -d.z)
	player.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


## Extra views of materials and fittings (`--tour`, with --shots), daytime.
func _tour(player, apt) -> void:
	apt.doors["bath_door"].set_open(true)
	apt.doors["toilet_door"].set_open(true)
	await _wait(0.6)
	for v in [
		["t1_washroom_bath", Vector3(1.6, 0.05, 4.4), Vector3(0.9, 0.8, 6.9)],
		["t2_washroom", Vector3(2.4, 0.05, 4.9), Vector3(0.3, 1.0, 4.2)],
		["t3_kitchen_counter", Vector3(4.7, 0.05, 4.1), Vector3(4.8, 0.85, 5.3)],
		["t4_toilet", Vector3(2.3, 0.05, 5.7), Vector3(2.27, 0.5, 7.2)],
		["t5_balcony", Vector3(1.2, 0.0, -0.4), Vector3(5.5, 0.6, -1.4)],
		["t6_skyline", Vector3(3.0, 0.0, -1.1), Vector3(3.0, -4.0, -30.0)],
		["t7_corridor", Vector3(3.3, -0.1, 8.1), Vector3(9.5, 0.8, 7.6)],
		["t8_floor_close", Vector3(4.5, 0.05, 1.0), Vector3(4.0, 0.0, 1.8)],
		["t9_bedroom", Vector3(2.2, 0.05, 2.8), Vector3(0.5, 0.8, 0.5)],
	]:
		_pose(player, v[1], v[2])
		await _wait(0.4)
		await _shot(v[0])
	apt.doors["bath_door"].set_open(false)
	apt.doors["toilet_door"].set_open(false)
	await _wait(0.6)


## Which scene load this is: 0 title + Outbreak, 1 Outbreak again, 2 Ash
## (to the evacuation), 3 Ash again (to a death). Static, so it survives the
## scene reloads between lives.
static var stage := -1


func _run() -> void:
	stage += 1
	match stage:
		1:
			_second_life()
			return
		2:
			_ash_life()
			return
		3:
			_ash_second_life()
			return
		4:
			_tide_life()
			return
		5:
			_tide_second_life()
			return
	print("SMOKE: start (runs so far: %d)" % Meta.runs)
	var hud = main.hud
	var player = main.player
	var apt = main.apartment
	await _wait(0.5)
	await _front_end(hud)
	await _shot("01_intro")
	_check(hud.overlay_kind == "intro", "intro card is shown")
	hud._start_run()
	await _wait(0.6)
	_check(Game.phase == Game.Phase.DAY, "run begins in the day phase")
	await _shot("02_day")

	# Navigation: stairwell to bedroom, and over the genkan step.
	var map: RID = player.get_world_3d().navigation_map
	var bedroom := Vector3(1.6, 0, 2.0)
	var path := NavigationServer3D.map_get_path(map, Vector3(10.0, -0.15, 8.0), bedroom, true)
	_check(path.size() > 1 and path[path.size() - 1].distance_to(bedroom) < 0.6, "navmesh connects stairwell to bedroom (%d points)" % path.size())
	var hall := Vector3(3.18, 0, 5.0)
	path = NavigationServer3D.map_get_path(map, Vector3(3.2, -0.15, 6.9), hall, true)
	_check(path.size() > 1 and path[path.size() - 1].distance_to(hall) < 0.4, "navmesh climbs the genkan step")

	# First person: looking at the phone focuses it.
	var phone = apt.nav_region.get_node("phone")
	_pose(player, Vector3(1.75, 0.05, 1.15), phone.global_position + Vector3(0, 0.45, 0))
	await _wait(0.3)
	_check(player.focus == phone, "looking at the phone focuses it (focus: %s)" % [player.focus.name if player.focus else "none"])
	phone.perform(false)
	await _wait(0.2)
	_check(Meta.knows_clue("zombie", "jalert"), "phone gives the J-ALERT clue")
	_check(hud.overlay_kind == "reading" and get_tree().paused, "clue popup pauses the game")
	await _shot("03_clue")
	hud._close()

	# Walking: from the genkan up the step into the hallway.
	_pose(player, Vector3(3.2, -0.1, 6.95), Vector3(3.2, 1.4, 4.0))
	await _wait(0.2)
	Input.action_press("move_up")
	await _wait(1.6)
	Input.action_release("move_up")
	_check(player.global_position.z < 6.2 and player.global_position.y > -0.05, "player can walk up the genkan step (at %s)" % player.global_position)

	# Doors.
	var wdoor = apt.doors["washroom_door"]
	wdoor.perform(false)
	await _wait(0.6)
	_check(wdoor.is_open, "washroom door opens")
	wdoor.perform(false)
	await _wait(0.6)
	_check(not wdoor.is_open, "washroom door closes")

	# Some views of the place.
	_pose(player, Vector3(3.2, 0.05, 5.6), Vector3(3.6, 1.2, 1.0))
	await _wait(0.3)
	await _shot("04_hallway_to_ldk")
	_pose(player, Vector3(3.3, 0.05, 2.6), Vector3(5.2, 0.9, 5.2))
	await _wait(0.3)
	await _shot("05_kitchen")
	_pose(player, Vector3(5.6, 0.05, 2.8), Vector3(2.5, 1.0, 1.0))
	await _wait(0.3)
	await _shot("06_living_to_bedroom")
	_pose(player, Vector3(3.2, 0.05, 5.2), Vector3(3.3, 0.6, 7.3))
	await _wait(0.3)
	await _shot("07_genkan")
	if "--tour" in OS.get_cmdline_user_args():
		await _tour(player, apt)
		_pose(player, Vector3(3.2, 0.05, 5.2), Vector3(3.3, 0.6, 7.3))
		await _wait(0.2)

	# Looting and barricading.
	var mats_before: int = Game.materials
	apt.nav_region.get_node("storage_closet").perform(false)
	_check(Game.materials == mats_before + 4, "storage shelves give 4 materials")
	var balcony = apt.barricades["balcony_door"]
	var hp_before: float = balcony.max_hp
	balcony.perform(false)
	_check(balcony.level == 1 and balcony.max_hp == hp_before + 100.0, "reinforcing raises level and max hp")

	# Securing furniture.
	Game.materials += 1
	var shelf = apt.nav_region.get_node("bookshelf")
	shelf.perform(false)
	_check(shelf.secured, "bookshelf can be secured")

	# Bathtub.
	apt.nav_region.get_node("bathtub").perform(false)
	_check(Game.bathtub_water == 8, "bathtub fills to 8 bottles")

	# Earthquake while asleep: the unsecured wardrobe falls across the bed.
	var bed = apt.nav_region.get_node("bed")
	var wardrobe = apt.nav_region.get_node("wardrobe")
	Game.scheduled_events.push_front({"at": 0, "type": "quake", "strength": 1.0})
	player.sleep_on(bed)
	_check(wardrobe._in_fall_zone(player.global_position), "the pillow is in the wardrobe's fall zone")
	# Wake up and get out of the way in time.
	Input.action_press("move_down")
	await _wait(0.1)
	Input.action_release("move_down")
	await _wait(2.2)
	_check(wardrobe.fallen, "unsecured wardrobe falls in the quake")
	_check(not shelf.fallen, "secured bookshelf stays up")
	_check(Game.is_alive_phase(), "getting off the bed in time saves you")
	_check(Game.gas_leaking, "open gas cock leaks after the quake")
	_pose(player, Vector3(1.9, 0.05, 2.6), Vector3(1.2, 0.3, 0.6))
	await _wait(0.3)
	await _shot("08_quake")
	apt.nav_region.get_node("stove").perform(false)
	_check(not Game.gas_leaking and not Game.gas_valve_open, "closing the gas stops the leak")

	# Night: zombies spawn and walk to their entrances.
	Game.tonight_plan = ["front_door", "balcony_door", "bath_window", "bedroom_window"]
	Game.minutes = Game.NIGHT_START - 0.5
	await _wait(0.3)
	_check(Game.phase == Game.Phase.NIGHT, "clock rolls into night")
	var director = main.get_node("NightDirector")
	director._schedule.clear()
	var spawned: Array = []
	for id in ["front_door", "balcony_door", "bath_window", "bedroom_window"]:
		spawned.append(director.spawn_at(id))
	Engine.time_scale = 4.0
	await _wait(24.0)  # timers scale with time_scale: 24 game seconds in ~6 real ones
	Engine.time_scale = 1.0
	for z in spawned:
		var id: String = z.target.point_id
		_check(z.state == z.State.BASH, "zombie walked to the %s and is bashing it (state %d, at %s)" % [id, z.state, z.global_position])
	_check(apt.barricades["balcony_door"].hp < apt.barricades["balcony_door"].max_hp, "bashing damages the barricade")
	player.flashlight.visible = true
	_pose(player, Vector3(4.55, 0.05, 2.6), Vector3(4.55, 1.2, -0.8))
	await _wait(0.3)
	await _shot("09_night_balcony")
	player.flashlight.visible = false

	# Breach: an infected gets in through the front door and has to shove
	# through the closed washroom door to reach you.
	var front = apt.barricades["front_door"]
	front.take_damage(99999.0)
	_check(front.broken, "front door can be breached")
	_check(front.get_prompt(false) != "" or front._zombie_blocking(), "a breached door can be boarded back up")
	_pose(player, Vector3(1.4, 0.05, 4.5), Vector3(2.73, 1.3, 4.15))
	Game.hunger = 100.0
	Game.thirst = 100.0
	var hp_start: float = Game.health
	var z_new = director.spawn_at("front_door")
	Engine.time_scale = 3.0
	for i in 80:
		await _wait(0.5)
		if Game.health < hp_start:
			break
	Engine.time_scale = 1.0
	_check(wdoor.is_open, "the infected shoved the washroom door open")
	_check(Game.health < hp_start, "an inside zombie hunts down and bites the player")
	_check(Game.is_alive_phase(), "one bite isn't fatal")
	if is_instance_valid(z_new):
		_pose(player, player.global_position, z_new.global_position + Vector3(0, 1.3, 0))
	await _wait(0.2)
	await _shot("10_breach")

	# Combat: swinging the bat kills the zombie in front of the player.
	Game.heal(Game.max_health)
	Game.has_weapon = true
	var kills_before: int = Game.zombies_killed
	var target = null
	var best := INF
	for z in get_tree().get_nodes_in_group("zombie"):
		var d: float = z.global_position.distance_to(player.global_position)
		if z.is_alive() and d < best:
			best = d
			target = z
	_check(target != null and best < 1.6, "the zombie that bit you is within reach (%.2f m)" % best)
	for i in 8:
		if target == null or not is_instance_valid(target) or not target.is_alive():
			break
		_pose(player, player.global_position, target.global_position + Vector3(0, 1.2, 0))
		player.swing_cd = 0.0
		player._swing()
		await _wait(0.1)
	_check(Game.zombies_killed > kills_before, "the bat kills a zombie")
	await _wait(0.5)  # let the swing settle
	await _shot("10b_bat")

	# Death -> Echo choice -> restart.
	if Game.is_alive_phase():
		Game.damage(9999.0, "Smoke test.")
	await _wait(2.0)
	_check(hud.overlay_kind == "end", "death screen is shown")
	_check(Meta.deaths >= 1, "death is recorded in meta progress")
	await _shot("11_death")
	var perks_before := Meta.perks.size()
	var choices := Game.roll_perk_choices()
	if choices.size() > 0:
		Meta.add_perk(choices[0])
		_check(Meta.perks.size() == perks_before + 1, "an Echo can be chosen")

	if _failed:
		print("SMOKE FAILED")
		await _quit(1)
		return
	print("SMOKE: dying worked, waking up again...")
	hud._restart()  # reloads the scene; a fresh smoke test runs _second_life()


## Runs in the reloaded scene after the first life ended.
func _second_life() -> void:
	print("SMOKE: second life")
	var hud = main.hud
	await _wait(0.5)
	_check(hud.overlay_kind == "intro", "intro card is shown again")
	_check(Meta.perks.size() == 1, "the chosen Echo carried over")
	_check(Meta.knows_clue("zombie", "jalert"), "clues are remembered after death")
	hud._start_run()
	await _wait(0.3)
	_check(Game.day == 1 and Game.health == Game.max_health, "world and stats reset for the new life")
	_check(Meta.runs == 2, "second run counted")
	var seen := []
	var on_clue := func(_id, is_new): seen.append(is_new)
	Game.clue_found.connect(on_clue)
	main.apartment.nav_region.get_node("phone").perform(false)
	Game.clue_found.disconnect(on_clue)
	_check(seen == [false], "re-reading a known clue isn't treated as new")
	_check(Meta.best_day_in("zombie") >= 1 and Meta.runs_in("zombie") == 2, "Outbreak keeps its own record (best day %d)" % Meta.best_day_in("zombie"))
	if _failed:
		print("SMOKE FAILED")
		await _quit(1)
		return
	hud._close()
	print("SMOKE: switching to Ash...")
	hud._title_play("ash")  # a different scenario: reloads into its intro


# --- Front end -------------------------------------------------------------------

func _front_end(hud) -> void:
	_check(hud.overlay_kind == "title", "title screen is shown at boot")
	_check(get_tree().paused, "the world waits behind the title")
	_check(Scenarios.lock_reason(Scenarios.TIDE.UNLOCK_AFTER_WIN) != "", "Tide is locked before any rescue")
	var pad_ok := true
	for action in ["move_up", "move_down", "move_left", "move_right", "look_left", "look_up", "interact", "interact_alt",
			"attack", "flashlight", "eat", "drink", "medkit", "mask", "journal", "pause", "sneak_toggle"]:
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		pad_ok = pad_ok and has_pad
	_check(pad_ok, "every action has a gamepad binding")
	_check(get_viewport().gui_get_focus_owner() is Button, "the title menu has gamepad focus")
	await _shot("00_title")
	hud._show_scenarios()
	await _wait(0.3)
	_check(hud.overlay_kind == "scenarios", "scenario select opens")
	await _shot("00b_scenarios")
	hud._show_settings(hud._show_title)
	await _wait(0.3)
	_check(hud.overlay_kind == "settings", "settings open")
	await _shot("00c_settings")
	var slider: HSlider = hud.overlay_box.find_child("slider_mouse_sensitivity", true, false)
	_check(slider != null, "settings have a mouse sensitivity slider")
	if slider:
		slider.value = 1.5
	_check(is_equal_approx(Settings.mouse_factor(), 1.5), "moving the slider changes the setting")
	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.path) == OK and is_equal_approx(float(cfg.get_value("settings", "mouse_sensitivity", 0.0)), 1.5), "settings are saved to %s" % Settings.path)
	var toggle: Button = hud.overlay_box.find_child("toggle_reduce_shake", true, false)
	if toggle:
		toggle.button_pressed = true
	_check(is_equal_approx(Settings.shake_scale(), 0.25), "reduce camera shake toggles")
	Settings.reset_defaults()
	_check(is_equal_approx(Settings.mouse_factor(), 1.0) and Settings.shake_scale() == 1.0, "settings reset to defaults")
	hud._show_credits(hud._show_title)
	await _wait(0.3)
	_check(hud.overlay_kind == "credits", "credits open")
	await _shot("00d_credits")
	hud._show_title()
	await _wait(0.2)
	hud._title_play("zombie")
	await _wait(0.3)


# --- Ash ---------------------------------------------------------------------------

func _ash_life() -> void:
	print("SMOKE: Ash")
	var hud = main.hud
	var player = main.player
	var apt = main.apartment
	await _wait(0.5)
	_check(Game.scenario.ID == "ash", "Ash is the active scenario")
	_check(hud.overlay_kind == "intro", "Ash opens on its intro card")
	await _shot("20_ash_intro")
	hud._start_run()
	await _wait(0.3)
	_check(Game.phase == Game.Phase.DAY, "Ash run begins")
	_check(main.get_node_or_null("NightDirector") == null and main.get_node_or_null("AshDirector") != null
		and main.get_node_or_null("LooterDirector") != null, "Ash runs its own directors, not the night siege")
	var ash = main.get_node("AshDirector")
	var seal = ash.seal
	_check(seal.levels.size() == 7 and apt.get_node_or_null("vent_ldk") != null, "7 seal points, vents on the walls")
	_check(apt.barricades["front_door"].mode_handler == seal, "entrances became seal points")
	var types := Game.scheduled_events.map(func(e): return e["type"])
	_check("ash_begins" in types and "quake" in types and "water_taint" in types, "eruption timeline: ash, tremors, tainted water")
	Game.gas_valve_open = false  # no gas leaks in the scripted run
	_pose(player, Vector3(3.2, 0.05, 5.0), Vector3(3.2, 1.4, 7.0))

	# Clues come from the same sources with Ash's content.
	apt.nav_region.get_node("phone").perform(false)
	_check(Meta.knows_clue("ash", "jalert") and not Meta.knows_clue("ash", "radio_sound"), "phone gives Ash's J-ALERT")
	await _wait(0.2)
	await _shot("20b_ash_clue")
	hud._close()
	apt.nav_region.get_node("tv").perform(false)
	hud._close()
	_check(Game.has_insight("ash_forecast"), "the NHK broadcast gives the ash forecast insight")

	# The plume arrives; unsealed, ash gets in.
	Game.advance_minutes(10 * 60 + 1 - Game.minutes)
	await _wait(0.2)
	_check(Game.ash_falling, "ash begins to fall at 10:00")
	var leak0: float = seal.total_leak()
	Game.advance_minutes(90)
	var dust1: float = Game.dust
	_check(dust1 > 5.0, "unsealed, ash gets in (air %d)" % int(Game.air_quality()))
	_pose(player, Vector3(4.55, 0.05, 2.4), Vector3(4.2, 1.1, -2.0))
	await _wait(0.4)
	await _shot("21_ash_day")

	# Seal everything twice: tape, then sheeting.
	Game.materials += 30
	for id in seal.nodes:
		seal.nodes[id].perform(false)
		seal.nodes[id].perform(false)
	_check(seal.total_leak() < leak0 * 0.15, "sealing cuts the leak (%.1f -> %.1f)" % [leak0, seal.total_leak()])
	Game.advance_minutes(120)
	_check(Game.dust < dust1, "with the gaps sealed the air clears (dust %d -> %d)" % [int(dust1), int(Game.dust)])
	_pose(player, Vector3(2.0, 0.05, 2.2), Vector3(1.2, 1.3, 0.0))
	await _wait(0.3)
	await _shot("23_ash_sealed_window")
	_pose(player, Vector3(5.2, 0.05, 2.0), Vector3(6.27, 2.07, 1.3))
	await _wait(0.3)
	_check(player.focus == apt.get_node("vent_ldk"), "looking at the LDK vent focuses it (focus: %s)" % [player.focus.name if player.focus else "none"])
	await _shot("23b_ash_vent")

	# A tremor peels tape.
	var before: int = seal.levels.values().reduce(func(a, b): return a + b)
	seal.peel(Game.rng, 1)
	_check(seal.levels.values().reduce(func(a, b): return a + b) == before - 1, "a tremor peels tape off a seal")

	# Masks.
	Game.masks = 1
	Game.wear_mask()
	_check(Game.masks == 0 and Game.mask_left > 300.0, "a mask goes on and lasts hours")

	# Day 2: tap water turns, then the power goes.
	Game.heal(Game.max_health)
	Game.hunger = 100.0
	Game.thirst = 100.0
	Game.advance_minutes(Game.NIGHT_START - Game.minutes + 1)
	await _wait(0.2)
	_check(Game.phase == Game.Phase.NIGHT, "night falls in Ash too")
	Game.advance_minutes(Game.NIGHT_END - Game.minutes + 1)
	await _wait(0.3)
	_check(Game.day == 2 and not Game.water_running and Game.water_note != "", "tap water is contaminated on day 2")
	_check(apt.nav_region.get_node("tap").get_prompt(false) == "", "the tainted tap can't fill bottles")
	Game.advance_minutes(16 * 60 - Game.minutes)
	await _wait(0.2)
	_check(not Game.power_on, "the power fails on day 2")

	# Looters at the front door.
	Game.heal(Game.max_health)
	Game.food = 4
	Game.water = 4
	var door = apt.barricades["front_door"]
	var looters = main.get_node("LooterDirector")
	looters.begin_attempt()
	_check(Game.looters_active, "looters try the front door")
	_check(door.get_prompt(true) != "", "you can shout through the door at them")
	var hp0: float = door.hp
	Engine.time_scale = 4.0
	await _wait(8.0)
	Engine.time_scale = 1.0
	_check(door.hp < hp0, "the looters damage the door (%d -> %d)" % [int(hp0), int(door.hp)])
	_pose(player, Vector3(3.25, 0.05, 5.4), Vector3(3.27, 1.1, 7.3))
	await _wait(0.3)
	await _shot("22_ash_looters")
	var hp_before: float = Game.health
	door.take_damage(99999.0)
	await _wait(0.2)
	_check(not Game.looters_active and Game.food < 4 and Game.health < hp_before, "a forced door costs supplies and health")
	_check(seal.factor("front_door") == Game.scenario.BROKEN_FACTOR, "a forced door lets the ash pour in")
	door.perform(false)
	_check(not door.broken, "the broken door can be boarded over")

	# The balcony: shovel it, then let it collapse.
	var bal = apt.barricades["balcony_door"]
	Game.balcony_load = 50.0
	bal.perform(true)
	_check(Game.balcony_load == 0.0, "shovelling clears the balcony")
	Game.balcony_load = 99.95
	Game.advance_minutes(10)
	_check(bal.broken, "wet ash brings the balcony door down at 100%")

	# Rescue: the evacuation bus at dawn after night 5.
	Game.heal(Game.max_health)
	Game.day = Game.scenario.NIGHTS_TO_SURVIVE
	Game.phase = Game.Phase.NIGHT
	Game.minutes = Game.NIGHT_END - 0.5
	await _wait(2.0)
	_check(Game.phase == Game.Phase.WON and hud.overlay_kind == "end", "the evacuation bus comes at dawn")
	_check(Meta.wins_in("ash") == 1 and Meta.wins_in("zombie") == 0, "the rescue is recorded for Ash only")
	_check(Meta.best_day_in("ash") == 6, "Ash's best day is tracked")
	await _shot("24_ash_evacuated")
	if _failed:
		print("SMOKE FAILED")
		await _quit(1)
		return
	hud._restart()


func _ash_second_life() -> void:
	print("SMOKE: Ash, second life")
	var hud = main.hud
	await _wait(0.5)
	_check(Game.scenario.ID == "ash" and hud.overlay_kind == "intro", "the next life stays in Ash")
	_check(Game.has_insight("ash_forecast"), "Ash insights are remembered")
	hud._start_run()
	await _wait(0.3)
	_check(Meta.runs_in("ash") == 2, "Ash lives are counted separately")
	Game.ash_falling = true
	Game.dust = 100.0
	Game.health = 3.0
	Game.advance_minutes(60)
	_check(Game.phase == Game.Phase.DEAD and "Ash in the lungs" in Game.death_cause, "breathing ash kills (%s)" % Game.death_cause)
	await _wait(2.0)
	_check(hud.overlay_kind == "end", "Ash death screen is shown")
	_check("lungs" in str(Meta.last_death_in("ash").get("cause", "")), "the death is recorded for Ash")
	await _shot("25_ash_death")
	_check(Scenarios.lock_reason(Scenarios.TIDE.UNLOCK_AFTER_WIN) == "", "a rescue in Ash unlocks Tide")
	if _failed:
		print("SMOKE FAILED")
		await _quit(1)
		return
	await _wait(0.3)
	hud._show_scenarios()
	await _wait(0.4)
	await _shot("26_scenarios_tide_unlocked")
	print("SMOKE: switching to Tide...")
	hud._title_play("tide")


# --- Tide --------------------------------------------------------------------------

func _tide_life() -> void:
	print("SMOKE: Tide")
	var hud = main.hud
	var player = main.player
	var apt = main.apartment
	await _wait(0.5)
	_check(Game.scenario.ID == "tide", "Tide is the active scenario")
	_check(hud.overlay_kind == "intro", "Tide opens on its intro card")
	await _shot("30_tide_intro")
	hud._start_run()
	await _wait(0.3)
	var tide = main.get_node_or_null("TideDirector")
	_check(tide != null and main.get_node_or_null("NightDirector") == null, "Tide runs its own director, not the night siege")
	if tide == null:
		print("SMOKE FAILED")
		await _quit(1)
		return
	var guard = tide.guard
	_check(guard.nodes.size() == 4 and apt.barricades["balcony_door"].mode_handler == guard, "the entrances became storm points")
	_check(hud.battery_row.visible and not hud.air_row.visible, "the HUD shows the phone battery")
	_check(Game.nights_goal() == 4, "rescue comes after 4 nights")

	# The phone: alerts cost battery, and it charges while plugged in.
	var phone = apt.nav_region.get_node("phone")
	var b0: float = Game.phone_battery
	phone.perform(false)
	_check(Meta.knows_clue("tide", "jalert") and Game.phone_battery < b0, "the evacuation alert costs battery (%d%% -> %d%%)" % [int(b0), int(Game.phone_battery)])
	await _wait(0.2)
	await _shot("30b_tide_alert")
	hud._close()
	_check(phone.get_prompt(true) != "", "the phone can be plugged in")
	phone.perform(true)
	var b1: float = Game.phone_battery
	Game.advance_minutes(60)
	_check(Game.phone_plugged and Game.phone_battery > b1 + 10.0, "plugged in, the phone charges (%d%%)" % int(Game.phone_battery))
	apt.nav_region.get_node("tv").perform(false)
	hud._close()
	_check(Game.has_insight("storm_forecast"), "the NHK broadcast gives the storm forecast")
	apt.nav_region.get_node("fridge").perform(false)
	await _wait(0.1)
	hud._close()
	_check(Meta.knows_clue("tide", "hazard_map"), "the hazard map is on the fridge")
	apt.nav_region.get_node("emergency_bag").perform(false)
	await _wait(0.1)
	hud._close()
	_check(Game.has_crank and Game.has_insight("prepared_storm"), "the emergency bag has the crank charger and the typhoon leaflet")
	await _wait(0.1)
	_check("Wind" in hud.info_label.text, "the storm forecast shows on the HUD")

	# Storm prep: bring the balcony things in, tape and board the glass.
	var bal = apt.barricades["balcony_door"]
	var bed_w = apt.barricades["bedroom_window"]
	_check("pots" in bal.get_prompt(true), "the balcony things can be brought in")
	bal.perform(true)
	_check(not tide.loose_on_balcony(), "the pots and drying rack come inside")
	Game.materials += 20
	bed_w.perform(false)
	_check(guard.levels["bedroom_window"] == 1 and bed_w.get_node_or_null("StormVisual") != null, "an X of tape goes on the bedroom window")
	bal.perform(false)
	bal.perform(false)
	_check(guard.levels["balcony_door"] == 2, "the balcony door is taped and boarded")
	Game.advance_minutes(14 * 60 - Game.minutes)  # 14:00, the wind is up
	await _wait(0.6)
	_check(Game.storm_level > 0.25, "the wind rises through day 1 (%.2f)" % Game.storm_level)
	_pose(player, Vector3(1.4, 0.05, 2.3), Vector3(1.2, 1.2, 0.0))
	await _wait(0.5)
	await _shot("31_tide_taped_window")
	_pose(player, Vector3(4.55, 0.05, 2.6), Vector3(4.55, 1.2, -0.5))
	await _wait(0.4)
	await _shot("32_tide_boarded_door")

	# A blown-in window: flying glass and a hole to board over.
	var hp_before: float = Game.health
	_pose(player, Vector3(1.3, 0.05, 1.2), Vector3(1.2, 1.2, 0.0))
	guard.levels["bedroom_window"] = 0
	guard.hit("bedroom_window", 9999.0)
	_check(bed_w.broken and Game.health < hp_before, "an untaped window blows in and cuts you (%d hp)" % int(hp_before - Game.health))
	bed_w.perform(false)
	_check(not bed_w.broken and guard.levels["bedroom_window"] == 2, "a blown-in window can be boarded over")
	Game.heal(Game.max_health)

	# Power and water.
	Game.advance_minutes(18 * 60 + 1 - Game.minutes)
	await _wait(0.2)
	_check(not Game.power_on and not Game.phone_plugged, "the power fails on the first evening and the phone stops charging")

	# Night 1: the peak of the storm, the surge, Tanaka at the door.
	Game.hunger = 100.0
	Game.thirst = 100.0
	Game.advance_minutes(Game.NIGHT_START - Game.minutes + 1)
	await _wait(0.2)
	_check(Game.phase == Game.Phase.NIGHT, "night falls")
	Game.advance_minutes(25 * 60 - Game.minutes)
	await _wait(0.5)
	_check(Game.storm_level > 0.9, "the storm peaks in the small hours (%.2f)" % Game.storm_level)
	_check(Game.flood_depth > 2.0, "the surge floods the street (%.1f m)" % Game.flood_depth)
	player.flashlight.visible = true
	var b2: float = Game.phone_battery
	await _wait(1.0)
	_check(Game.phone_battery < b2, "the phone light drains the battery")
	_pose(player, Vector3(4.2, 0.05, 2.6), Vector3(4.0, 1.4, -0.3))
	await _wait(0.4)
	await _shot("33_tide_night_storm")
	player.flashlight.visible = false
	Game.light_on = false

	tide.begin_knock()
	_check(tide.is_knocking() and apt.barricades["front_door"].get_prompt(false) != "", "Tanaka knocks, and you can answer the door")
	apt.barricades["front_door"].perform(false)
	await _wait(0.9)
	_check(hud.overlay_kind == "choice", "answering the door opens the choice")
	var focus = hud.get_viewport().gui_get_focus_owner()
	_check(focus is Button, "the choice has a focused button for the gamepad")
	await _shot("34_tide_choice")
	var mats: int = Game.materials
	var let_in: Button = hud.overlay_box.find_child("choice_good", true, false)
	_check(let_in != null, "the choice offers to let him in")
	if let_in:
		let_in.pressed.emit()
	await _wait(1.6)
	_check(Game.flags.get("tanaka") == "in" and Game.materials == mats + Game.scenario.GUEST_GIFT, "Tanaka comes in with his tool bag")
	_check(Meta.knows_clue("tide", "tanaka_story") and Game.has_insight("signal"), "Tanaka's story teaches the rescue signal")
	if hud.overlay_kind == "reading":
		await _shot("35_tide_tanaka_story")
		hud._close()

	# Dawn, day 2: he eats with you; the tap turns brown.
	Game.food = 5
	Game.water = 5
	Game.advance_minutes(Game.NIGHT_END - Game.minutes + 1)
	await _wait(0.3)
	_check(Game.day == 2 and Game.food == 4 and Game.water == 4, "a guest costs food and water each morning")
	_check(Game.water_note != "", "the tap water is contaminated on day 2")
	var tap = apt.nav_region.get_node("tap")
	_check("Boil" in tap.get_prompt(false), "the brown tap water can be boiled on the gas")
	var w0: int = Game.water
	tap.perform(false)
	_check(Game.water == w0 + Game.scenario.BOIL_WATER, "boiling gives clean water")
	tap.perform(true)
	_check(Game.sick_left > 0.0, "drinking it unboiled makes you sick")
	Game.sick_left = 0.0
	_pose(player, Vector3(3.0, 0.0, -1.1), Vector3(3.0, -4.0, -24.0))
	await _wait(0.8)
	await _shot("36_tide_flood")

	# Gamepad: glyphs follow the last device, the right stick looks.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Game.watch_input(pad)
	_check(Game.using_pad and Game.glyph("interact") == "A", "a gamepad press switches key caps to pad glyphs")
	_pose(player, Vector3(4.55, 0.05, 1.2), Vector3(4.55, 1.2, -0.5))
	await _wait(0.3)
	_check(player.focus == apt.barricades["balcony_door"] and hud.prompt_rows[0]["cap"].get_meta("key") == "A", "the use prompt shows A")
	await _shot("37_tide_pad_prompt")
	var yaw: float = player.rotation.y
	Input.action_press("look_right", 1.0)
	await _wait(0.3)
	Input.action_release("look_right")
	_check(player.rotation.y < yaw - 0.1, "the right stick turns the view")
	hud._show_pause()
	await _wait(0.2)
	_check(hud.get_viewport().gui_get_focus_owner() is Button, "the pause menu focuses its first button")
	await _shot("38_pause_pad")
	hud._show_manual()
	await _wait(0.3)
	await _shot("38b_manual_pad")
	hud._close()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Game.watch_input(key)
	_check(not Game.using_pad and Game.glyph("interact") == "E", "a key press switches back to keyboard caps")

	# The gas meter trips; the crank charges the phone.
	Game.scheduled_events.push_front({"at": 0, "type": "gas_cut"})
	await _wait(0.2)
	_check(not Game.gas_valve_open and tap.get_prompt(false) == "", "with the gas gone, there's nothing to boil on")
	Game.phone_battery = 20.0
	Game.crank_phone()
	_check(Game.phone_battery > 20.0, "the crank charger adds battery")

	# Day 3: the wind drops, signal the boats for an early pickup.
	Game.heal(Game.max_health)
	Game.hunger = 100.0
	Game.thirst = 100.0
	Game.day = 3
	Game.minutes = 15 * 60
	Game.advance_minutes(1)
	_check(Game.storm_level < 0.1 and "sheet" in bal.get_prompt(true), "once the wind drops, you can signal from the balcony")
	bal.perform(true)
	_check(Game.flags.has("signal") and Game.nights_goal() == 3, "a white sheet brings the boat a day early")

	# Rescue at dawn on day 4.
	Game.phase = Game.Phase.NIGHT
	Game.minutes = Game.NIGHT_END - 0.5
	await _wait(2.0)
	_check(Game.phase == Game.Phase.WON and hud.overlay_kind == "end", "the SDF boat comes at dawn on day 4")
	_check(Meta.wins_in("tide") == 1 and Game.end_note != "", "the rescue is recorded for Tide, with Tanaka's ending")
	await _shot("39_tide_rescued")
	if _failed:
		print("SMOKE FAILED")
		await _quit(1)
		return
	hud._restart()


func _tide_second_life() -> void:
	print("SMOKE: Tide, second life")
	var hud = main.hud
	var player = main.player
	var apt = main.apartment
	await _wait(0.5)
	_check(Game.scenario.ID == "tide" and hud.overlay_kind == "intro", "the next life stays in Tide")
	hud._start_run()
	await _wait(0.3)
	var tide = main.get_node("TideDirector")
	# Refuse Tanaka this time: his note turns up under the door.
	Game.advance_minutes(Game.NIGHT_START - Game.minutes + 1)
	tide.begin_knock()
	tide.refuse(false)
	_check(Game.flags.get("tanaka") == "refused", "you can keep the door shut")
	player.global_position = Vector3(3.2, 0.05, 5.0)  # in the hall, away from the glass
	for i in 2:  # the night in two halves, patched up in between
		Game.hunger = 100.0
		Game.thirst = 100.0
		Game.heal(Game.max_health)
		Game.advance_minutes(25 * 60 - Game.minutes if i == 0 else Game.NIGHT_END - Game.minutes + 1)
		await _wait(0.2)
	_check(Game.is_alive_phase() and Game.day == 2, "the unprotected night is survivable away from the windows")
	var mail = apt.nav_region.get_node("mail")
	mail.perform(false)  # the building notice first
	hud._close()
	mail.perform(false)
	await _wait(0.2)
	_check(Meta.knows_clue("tide", "tanaka_note"), "refusing him leaves a note under the door")
	await _shot("40_tide_tanaka_note")
	hud._close()
	# Death: asleep by the window when the storm blows it in.
	Game.health = 10.0
	var bed_w = apt.barricades["bedroom_window"]
	_check(bed_w.broken or apt.barricades["balcony_door"].broken or apt.barricades["balcony_door"].hp < apt.barricades["balcony_door"].max_hp,
		"an unprotected night in the storm wrecks the balcony-side glass")
	if bed_w.broken:
		Game.materials += 10
		bed_w.perform(false)  # board it over, then strip it back to bare glass
		tide.guard.levels["bedroom_window"] = 0
		tide.guard.refresh_visual(bed_w)
	Game.health = 10.0
	player.global_position = Vector3(1.2, 0.05, 1.0)
	Game.player_sleeping = true
	tide.guard.hit("bedroom_window", 9999.0)
	_check(Game.phase == Game.Phase.DEAD and "asleep" in Game.death_cause, "a window blowing in can kill you (%s)" % Game.death_cause)
	Game.player_sleeping = false
	await _wait(2.0)
	_check(hud.overlay_kind == "end", "Tide death screen is shown")
	await _shot("41_tide_death")
	_check(bed_w.broken, "the window is blown in")
	print("SMOKE OK" if not _failed else "SMOKE FAILED")
	await _quit(1 if _failed else 0)


## Stop every sound first, or playbacks still mixing at exit show up as leaks.
func _quit(code: int) -> void:
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for p in get_tree().root.find_children("*", kind, true, false):
			p.stop()
			p.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(code)
