extends CharacterBody3D
## The survivor. WASD to move (camera-relative, top-down), Shift to sneak,
## hold E / R to use things, Space / LMB to swing, 1/2/3 to eat/drink/heal.

const Props := preload("res://scripts/world/props.gd")

const SPEED := 3.4
const SNEAK_SPEED := 1.5
const FOCUS_RANGE := 0.85
const SWING_RANGE := 1.55
const SWING_COOLDOWN := 0.6

var focus: Node = null
var hold_progress := 0.0
var hold_alt := false
var hold_lock := false  # must release the key between actions
var swing_cd := 0.0
var step_noise_t := 0.0

var body_pivot: Node3D
var arm: Node3D
var bat: MeshInstance3D
var phone_light: OmniLight3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	add_child(shape)

	body_pivot = Node3D.new()
	add_child(body_pivot)
	if Props.has_model("player"):
		body_pivot.add_child(Props.visual("player", Vector3(0.5, 1.6, 0.3), Color.WHITE))
	else:
		var torso := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.26
		cm.height = 1.5
		torso.mesh = cm
		torso.position.y = 0.75
		torso.material_override = Props.mat(Color(0.2, 0.35, 0.6))
		body_pivot.add_child(torso)
		body_pivot.add_child(Props.box(Vector3(0.28, 0.1, 0.12), Color(0.95, 0.85, 0.7), Vector3(0, 1.35, 0.22)))  # face
	arm = Node3D.new()
	arm.position = Vector3(0.3, 1.0, 0.0)
	body_pivot.add_child(arm)
	arm.add_child(Props.box(Vector3(0.1, 0.1, 0.45), Color(0.2, 0.35, 0.6), Vector3(0, 0, 0.2)))
	bat = Props.box(Vector3(0.06, 0.06, 0.85), Color(0.75, 0.75, 0.8), Vector3(0, 0, 0.75))
	arm.add_child(bat)

	phone_light = OmniLight3D.new()
	phone_light.position = Vector3(0, 1.6, 0.3)
	phone_light.omni_range = 3.5
	phone_light.light_energy = 0.35
	phone_light.light_color = Color(0.85, 0.9, 1.0)
	add_child(phone_light)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	bat.visible = Game.has_weapon
	swing_cd = max(0.0, swing_cd - delta)

	if not Game.is_alive_phase():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0, input.y)
	if Game.player_sleeping and dir.length() > 0.1:
		_wake()

	_update_focus()
	var holding := _process_hold(delta)

	if holding or Game.player_sleeping:
		dir = Vector3.ZERO
	var sneaking := Input.is_action_pressed("sneak")
	var speed := SNEAK_SPEED if sneaking else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dir.length() > 0.1:
		body_pivot.rotation.y = lerp_angle(body_pivot.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
		step_noise_t += delta
		if step_noise_t > 0.5:
			step_noise_t = 0.0
			Game.make_noise(global_position, 0.3 if sneaking else 1.0)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_alive_phase():
		return
	if event.is_action_pressed("attack") and not Game.player_sleeping:
		_swing()
	elif event.is_action_pressed("eat"):
		Game.eat()
	elif event.is_action_pressed("drink"):
		Game.drink()
	elif event.is_action_pressed("medkit"):
		Game.use_medkit()


# --- Interaction ---------------------------------------------------------------

func facing() -> Vector3:
	return Vector3(sin(body_pivot.rotation.y), 0, cos(body_pivot.rotation.y))


func _update_focus() -> void:
	if hold_progress > 0.0 and is_instance_valid(focus):
		return  # don't switch target mid-action
	var best: Node = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var d: float = node.distance_to(global_position)
		if d > FOCUS_RANGE:
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0
		var score := d - 0.25 * facing().dot(to.normalized())
		if score < best_score:
			best_score = score
			best = node
	if best != focus:
		if is_instance_valid(focus):
			focus.set_focused(false)
		focus = best
		if focus:
			focus.set_focused(true)


func _process_hold(delta: float) -> bool:
	var primary := Input.is_action_pressed("interact")
	var alt := Input.is_action_pressed("interact_alt")
	if not primary and not alt:
		hold_lock = false
		hold_progress = 0.0
		return false
	if hold_lock or not is_instance_valid(focus):
		hold_progress = 0.0
		return false
	var want_alt := alt and not primary
	if hold_progress > 0.0 and want_alt != hold_alt:
		hold_progress = 0.0
	hold_alt = want_alt
	if focus.get_prompt(hold_alt) == "":
		hold_progress = 0.0
		return false
	if Game.player_sleeping:
		_wake()
	hold_progress += delta * Game.action_speed()
	Game.make_noise(global_position, focus.get_noise(hold_alt) * delta)
	if hold_progress >= focus.get_duration(hold_alt):
		hold_progress = 0.0
		hold_lock = true
		focus.perform(hold_alt)
		Game.make_noise(global_position, focus.get_noise(hold_alt))
	return true


func hold_fraction() -> float:
	if not is_instance_valid(focus) or hold_progress <= 0.0:
		return 0.0
	return clamp(hold_progress / focus.get_duration(hold_alt), 0.0, 1.0)


# --- Combat ----------------------------------------------------------------------

func _swing() -> void:
	if swing_cd > 0.0:
		return
	swing_cd = SWING_COOLDOWN
	var tween := create_tween()
	arm.rotation.y = 1.1
	tween.tween_property(arm, "rotation:y", -1.0, 0.15)
	tween.tween_property(arm, "rotation:y", 0.0, 0.2)
	Game.make_noise(global_position, 2.5)
	var hit := false
	for z in get_tree().get_nodes_in_group("zombie"):
		if not z.is_alive():
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		if to.length() > SWING_RANGE:
			continue
		if facing().dot(to.normalized()) < 0.35:
			continue
		z.take_hit(Game.weapon_damage(), to.normalized())
		hit = true
	if hit:
		Game.shake.emit(0.12, 0.1)


# --- Sleep ---------------------------------------------------------------------------

func sleep_on(bed: Node3D) -> void:
	global_position = bed.global_position + Vector3(0, 0.45, 0)
	body_pivot.rotation = Vector3(-PI * 0.5, 0, 0)
	Game.player_sleeping = true
	var before := Game.health
	Game.skip_to(Game.REST_UNTIL)
	if Game.is_alive_phase():
		if Meta.has_perk("light_sleeper"):
			Game.heal(Game.max_health)
		else:
			Game.heal(15.0)
		Game.say("You sleep fitfully until evening. (+%d health)" % int(Game.health - before), "info")


func _wake() -> void:
	Game.player_sleeping = false
	body_pivot.rotation = Vector3(0, body_pivot.rotation.y, 0)
	global_position.y = max(global_position.y, 0.05)
	global_position += Vector3(-1.0, 0, 0)  # roll off the bed, away from the wardrobe
