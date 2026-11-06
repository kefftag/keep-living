extends Node
## The strange things that happen in every scenario (docs/STORY.md "Omens"),
## escalating with Meta.runs; each fires at most once per life. Also drives the
## LDK wall clock's hands (the game time, 07:58 when the morning won't let go,
## the real time behind the title once the true ending has been seen) and
## rings the phone for the life-5 omen.
##
## Built for every scenario by scenario_world.gd. The final scenario (Monday)
## has no omens, only the clock.

const Story := preload("res://scripts/data/story.gd")

const CALL_SECONDS := 10.0       # real seconds the phone rings by itself
const CLOCK_HOLD_MINUTES := 120.0  # game minutes the clock stays on 07:58 after a rest
const STUCK := 7 * 60 + 58

# Where the wall clock model's hands point as authored (degrees clockwise from
# 12; the scan shows 10:10 and 30 s), measured from its vertices.
const MINUTE_REST := 57.0
const HOUR_REST := 306.8
const SECOND_REST := 170.5

var apartment: Node3D
var player: Node3D
var fired := {}        # omen id -> true, this life
var plan := {}         # omen id -> total game minutes it fires at
var rng := RandomNumberGenerator.new()

var _ringing_left := 0.0
var _buzz_t := 0.0
var _clock_hold_until := -1.0
var _hands := {}       # "minute" / "hour" / "second" -> Node3D
var _tick_t := 0.0
var _pending: Array = []  # [[seconds left, Callable]]
var _released := false  # the true ending: the morning is allowed to go on


## After the true ending the clock moves on, to 07:59 and onwards.
func release_clock() -> void:
	_released = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the clock keeps going behind the title
	rng.randomize()
	Game.phase_changed.connect(_on_phase)
	Game.woke_up.connect(_on_woke)
	# Daytime knocking on day 1 or 2, the voice under the radio static on the
	# first night, the phone call on day 1 (late morning to late afternoon).
	plan["knock"] = rng.randi_range(0, 1) * 1440 + rng.randi_range(11 * 60, 16 * 60)
	plan["radio"] = rng.randi_range(22 * 60, 26 * 60)
	plan["call"] = rng.randi_range(10 * 60 + 30, 17 * 60)
	if apartment:
		var phone = apartment.nav_region.get_node_or_null("phone")
		if phone:
			phone.call_handler = self
		if apartment.get("wall_clock"):
			_find_hands(apartment.wall_clock)


## True if `id` may fire in this life.
func can_fire(id: String) -> bool:
	if Game.is_monday() or fired.has(id):
		return false
	return Meta.runs >= int(Story.omen(id).get("from", 99))


func _process(delta: float) -> void:
	_update_clock(delta)
	if get_tree().paused:
		return
	_run_pending(delta)
	if not Game.is_alive_phase() or Game.is_monday():
		return
	var now := Game.total_minutes()
	for id in ["knock", "radio", "call"]:
		if plan.has(id) and now >= plan[id] and can_fire(id):
			if id == "radio" and Game.phase != Game.Phase.NIGHT:
				continue
			if id != "radio" and Game.phase != Game.Phase.DAY:
				continue
			fire(id)
	if _ringing_left > 0.0:
		_ringing_left -= delta
		_buzz_t -= delta
		if _buzz_t <= 0.0:
			_buzz_t = 1.6
			var phone = _phone()
			Sfx.play("phone_buzz", phone.global_position + Vector3(0, 0.5, 0) if phone else null, -2.0, 0.0)
		if _ringing_left <= 0.0:
			Game.say(Story.omen("call")["missed"], "info")


## Fire an omen now (also used by the smoke test).
func fire(id: String) -> void:
	fired[id] = true
	var o := Story.omen(id)
	match id:
		"siren":
			# Far off, coming closer down the street on the corridor side, then it stops.
			Sfx.play("siren", Vector3(9.0, -6.0, 18.0), 4.0, 0.0, 90.0)
			_later(7.5, func(): Game.say(o["text"], "warn"))
		"knock":
			var door = apartment.barricades.get("front_door") if apartment else null
			var at: Vector3 = door.global_position + Vector3(0, 1.1, 0) if door else Vector3(3.3, 1.0, 7.4)
			for i in 3:  # three slow knocks: a fist, quieter than a siege
				_later(i * 1.1, func(): Sfx.play("bang_door", at, -13.0, 0.04, 20.0))
			_later(3.3, func(): Game.say(o["text"], "warn"))
			_later(6.5, func(): Game.say(o["after"], "info"))
		"radio":
			var radio = apartment.nav_region.get_node_or_null("radio") if apartment else null
			if radio:
				var hiss := Sfx.loop_on("radio_static", radio, -4.0, Vector3(0, 0.45, 0))
				_later(7.0, func():
					if is_instance_valid(hiss):
						hiss.queue_free())
			_later(1.5, func(): Game.voice(o["text"], "warn"))
		"call":
			_ringing_left = CALL_SECONDS
			_buzz_t = 0.0
			Game.say(o["text"], "warn")
		"clock":
			_clock_hold_until = Game.total_minutes() + CLOCK_HOLD_MINUTES
			Game.say(o["text"] % Game.clock_string(), "warn")
	print("STORY: omen ", id)


