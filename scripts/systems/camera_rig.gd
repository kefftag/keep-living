extends Camera3D
## High-angle follow camera over the cut-away apartment, with screen shake.

const OFFSET := Vector3(0, 10.5, 6.2)

var target: Node3D
var _shake_amount := 0.0
var _shake_left := 0.0
var _focus := Vector3.ZERO


func _ready() -> void:
	fov = 46.0
	current = true
	Game.shake.connect(_on_shake)
	if target:
		_focus = target.global_position
		global_position = _focus + OFFSET
		look_at(_focus, Vector3.UP)


func _on_shake(amount: float, duration: float) -> void:
	_shake_amount = max(_shake_amount, amount)
	_shake_left = max(_shake_left, duration)


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	# Keep the apartment mostly framed: follow the player, but clamp the focus.
	var want := target.global_position
	want.x = clamp(want.x, 2.5, 7.5)
	want.z = clamp(want.z, 1.0, 6.5)
	_focus = _focus.lerp(want, 1.0 - exp(-4.0 * delta))
	var pos := _focus + OFFSET
	if _shake_left > 0.0:
		_shake_left -= delta
		var a: float = _shake_amount * clamp(_shake_left, 0.0, 1.0)
		pos += Vector3(randf_range(-a, a), randf_range(-a, a) * 0.5, randf_range(-a, a))
	else:
		_shake_amount = 0.0
	global_position = pos
	look_at(_focus, Vector3.UP)
