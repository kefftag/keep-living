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
	Game.clue_found.connect(func(id, is_new): seen.append(is_new))
	main.apartment.nav_region.get_node("phone").perform(false)
	_check(seen == [false], "re-reading a known clue isn't treated as new")
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