# --- The phone call (clue_source.gd's call_handler) ---------------------------------

func is_ringing() -> bool:
	return _ringing_left > 0.0


func answer() -> void:
	_ringing_left = 0.0
	var phone = _phone()
	Sfx.play("radio_static", phone.global_position + Vector3(0, 0.5, 0) if phone else null, -6.0, 0.0)
	_later(1.2, func(): Game.voice(Story.omen("call")["answer"], "warn"))
	Game.flags["mother_call"] = true


func _phone() -> Node3D:
	return apartment.nav_region.get_node_or_null("phone") if apartment else null


# --- Triggers --------------------------------------------------------------------

func _on_phase(phase: int) -> void:
	# The first dawn of the life (night -> day).
	if phase == Game.Phase.DAY and Game.day > 1 and can_fire("siren"):
		fire("siren")


func _on_woke() -> void:
	if can_fire("clock"):
		fire("clock")


## Run `cb` after `seconds` of play (paused time doesn't count). A queue on
## this node rather than SceneTreeTimers, so nothing outlives a scene reload.
func _later(seconds: float, cb: Callable) -> void:
	if seconds <= 0.0:
		cb.call()
		return
	_pending.append([seconds, cb])


func _run_pending(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var cb: Callable = _pending[i][1]
			_pending.remove_at(i)
			cb.call()
		else:
			i += 1


# --- The wall clock -----------------------------------------------------------------

func _find_hands(root: Node) -> void:
	for n in root.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.ends_with("minute_hand"):
			_hands["minute"] = n
		elif nm.ends_with("hours_hand") or nm.ends_with("hour_hand"):
			_hands["hour"] = n
		elif nm.ends_with("second_hand"):
			_hands["second"] = n


## What the wall clock shows, in minutes after midnight.
func clock_minutes() -> float:
	if _released:
		return STUCK + 1
	if Game.is_monday():
		return STUCK
	if Game.show_title and Game.phase == Game.Phase.INTRO and Meta.true_ending:
		var t := Time.get_time_dict_from_system()
		return t["hour"] * 60.0 + t["minute"]
	if _clock_hold_until > 0.0 and Game.total_minutes() < _clock_hold_until:
		return STUCK
	if Game.phase == Game.Phase.INTRO:
		return STUCK  # the alarm is going; it's 07:58
	return fmod(Game.minutes, 1440.0)


func is_stuck() -> bool:
	return not _released and is_equal_approx(clock_minutes(), STUCK) and not (Game.show_title and Meta.true_ending)


func _update_clock(delta: float) -> void:
	if _hands.is_empty():
		return
	var m := clock_minutes()
	var minute_deg := fmod(m, 60.0) * 6.0
	var hour_deg := fmod(m / 60.0, 12.0) * 30.0
	_set_hand("minute", minute_deg, MINUTE_REST)
	_set_hand("hour", hour_deg, HOUR_REST)
	# The second hand: ticks with real seconds, or twitches and goes back.
	_tick_t += delta
	var sec_deg: float
	if is_stuck():
		sec_deg = 6.0 if fmod(_tick_t, 1.0) < 0.12 else 0.0
	else:
		sec_deg = floorf(fmod(Time.get_ticks_msec() / 1000.0, 60.0)) * 6.0
	_set_hand("second", sec_deg, SECOND_REST)


func _set_hand(key: String, deg: float, rest: float) -> void:
	var n: Node3D = _hands.get(key)
	if n == null:
		return
	# The model faces +Z: a positive rotation about Z turns a hand anticlockwise.
	n.rotation = Vector3(0, 0, -deg_to_rad(deg - rest))
