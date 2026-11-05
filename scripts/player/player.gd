extends CharacterBody3D
## The survivor, in first person. Mouse to look, WASD to move, Shift to walk
## quietly, hold E / R on what you're looking at, LMB / Space to swing,
## F for the phone light, 1/2/3 to eat/drink/heal.

const Props := preload("res://scripts/world/props.gd")

const SPEED := 2.4          # brisk indoor walk
const SNEAK_SPEED := 1.1
const EYE_HEIGHT := 1.55
const REACH := 1.9
const SWING_RANGE := 1.6
const SWING_COOLDOWN := 0.6
const MOUSE_SENS := 0.0022
const LOOK_MASK := 1 | 2 | 16 | 32  # world, entrances, doors, breached entrances
const VIEWMODEL_POS := Vector3(0.26, -0.3, -0.42)  # swing pivot, relative to the camera

var focus: Node = null
var hold_progress := 0.0
var hold_alt := false
var hold_lock := false  # must release the key between actions
var swing_cd := 0.0
var step_noise_t := 0.0
var bob_t := 0.0

var head: Node3D
var camera: Camera3D
var viewmodel: Node3D
var bat: Node3D
var fist: Node3D
var flashlight: SpotLight3D

var hold_sound_t := 0.0
const HOLD_SOUND_EVERY := {"hammer": 0.45, "rummage": 0.6, "water_pour": 2.3}

var _shake_amount := 0.0
var _shake_left := 0.0
var _bed: Node3D = null


func _ready() -> void:
	add_to_group("player")
	collision_layer = 8
	collision_mask = 1 | 2 | 16
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.03
	camera.current = true
	head.add_child(camera)

	# Viewmodel: his own forearm and fist, or both hands on the metal bat once
	# found. fp_fist / fp_bat are posed in Blender from the protagonist model
	# with the eye at their origin, so they sit at -VIEWMODEL_POS under the pivot.
	viewmodel = Node3D.new()
	viewmodel.position = VIEWMODEL_POS
	camera.add_child(viewmodel)
	fist = Node3D.new()
	viewmodel.add_child(fist)
	bat = Node3D.new()
	viewmodel.add_child(bat)
	if Props.has_model("fp_fist"):
		var arm := Props.visual("fp_fist", Vector3.ONE, Color.WHITE)
		arm.position = -VIEWMODEL_POS
		fist.add_child(arm)
	else:
		fist.add_child(Props.box(Vector3(0.055, 0.055, 0.22), Color(0.16, 0.28, 0.5), Vector3(0, -0.02, 0.12)))  # sleeve
		fist.add_child(Props.box(Vector3(0.06, 0.05, 0.08), Color(0.85, 0.66, 0.52), Vector3(0, -0.01, -0.02)))   # hand
	if Props.has_model("fp_bat"):
		var grip := Props.visual("fp_bat", Vector3.ONE, Color.WHITE)
		grip.position = -VIEWMODEL_POS
		bat.add_child(grip)
	else:  # no hands: just the bat, tipped over the shoulder
		bat.rotation = Vector3(deg_to_rad(55), deg_to_rad(-10), 0)
		bat.position = Vector3(0, 0, -0.08)
		if Props.has_model("bat"):
			var real_bat := Props.visual("bat", Vector3(0.08, 0.84, 0.08), Color.WHITE, true)
			real_bat.position.y = -0.1
			bat.add_child(real_bat)
		else:
			var shaft := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.032
			cyl.bottom_radius = 0.018
			cyl.height = 0.8
			shaft.mesh = cyl
			shaft.material_override = Props.mat(Color(0.72, 0.73, 0.76))
			shaft.position.y = 0.32
			bat.add_child(shaft)

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 14.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 2.2
	flashlight.light_color = Color(0.92, 0.95, 1.0)
	flashlight.shadow_enabled = true
	flashlight.visible = false
	camera.add_child(flashlight)

	_no_shadows(viewmodel)
	Game.shake.connect(_on_shake)


