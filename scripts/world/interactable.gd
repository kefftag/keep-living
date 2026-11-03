extends StaticBody3D
## Base class for anything the player can use. The player looks at it
## (camera raycast) and holds [E] (primary) or [R] (alternate).
##
## Subclasses override get_prompt / get_duration / get_noise / perform and
## optionally get_status and get_flag.

const Props := preload("res://scripts/world/props.gd")

var display_name := "Thing"
var model_name := ""
var size := Vector3(0.6, 0.8, 0.6)
var color := Color(0.6, 0.6, 0.6)

var visual: Node3D
var flag_label: Label3D
var focused := false


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 1
	collision_mask = 0
	_build()
	flag_label = Props.label("", size.y + 0.25, Color(1.0, 0.55, 0.3))
	flag_label.no_depth_test = false  # first person: no warnings through walls
	flag_label.visible = false
	add_child(flag_label)
	Game.stats_changed.connect(refresh_flag)
	refresh_flag()


## Default construction: one visual + one box collider.
func _build() -> void:
	visual = Props.visual(model_name, size, color)
	add_child(visual)
	add_child(Props.box_shape(size, Vector3(0, size.y * 0.5, 0)))


func set_focused(value: bool) -> void:
	focused = value
	refresh_flag()


func refresh_flag() -> void:
	if not is_inside_tree():
		return
	var text := get_flag()
	flag_label.text = text
	flag_label.visible = text != ""


# --- Overridables ------------------------------------------------------------

## Text for the action, or "" if the action isn't available right now.
func get_prompt(_alt: bool) -> String:
	return ""


## Short state shown next to the name, e.g. "(searched)".
func get_status() -> String:
	return ""


## Warning text floating over the object (used by the "Prepared" insight).
func get_flag() -> String:
	return ""


func get_duration(_alt: bool) -> float:
	return 1.0


## Noise per second while the action is held.
func get_noise(_alt: bool) -> float:
	return 0.0


func perform(_alt: bool) -> void:
	pass
