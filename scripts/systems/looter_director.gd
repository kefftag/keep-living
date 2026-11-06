extends Node
## Ash's looters: on a couple of nights (Game.looter_nights) desperate people
## work a bar into the front door after midnight. Kept simple and readable:
## no bodies, just the door taking damage, the sounds and the messages. If it
## holds they move on. If it gives, they grab half of everything and hit you
## on the way out. Shouting through the door (R) may scare them off.

var door: Node3D    # the front door barricade
var player: Node3D

var _start_t := -1.0   # night seconds when they arrive (-1: not tonight)
var _night_t := 0.0
var _left := 0.0       # seconds of bashing left
var _dps := 0.0
var _shouted := false
var _done := false
var _taunt_t := 0.0


func _ready() -> void:
	Game.phase_changed.connect(_on_phase)
	if door:
		door.breached.connect(_on_breached)


func scenario() -> Script:
	return Game.scenario


func is_looter_night(day: int) -> bool:
	return day in Game.looter_nights


func _on_phase(phase: int) -> void:
	if phase == Game.Phase.NIGHT and is_looter_night(Game.day):
		var night_len := (Game.NIGHT_END - Game.NIGHT_START) / Game.NIGHT_MIN_PER_SEC
		# After midnight (4 game hours in), with time to finish before dawn.
		_start_t = randf_range(night_len * 0.4, night_len * 0.55)
		_night_t = 0.0
		_done = false
		_shouted = false
		if Game.has_insight("looters"):
			Game.say("Tonight is one of their nights. Brace the front door, and keep it shut.", "warn")
	elif phase != Game.Phase.NIGHT:
		_start_t = -1.0
		if Game.looters_active:
			_end("At first light the footsteps fade down the stairwell.")


## Smoke test / debugging: start an attempt right now.
func begin_attempt() -> void:
	var s := scenario()
	Game.looters_active = true
	_done = true
	_shouted = false
	_left = s.LOOTER_SECONDS
	_dps = s.LOOTER_DPS_BASE + s.LOOTER_DPS_PER_NIGHT * Game.day
	_taunt_t = 6.0
	Sfx.play("bang_door", door.global_position + Vector3(0, 1.2, 0.3), -2.0)
	Game.say("Footsteps in the corridor. Someone tries 304's handle, then yours. Metal scrapes into the gap of your front door.", "danger")


func _process(delta: float) -> void:
	if not Game.is_alive_phase() or door == null:
		return
	if Game.phase == Game.Phase.NIGHT and _start_t >= 0.0 and not _done:
		_night_t += delta
		if _night_t >= _start_t:
			begin_attempt()
	if not Game.looters_active:
		return
	_left -= delta
	door.take_damage(_dps * delta)
	_taunt_t -= delta
	if _taunt_t <= 0.0 and Game.looters_active:
		_taunt_t = randf_range(12.0, 18.0)
		Game.say(["\"Anyone in there? We just want water!\"", "\"Come on, we've got kids out here.\"", "The bar bites deeper. The door frame creaks.", "\"Get it open before someone comes.\""].pick_random(), "warn")
	if _left <= 0.0 and Game.looters_active:
		_end("The scraping stops. Footsteps move off down the corridor. You hear them start on 305.")


func shout() -> void:
	if _shouted:
		Game.say("They know you're bluffing now.", "info")
		return
	_shouted = true
	Game.make_noise(door.global_position, 6.0)
	var chance := 0.75 if Game.has_weapon else 0.3
	if Game.rng.randf() < chance:
		Sfx.play("bang_door", door.global_position + Vector3(0, 1.2, 0), 4.0)
		_end("A muttered argument outside, then running footsteps. They've decided this one isn't worth it.")
	else:
		_dps *= 1.5
		Game.say("A laugh outside. \"Then open up!\" They throw their weight into the bar.", "danger")


func _end(text: String) -> void:
	Game.looters_active = false
	Game.say(text, "good")
	Game.stats_changed.emit()


func _on_breached(_point) -> void:
	if not Game.looters_active:
		return
	var s := scenario()
	Game.looters_active = false
	var armed := Game.has_weapon
	var share := 0.25 if armed else 0.5
	var took: Array = []
	for key in ["food", "water", "masks", "materials", "medkits"]:
		var have: int = Game.get(key)
		var n := int(ceil(have * share)) if have > 0 else 0
		if n > 0:
			Game.set(key, have - n)
			took.append("%d %s" % [n, key])
	Sfx.play("hit_flesh", null, 0.0)
	if armed:
		Game.say("Two figures in masks shove in. You swing the bat and they back off, but they grab %s on the way out." % (", ".join(took) if not took.is_empty() else "nothing"), "danger")
	else:
		Game.say("Two figures in masks shove in, knock you down and take %s." % (", ".join(took) if not took.is_empty() else "nothing, there was nothing left"), "danger")
	Game.damage(s.LOOTER_HIT_ARMED if armed else s.LOOTER_HIT, s.DEATHS["looters"] % Game.day)
	Game.stats_changed.emit()
