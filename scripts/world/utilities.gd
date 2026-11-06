extends "res://scripts/world/interactable.gd"
## Small fixed fixtures: the gas stove + its gas valve (ガス栓), the kitchen tap,
## the bathtub and the bed. One script, switched on `kind`, because each is
## only a few lines.

var kind := ""  # stove | tap | bathtub | bed
var water_plane: MeshInstance3D
var _hiss: AudioStreamPlayer3D
## A scenario can take a fixture over while handles(self, alt) is true (Tide:
## boiling the brown tap water). Gets the interactable calls with this node first.
var mode_handler: Object = null


func _mode(alt: bool) -> bool:
	return mode_handler != null and mode_handler.handles(self, alt)


func _process(_delta: float) -> void:
	if kind != "stove":
		return
	if Game.gas_leaking and not is_instance_valid(_hiss):
		_hiss = Sfx.loop_on("gas_hiss", self, -8.0, Vector3(0, 0.95, 0))
	elif not Game.gas_leaking and is_instance_valid(_hiss):
		_hiss.queue_free()


func get_hold_sound(_alt: bool) -> String:
	if _mode(_alt):
		return mode_handler.get_hold_sound(self, _alt)
	if kind == "tap" or (kind == "bathtub" and Game.bathtub_water <= 0):
		return "water_pour"
	return ""


func _build() -> void:
	super._build()
	if kind == "bathtub":
		water_plane = Props.box(Vector3(size.x * 0.8, 0.02, size.z * 0.85), Color(0.35, 0.6, 0.85, 0.75),
			Vector3(0, size.y * 0.85, 0))
		water_plane.visible = false
		add_child(water_plane)


func get_prompt(alt: bool) -> String:
	if _mode(alt):
		return mode_handler.get_prompt(self, alt)
	match kind:
		"stove":
			if alt:
				if Game.gas_valve_open and not Game.gas_leaking and Game.food > 0:
					return "Cook a hot meal (1 food)"
				return ""
			return "Close the gas valve" if Game.gas_valve_open else ""
		"tap":
			if alt or not Game.water_running or _tap_uses() >= 2:
				return ""
			return "Fill bottles (+2 water)"
		"bathtub":
			if alt:
				return ""
			if Game.bathtub_water > 0:
				return "Scoop water (+1 water, %d left)" % Game.bathtub_water
			if Game.water_running and not Game.bathtub_filled_ever:
				return "Fill the bathtub"
			return ""
		"bed":
			if alt or Game.phase != Game.Phase.DAY or Game.minutes >= Game.REST_UNTIL - 30:
				return ""
			return "Rest until evening"
	return ""


func get_status() -> String:
	if _mode(false):
		return mode_handler.get_status(self)
	match kind:
		"stove":
			if Game.gas_leaking:
				return "(LEAKING)"
			return "(gas on)" if Game.gas_valve_open else "(gas off)"
		"tap":
			if not Game.water_running:
				return "(%s)" % (Game.water_note if Game.water_note != "" else "dry")
			if _tap_uses() >= 2:
				return "(pressure too low, try tomorrow)"
		"bathtub":
			if Game.bathtub_filled_ever and Game.bathtub_water <= 0:
				return "(empty)"
		"bed":
			if Game.phase == Game.Phase.NIGHT:
				return "(no sleeping tonight)"
	return ""


func get_flag() -> String:
	if kind == "stove" and Game.has_insight("prepared") and Game.gas_valve_open:
		return "GAS ON"
	return ""


func get_duration(alt: bool) -> float:
	if _mode(alt):
		return mode_handler.get_duration(self, alt)
	match kind:
		"stove":
			return 4.0 if alt else 1.5
		"tap":
			return 2.5
		"bathtub":
			return 1.0 if Game.bathtub_water > 0 else 4.0
		"bed":
			return 1.0
	return 1.0


func get_noise(alt: bool) -> float:
	if _mode(alt):
		return mode_handler.get_noise(self, alt)
	if kind == "stove" and alt:
		return 1.5
	if kind == "tap" or (kind == "bathtub" and Game.bathtub_water <= 0):
		return 1.2
	return 0.0


func perform(alt: bool) -> void:
	if _mode(alt):
		mode_handler.perform(self, alt)
		return
	match kind:
		"stove":
			if alt:
				Game.cook_meal()
			else:
				Game.gas_valve_open = false
				if Game.gas_leaking:
					Game.gas_leaking = false
					Game.say("You wrench the gas valve shut. The smell slowly fades.", "good")
				else:
					Game.say("You close the gas valve. No more hot meals, but nothing to leak.", "info")
		"tap":
			Game.tap_uses[Game.day] = _tap_uses() + 1
			Game.water += 2
			Game.say("You fill two bottles from the tap.", "good")
		"bathtub":
			if Game.bathtub_water > 0:
				Game.bathtub_water -= 1
				Game.water += 1
				Game.say("You scoop a bottle of water from the tub.", "info")
			else:
				Game.bathtub_water = 8
				Game.bathtub_filled_ever = true
				Game.say("The bathtub is full. That's eight bottles of water.", "good")
		"bed":
			get_tree().call_group("player", "sleep_on", self)
	if water_plane:
		water_plane.visible = Game.bathtub_water > 0
	Game.stats_changed.emit()


func _tap_uses() -> int:
	return Game.tap_uses.get(Game.day, 0)
