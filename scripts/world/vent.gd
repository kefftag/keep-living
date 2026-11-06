extends "res://scripts/world/interactable.gd"
## A gap that isn't an entrance: a 24-hour ventilation inlet (24時間換気の
## 給気口) or the range hood duct. Only Ash places these (scenario_world.gd);
## all behaviour comes from its `mode_handler` (scripts/systems/seal.gd).
## Local +Z faces into the room.

var point_id := ""
var hidden := false   # no visual of its own (the range hood is already there)
var mode_handler: Object = null


func _ready() -> void:
	super._ready()
	flag_label.position = Vector3(0, -0.25, 0.15)  # under it: vents sit near the ceiling


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	if not hidden:
		# Round-cornered white plastic cover with louvres, like a Japanese 給気口.
		visual.add_child(Props.fbox(Vector3(size.x, size.y, 0.02), "plastic_white", Vector3(0, size.y * 0.5, size.z * 0.5 - 0.01)))
		for i in 4:
			var y := size.y * (0.25 + 0.17 * i)
			visual.add_child(Props.fbox(Vector3(size.x * 0.75, 0.012, 0.012), "plastic_grey", Vector3(0, y, size.z * 0.5 + 0.004)))
	add_child(Props.box_shape(size, Vector3(0, size.y * 0.5, 0)))


func get_prompt(alt: bool) -> String:
	return mode_handler.get_prompt(self, alt) if mode_handler else ""


func get_status() -> String:
	return mode_handler.get_status(self) if mode_handler else ""


func get_flag() -> String:
	return mode_handler.get_flag(self) if mode_handler else ""


func get_duration(alt: bool) -> float:
	return mode_handler.get_duration(self, alt) if mode_handler else 1.0


func get_noise(alt: bool) -> float:
	return mode_handler.get_noise(self, alt) if mode_handler else 0.0


func get_hold_sound(alt: bool) -> String:
	return mode_handler.get_hold_sound(self, alt) if mode_handler else ""


func perform(alt: bool) -> void:
	if mode_handler:
		mode_handler.perform(self, alt)
