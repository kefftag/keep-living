extends Node
## Scripted playthrough used for automated checks:
##   godot --headless -- --smoke-test
## Optionally saves screenshots when a renderer is available:
##   godot -- --smoke-test --shots=/some/dir
## Prints "SMOKE OK" and exits 0 on success, exits 1 on the first failure.

var main: Node
var _shots_dir := ""
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.substr(8)
	_run()


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


func _run() -> void:
	if Meta.deaths > 0:
		_second_life()
		return
	print("SMOKE: start (runs so far: %d)" % Meta.runs)
	var hud = main.hud
	var player = main.player
	var apt = main.apartment
	await _wait(0.5)
	await _shot("01_intro")
	_check(hud.overlay_kind == "intro", "intro card is shown")
	hud._start_run()
	await _wait(0.6)
	_check(Game.phase == Game.Phase.DAY, "run begins in the day phase")
	await _shot("02_day")

	# Navigation: there must be a path from the stairwell to the bedroom.
	var map: RID = player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(11.5, 0, 8.25), Vector3(2.0, 0, 1.5), true)
	_check(path.size() > 1, "navmesh connects stairwell to bedroom (%d points)" % path.size())
	if path.size() > 1:
		_check(path[path.size() - 1].distance_to(Vector3(2.0, 0, 1.5)) < 0.6, "path actually reaches the bedroom")

	# Clue: the phone.
	var phone = apt.nav_region.get_node("phone")
	player.global_position = phone.global_position + Vector3(0.6, 0.1, 0)
	await _wait(0.3)
	phone.perform(false)
	await _wait(0.2)
	_check(Meta.knows_clue("zombie", "jalert"), "phone gives the J-ALERT clue")
	_check(hud.overlay_kind == "reading" and get_tree().paused, "clue popup pauses the game")
	await _shot("03_clue")
	hud._close()

	# Looting and barricading.
	var mats_before: int = Game.materials
	apt.nav_region.get_node("storage_closet").perform(false)
	_check(Game.materials == mats_before + 4, "storage closet gives 4 materials")
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

	# Earthquake: the unsecured wardrobe should topple, the gas should leak.
	player.global_position = Vector3(6.5, 0.1, 5.0)
	Game.scheduled_events.push_front({"at": 0, "type": "quake", "strength": 1.0})
	await _wait(2.2)
	var wardrobe = apt.nav_region.get_node("wardrobe")
	_check(wardrobe.fallen, "unsecured wardrobe falls in the quake")
	_check(not shelf.fallen, "secured bookshelf stays up")
	_check(Game.gas_leaking, "open gas main leaks after the quake")
	await _shot("04_quake")
	apt.nav_region.get_node("stove").perform(false)
	_check(not Game.gas_leaking and not Game.gas_valve_open, "closing the gas main stops the leak")

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
	await _shot("05_night")

	# Breach: zombies get in and hurt the player.
	var front = apt.barricades["front_door"]
	front.take_damage(99999.0)
	_check(front.broken, "front door can be breached")
	var hp_start: float = Game.health
	var z_new = main.get_node("NightDirector").spawn_at("front_door")
	player.global_position = Vector3(7.5, 0.1, 6.0)
	Engine.time_scale = 3.0
	for i in 60:
		await _wait(0.5)
		if Game.health < hp_start:
			break
	Engine.time_scale = 1.0
	_check(Game.health < hp_start, "an inside zombie hunts down and bites the player")
	_check(Game.is_alive_phase(), "one bite isn't fatal")
	await _shot("06_breach")

	# Combat: swinging the bat kills the zombie in front of the player.
	Game.heal(Game.max_health)
	Game.has_weapon = true
	var kills_before: int = Game.zombies_killed
	for i in 8:
		if not is_instance_valid(z_new) or not z_new.is_alive():
			break
		var to: Vector3 = z_new.global_position - player.global_position
		player.body_pivot.rotation.y = atan2(to.x, to.z)
		player.swing_cd = 0.0
		player._swing()
		await _wait(0.1)
	_check(Game.zombies_killed > kills_before, "the bat kills a zombie")

	# Death -> Echo choice -> restart.
	if Game.is_alive_phase():
		Game.damage(9999.0, "Smoke test.")
	await _wait(2.0)
	_check(hud.overlay_kind == "end", "death screen is shown")
	_check(Meta.deaths >= 1, "death is recorded in meta progress")
	await _shot("07_death")
	var perks_before := Meta.perks.size()
	var choices := Game.roll_perk_choices()
	if choices.size() > 0:
		Meta.add_perk(choices[0])
		_check(Meta.perks.size() == perks_before + 1, "an Echo can be chosen")

	if _failed:
		print("SMOKE FAILED")
		get_tree().quit(1)
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
	Game.clue_found.connect(func(id, is_new): seen.append(is_new))
	main.apartment.nav_region.get_node("phone").perform(false)
	_check(seen == [false], "re-reading a known clue isn't treated as new")
	print("SMOKE OK" if not _failed else "SMOKE FAILED")
	get_tree().quit(1 if _failed else 0)
