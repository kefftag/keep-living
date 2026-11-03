extends CharacterBody3D
## One of the infected. Walks from a spawn origin (stairwell / neighbour's
## balcony) to an entrance, beats on it until it breaks, then hunts the player.

const Props := preload("res://scripts/world/props.gd")

enum State { APPROACH, BASH, HUNT, DEAD }

var state := State.APPROACH
var target = null  # barricade node
var slot := 0
var night := 1
var hp := 100.0
var speed := 1.3
var bash_dps := 7.0
var bite := 12.0
var attack_cd := 0.0
var player: Node3D
var nav: NavigationAgent3D
var pivot: Node3D
var flash_t := 0.0
var body_mat: StandardMaterial3D
var anim_t := 0.0


func setup(target_point, player_ref: Node3D, night_number: int, slot_index: int) -> void:
	target = target_point
	player = player_ref
	night = night_number
	slot = slot_index
	hp = 90.0 + 10.0 * night
	bash_dps = 2.5 + 0.6 * night
	speed = randf_range(1.1, 1.5) + 0.05 * night


func _ready() -> void:
	add_to_group("zombie")
	collision_layer = 4
	collision_mask = 1 | 2 | 8  # not each other: the balcony is too narrow to pass
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.65
	shape.shape = cap
	shape.position.y = 0.82
	add_child(shape)

	pivot = Node3D.new()
	add_child(pivot)
	if Props.has_model("zombie"):
		pivot.add_child(Props.visual("zombie", Vector3(0.5, 1.7, 0.3), Color.WHITE))
	else:
		body_mat = StandardMaterial3D.new()
		body_mat.albedo_color = Color(0.42, 0.5, 0.4).lerp(Color(0.5, 0.4, 0.4), randf())
		var torso := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.55
		torso.mesh = cm
		torso.material_override = body_mat
		torso.position.y = 0.78
		pivot.add_child(torso)
		for side in [-1, 1]:
			var arm_mesh := Props.box(Vector3(0.09, 0.09, 0.55), Color(0.55, 0.6, 0.5), Vector3(0.2 * side, 1.15, 0.3))
			pivot.add_child(arm_mesh)
		pivot.add_child(Props.box(Vector3(0.3, 0.08, 0.1), Color(0.6, 0.1, 0.1), Vector3(0, 1.32, 0.22)))  # eyes

	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.35
	nav.target_desired_distance = 0.3
	nav.radius = 0.27
	nav.height = 1.65
	add_child(nav)


func is_alive() -> bool:
	return state != State.DEAD


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	attack_cd = max(0.0, attack_cd - delta)
	anim_t += delta
	if flash_t > 0.0:
		flash_t -= delta
		if body_mat:
			body_mat.emission_enabled = flash_t > 0.0
	if not Game.is_alive_phase():
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	match state:
		State.APPROACH:
			if target == null or target.broken:
				state = State.HUNT
			else:
				var goal: Vector3 = target.attack_position(slot)
				if _flat(goal - global_position).length() < 0.35:
					state = State.BASH
				else:
					_move_towards(goal, speed, delta)
		State.BASH:
			if target.broken:
				state = State.HUNT
			else:
				velocity.x = 0
				velocity.z = 0
				_face(target.global_position, delta)
				var mult: float = 1.0 + min(Game.noise_near(target.global_position), 10.0) * 0.08
				target.take_damage(bash_dps * mult * delta)
				pivot.position.z = sin(anim_t * 9.0) * 0.06  # pounding
		State.HUNT:
			if not is_instance_valid(player):
				return
			var day_slow := 0.6 if Game.phase == Game.Phase.DAY else 1.0
			var to := _flat(player.global_position - global_position)
			if to.length() < 1.05:
				velocity.x = 0
				velocity.z = 0
				_face(player.global_position, delta)
				if attack_cd <= 0.0:
					attack_cd = 1.1
					Game.damage(bite, "Torn apart by the infected on night %d." % Game.day if Game.phase == Game.Phase.NIGHT else "Bitten by one of the infected that got inside.")
			else:
				_move_towards(player.global_position, speed * 1.15 * day_slow, delta)
	move_and_slide()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _move_towards(goal: Vector3, spd: float, delta: float) -> void:
	nav.target_position = goal
	var next := goal
	var map := nav.get_navigation_map()
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 and not nav.is_navigation_finished():
		next = nav.get_next_path_position()
	var dir := _flat(next - global_position)
	if dir.length() < 0.05:
		dir = _flat(goal - global_position)
	dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	_face(global_position + dir, delta)
	pivot.rotation.z = sin(anim_t * 4.0) * 0.08  # shamble


func _face(point: Vector3, delta: float) -> void:
	var d := _flat(point - global_position)
	if d.length() > 0.01:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(d.x, d.z), 8.0 * delta)


func take_hit(amount: float, from_dir: Vector3) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	flash_t = 0.12
	if body_mat:
		body_mat.emission = Color(0.8, 0.2, 0.2)
	global_position += from_dir * 0.25
	if hp <= 0.0:
		die()


func die() -> void:
	state = State.DEAD
	Game.zombies_killed += 1
	remove_from_group("zombie")
	collision_layer = 0
	collision_mask = 1
	var tween := create_tween()
	tween.tween_property(pivot, "rotation:x", -PI * 0.5, 0.4)
	tween.tween_interval(2.0)
	tween.tween_property(pivot, "position:y", -0.6, 1.5)
	tween.tween_callback(queue_free)


## Dawn: the ones still outside drift away.
func retreat() -> void:
	if state == State.APPROACH or state == State.BASH:
		state = State.DEAD
		remove_from_group("zombie")
		collision_layer = 0
		var tween := create_tween()
		tween.tween_property(pivot, "scale", Vector3(0.01, 0.01, 0.01), 1.5)
		tween.tween_callback(queue_free)
