extends Node
## Runs the nightly siege: spawns zombies for each entrance in tonight's plan,
## and punishes noise with extra visitors.

const Zombie := preload("res://scripts/enemies/zombie.gd")

const SPAWN_WINDOW := 0.7   # fraction of the night during which the plan spawns
const NOISE_THRESHOLD := 14.0
const MAX_EXTRA := 3

var barricades := {}
var player: Node3D
var zombie_parent: Node3D

var _schedule: Array = []  # [{t, point}]
var _night_t := 0.0
var _extra_spawned := 0
var _noise_check := 0.0
var _slot_counter := {}


func _ready() -> void:
	Game.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: int) -> void:
	if phase == Game.Phase.NIGHT:
		_start_night()
	elif phase == Game.Phase.DAY:
		for z in get_tree().get_nodes_in_group("zombie"):
			z.retreat()


func _start_night() -> void:
	_night_t = 0.0
	_extra_spawned = 0
	_slot_counter = {}
	_schedule = []
	var night_len := (Game.NIGHT_END - Game.NIGHT_START) / Game.NIGHT_MIN_PER_SEC
	var n := Game.tonight_plan.size()
	for i in n:
		var t := night_len * SPAWN_WINDOW * (float(i) + randf_range(0.0, 0.8)) / float(max(n, 1))
		_schedule.append({"t": t + 3.0, "point": Game.tonight_plan[i]})


func _process(delta: float) -> void:
	if Game.phase != Game.Phase.NIGHT:
		return
	_night_t += delta
	while _schedule.size() > 0 and _schedule[0]["t"] <= _night_t:
		var entry: Dictionary = _schedule.pop_front()
		spawn_at(entry["point"])
	_noise_check -= delta
	if _noise_check <= 0.0:
		_noise_check = 1.0
		_check_noise()


func _check_noise() -> void:
	if _extra_spawned >= MAX_EXTRA:
		return
	var loudest := ""
	var loudest_n := NOISE_THRESHOLD
	for id in barricades:
		var n := Game.noise_near(barricades[id].global_position, 5.0)
		if n > loudest_n:
			loudest_n = n
			loudest = id
	if loudest != "":
		_extra_spawned += 1
		Game.say("Something out there heard you.", "warn")
		spawn_at(loudest)


func spawn_at(point_id: String) -> Node3D:
	var point = barricades.get(point_id)
	if point == null:
		return null
	var z = Zombie.new()
	var slot: int = _slot_counter.get(point_id, 0)
	_slot_counter[point_id] = slot + 1
	z.setup(point, player, Game.day, slot)
	var origins: Array = point.spawn_origins
	var origin: Vector3 = origins[randi() % origins.size()]
	zombie_parent.add_child(z)
	z.global_position = origin + Vector3(randf_range(-0.2, 0.2), 0.05, randf_range(-0.2, 0.2))
	return z
