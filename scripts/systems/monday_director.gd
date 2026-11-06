extends Node
## The final scenario's morning (scenario_monday.gd). Not a threat director:
## birds on the balcony, a train in the distance, and from the start someone
## knocking at the front door, a calm voice behind it (subtitles + messages).
##
## It is also the entrances' mode_handler: the front door's E opens it (the
## true ending), and nothing else needs boarding today.

const Story := preload("res://scripts/data/story.gd")

const KNOCK_EVERY := [13.0, 17.0]  # real seconds between knocks
const TRAIN_EVERY := [35.0, 55.0]

var apartment: Node3D
var player: Node3D
var _knock_t := 3.0
var _train_t := 12.0
var _line := 0
var _birds: AudioStreamPlayer3D
var _pending: Array = []  # [[seconds left, Callable]]: no timers outlive the scene


func _ready() -> void:
	if apartment:
		for id in apartment.barricades:
			apartment.barricades[id].mode_handler = self
		var bal = apartment.barricades.get("balcony_door")
		if bal:
			_birds = Sfx.loop_on("birds", bal, -8.0, Vector3(0, 1.6, 1.2))


func _process(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var cb: Callable = _pending[i][1]
			_pending.remove_at(i)
			cb.call()
		else:
			i += 1
	if not Game.is_alive_phase():
		return
	_knock_t -= delta
	if _knock_t <= 0.0:
		_knock_t = randf_range(KNOCK_EVERY[0], KNOCK_EVERY[1])
		knock()
	_train_t -= delta
	if _train_t <= 0.0:
		_train_t = randf_range(TRAIN_EVERY[0], TRAIN_EVERY[1])
		Sfx.play("train_far", Vector3(-30.0, -4.0, -60.0), 2.0, 0.03, 120.0)


## Three knocks, then the next thing the voice says.
func knock() -> void:
	var door = apartment.barricades.get("front_door") if apartment else null
	var at: Vector3 = door.global_position + Vector3(0, 1.1, 0.1) if door else Vector3(3.3, 1.0, 7.4)
	for i in 3:
		_pending.append([i * 0.6, func(): Sfx.play("bang_door", at, -10.0, 0.05, 25.0)])
	var text: String = Story.MONDAY_VOICE[_line % Story.MONDAY_VOICE.size()]
	_line += 1
	var say := func():
		if Game.is_alive_phase():
			Game.voice(text, "info")
	_pending.append([2.2, say])


# --- Entrances (barricade_point.gd mode_handler) -------------------------------------

func _is_front(b) -> bool:
	return b.point_id == "front_door"


func get_prompt(b, alt: bool) -> String:
	if alt or not _is_front(b):
		return ""
	return "Open the door"


func get_status(b) -> String:
	return "(someone is knocking)" if _is_front(b) else ""


func get_duration(_b, _alt: bool) -> float:
	return 2.5


func get_hold_sound(_b, _alt: bool) -> String:
	return ""


func get_noise(_b, _alt: bool) -> float:
	return 0.0


func get_flag(_b) -> String:
	return ""


func perform(b, alt: bool) -> void:
	if alt or not _is_front(b):
		return
	Sfx.play("door_open", b.global_position + Vector3(0, 1.0, 0), -2.0)
	Game.ending_requested.emit("door")


func on_breached(_b) -> void:
	pass