# --- Look & move -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		head.rotation.x = clamp(head.rotation.x - event.relative.y * MOUSE_SENS, deg_to_rad(-85), deg_to_rad(85))
		return
	if not Game.is_alive_phase():
		return
	if event.is_action_pressed("attack") and not Game.player_sleeping:
		_swing()
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("eat"):
		Game.eat()
	elif event.is_action_pressed("drink"):
		Game.drink()
	elif event.is_action_pressed("medkit"):
		Game.use_medkit()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	bat.visible = Game.has_weapon
	fist.visible = not Game.has_weapon
	swing_cd = max(0.0, swing_cd - delta)
	_update_shake(delta)

	if not Game.is_alive_phase():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Game.player_sleeping:
		if input.length() > 0.1:
			_wake()
		else:
			return

	_update_focus()
	var holding := _process_hold(delta)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	if holding:
		dir = Vector3.ZERO
	var sneaking := Input.is_action_pressed("sneak")
	var speed := SNEAK_SPEED if sneaking else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	var moving := dir.length() > 0.1 and is_on_floor()
	if moving:
		bob_t += delta * (6.0 if sneaking else 9.0)
		step_noise_t += delta
		if step_noise_t > (0.62 if sneaking else 0.45):
			step_noise_t = 0.0
			Game.make_noise(global_position, 0.3 if sneaking else 1.0)
			Sfx.play(_floor_sound(), global_position, -16.0 if sneaking else -7.0, 0.1)
	else:
		bob_t = lerp(bob_t, round(bob_t / PI) * PI, 10.0 * delta)
	head.position.y = EYE_HEIGHT + sin(bob_t) * 0.025
	viewmodel.position.x = VIEWMODEL_POS.x + cos(bob_t * 0.5) * 0.008
	move_and_slide()


func _on_shake(amount: float, duration: float) -> void:
	_shake_amount = max(_shake_amount, amount)
	_shake_left = max(_shake_left, duration)


func _update_shake(delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left -= delta
		var a: float = _shake_amount * 0.12 * clamp(_shake_left, 0.0, 1.0)
		camera.h_offset = randf_range(-a, a)
		camera.v_offset = randf_range(-a, a)
	else:
		_shake_amount = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0


# --- Interaction ---------------------------------------------------------------

func look_dir() -> Vector3:
	return -camera.global_transform.basis.z


func _update_focus() -> void:
	if hold_progress > 0.0 and is_instance_valid(focus):
		return  # don't switch target mid-action
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + look_dir() * REACH, LOOK_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var best: Node = null
	if hit:
		var n: Node = hit["collider"]
		while n and not n.is_in_group("interactable"):
			n = n.get_parent()
			if n == null or n is Window:
				n = null
				break
		best = n
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
		hold_sound_t = 0.0
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
	hold_progress += delta * Game.action_speed()
	var hs: String = focus.get_hold_sound(hold_alt)
	if hs != "":
		hold_sound_t -= delta
		if hold_sound_t <= 0.0:
			hold_sound_t = HOLD_SOUND_EVERY.get(hs, 0.5)
			Sfx.play(hs, focus.global_position + Vector3(0, 0.8, 0), -4.0)
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
	viewmodel.rotation = Vector3(0.3, 0.9, 0)
	tween.tween_property(viewmodel, "rotation", Vector3(-0.4, -0.7, -0.3), 0.14)
	tween.tween_property(viewmodel, "rotation", Vector3.ZERO, 0.22)
	Game.make_noise(global_position, 2.5)
	Sfx.play("swing", null, -8.0)
	var hit := false
	var fwd := look_dir()
	fwd.y = 0
	fwd = fwd.normalized()
	for z in get_tree().get_nodes_in_group("zombie"):
		if not z.is_alive():
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		if to.length() > SWING_RANGE or fwd.dot(to.normalized()) < 0.5:
			continue
		z.take_hit(Game.weapon_damage(), to.normalized())
		Sfx.play("hit_flesh", z.global_position + Vector3(0, 1.2, 0), -2.0)
		hit = true
	if hit:
		_on_shake(0.4, 0.12)


func _floor_sound() -> String:
	var p := global_position
	if p.y < -0.07:
		return "step_tile"  # genkan / corridor
	if p.x < 2.73 and p.z > 3.64:
		return "step_tile"  # washroom, bath, toilet
	return "step_wood"


# --- Sleep ---------------------------------------------------------------------------

func sleep_on(bed: Node3D) -> void:
	_bed = bed
	velocity = Vector3.ZERO
	# Lie down with your head on the pillow (bed head is the bed's local -Z).
	global_position = bed.to_global(Vector3(0, 0.46, -0.55))
	head.position.y = 0.25
	head.rotation.x = deg_to_rad(80)  # staring at the ceiling
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
	head.rotation.x = 0.0
	head.position.y = EYE_HEIGHT
	if is_instance_valid(_bed):
		# Swing your legs out on the room side of the bed.
		global_position = _bed.to_global(Vector3(_bed.size.x * 0.5 + 0.4, 0.05, 0.5))


## Viewmodel meshes are drawn at arm's length from the camera; their shadows
## would land on the walls in odd places.
func _no_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_no_shadows(c)
