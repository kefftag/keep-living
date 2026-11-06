extends CharacterBody3D
## One of the infected. Walks from a spawn origin (stairwell / neighbour's
## balcony) to an entrance, beats on it until it breaks, then hunts the player.

const Props := preload("res://scripts/world/props.gd")
## assets/models/<name>.glb, one picked per zombie. Rigged ones carry walk / idle / attack clips.
const MODEL_VARIANTS := ["zombie", "zombie_02", "zombie_03"]

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
var body: Node3D           # the visible body, under pivot, for twitches
var groan_t := 0.0
var lunge_t := 0.0
var lunge_cd := 0.0
var twitch_t := 0.0
var twitch := Vector3.ZERO
var shrieked := false
var anim: AnimationPlayer       # set when the model is rigged (walk / idle / attack clips)
var head_from_body := Transform3D()  # body space -> head bone space, for the eyes
var biting := false
const WALK_CLIP_SPEED := 0.6  # m/s the walk clip plays naturally at (a bit above its ~0.4 to limit scrambling)


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
	cap.radius = 0.2  # must match the navmesh agent radius or they snag on door frames
	cap.height = 1.65
	shape.shape = cap
	shape.position.y = 0.82
	add_child(shape)

	pivot = Node3D.new()
	add_child(pivot)
	var variants: Array = MODEL_VARIANTS.filter(func(n): return Props.has_model(n))
	if not variants.is_empty():
		body = Props.visual(variants.pick_random(), Vector3(0.5, 1.7, 0.3), Color.WHITE)
		pivot.add_child(body)
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

	anim = _find_anim_player(body) if body != null else null
	if anim:
		for clip in ["walk", "idle", "attack"]:
			if anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play("idle", 1.0)
		anim.seek(randf_range(0.0, 3.0), true)  # don't move in lockstep

	# Eyes: pale, faintly glowing, so they catch your phone light in the dark.
	var head := _head_attachment(body) if anim else null
	for side in [-1, 1]:
		if head:
			var eye := Props.box(Vector3(0.018, 0.008, 0.008), Color(0.95, 0.92, 0.75), Vector3.ZERO, 1.6)
			# Eyes sit ~7 cm above the head bone's base and ~9.5 cm forward,
			# so they follow models of any height.
			var head_base: Vector3 = head_from_body.affine_inverse().origin
			eye.transform = head_from_body * Transform3D(Basis(), Vector3(0.032 * side, head_base.y + 0.07, head_base.z + 0.095))
			head.add_child(eye)
		else:
			var eye := Props.box(Vector3(0.035, 0.02, 0.02), Color(0.95, 0.92, 0.75), Vector3(0.045 * side, 1.47, 0.16), 2.5)
			(body if body != null else pivot).add_child(eye)
	pivot.rotation.x = 0.0
	if body == null:
		body = pivot
	groan_t = randf_range(1.0, 6.0)
	lunge_cd = randf_range(1.5, 4.0)

	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.35
	nav.target_desired_distance = 0.3
	nav.radius = 0.2
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
	_animate(delta)
	if flash_t > 0.0:
		flash_t -= delta
		if body_mat:
			body_mat.emission_enabled = flash_t > 0.0
	if not Game.is_alive_phase():
		biting = false
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
			biting = to.length() < 1.05
			if biting:
				velocity.x = 0
				velocity.z = 0
				_face(player.global_position, delta)
				if attack_cd <= 0.0:
					attack_cd = 1.1
					Game.damage(bite, "Torn apart by the infected on night %d." % Game.day if Game.phase == Game.Phase.NIGHT else "Bitten by one of the infected that got inside.")
			else:
				if not shrieked:
					shrieked = true
					Sfx.play("shriek", global_position + Vector3(0, 1.5, 0), 0.0, 0.15)
				# Close in, then lunge: a sudden burst of speed with a shriek.
				lunge_cd -= delta
				if lunge_t <= 0.0 and lunge_cd <= 0.0 and to.length() < 4.0:
					lunge_t = 0.7
					lunge_cd = randf_range(3.5, 7.0)
					Sfx.play("shriek", global_position + Vector3(0, 1.5, 0), 3.0, 0.2)
				var burst := 2.3 if lunge_t > 0.0 else 1.15
				lunge_t -= delta
				_move_towards(player.global_position, speed * burst * day_slow, delta)
	move_and_slide()


## Hunched, twitchy body language and the occasional groan.
func _animate(delta: float) -> void:
	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(3.0, 8.0) if state != State.HUNT else randf_range(1.5, 4.0)
		Sfx.play("groan", global_position + Vector3(0, 1.5, 0), -1.0, 0.15, 22.0)
	twitch_t -= delta
	if twitch_t <= 0.0:
		twitch_t = randf_range(0.4, 2.2)
		twitch = Vector3(randf_range(-0.35, 0.25), randf_range(-0.5, 0.5), randf_range(-0.3, 0.3))
	twitch = twitch.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * delta))
	var lean := 0.32 if lunge_t > 0.0 else 0.18  # hunched forward, more when lunging
	if anim:
		lean -= 0.14  # the clips are already hunched
	if body != pivot and is_instance_valid(body):
		body.rotation = Vector3(lean + twitch.x + sin(anim_t * 2.1) * 0.04, twitch.y, twitch.z + sin(anim_t * 1.3) * 0.06)
	if anim:
		var hspeed := Vector2(velocity.x, velocity.z).length()
		if state == State.BASH or biting:
			_play("attack", 1.0 + (0.4 if biting else 0.0))
		elif hspeed > 0.15:
			# The clip covers ~0.4 m/s; past ~2.5x it reads as a frantic scramble, so let feet slide.
			_play("walk", clamp(hspeed / WALK_CLIP_SPEED, 0.8, 2.5))
		else:
			_play("idle", 1.0)


func _play(clip: String, rate: float) -> void:
	if anim.current_animation != clip and anim.has_animation(clip):
		anim.play(clip, 0.25)
	anim.speed_scale = rate


static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found:
			return found
	return null


## A BoneAttachment3D on the head bone; sets head_from_body so things placed in
## body space (metres, +Z front) land on the face at the rest pose.
func _head_attachment(root: Node3D) -> BoneAttachment3D:
	var skel := _find_skeleton(root)
	if skel == null:
		return null
	var idx := -1
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn.ends_with("Head") and not bn.contains("Top"):
			idx = i
			break
	if idx < 0:
		return null
	var skel_xf := Transform3D()  # skeleton -> body
	var n: Node = skel
	while n != root and n is Node3D:
		skel_xf = (n as Node3D).transform * skel_xf
		n = n.get_parent()
	head_from_body = (skel_xf * skel.get_bone_global_rest(idx)).affine_inverse()
	var att := BoneAttachment3D.new()
	att.bone_idx = idx
	skel.add_child(att)
	return att


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
	if anim:
		anim.pause()
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
