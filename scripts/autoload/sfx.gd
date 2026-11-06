extends Node
## Sound. 3D one-shots and loops on a "World" bus with small-room reverb,
## plus day/night ambience and a low-health heartbeat on "Ambience".
## Files live in assets/audio (see tools/audio/make_sounds.py); a name with
## variants (step_wood_0..3) is played as "step_wood" and picks one at random.

const DIR := "res://assets/audio/"
const LOOPS := ["gas_hiss", "fridge_hum", "radio_static", "heartbeat", "helicopter", "ambience_day", "ambience_night",
	"wind_storm", "rain_glass", "birds"]

var _streams := {}     # name -> Array[AudioStream]
var _ambience: Array = []  # [day player, night player]
var _heartbeat: AudioStreamPlayer

## Every one-shot request (the HUD turns some into subtitles).
signal played(sound: String, pos: Variant)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_all()
	for n in ["ambience_day", "ambience_night"]:
		var p := AudioStreamPlayer.new()
		p.stream = _pick(n)
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		_ambience.append(p)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = _pick("heartbeat")
	_heartbeat.bus = "Ambience"
	_heartbeat.volume_db = -80.0
	add_child(_heartbeat)


func _exit_tree() -> void:
	_streams.clear()


func _setup_buses() -> void:
	if AudioServer.get_bus_index("World") != -1:
		return
	for bus_name in ["World", "Ambience"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	var reverb := AudioEffectReverb.new()  # a small, hard-walled apartment
	reverb.room_size = 0.25
	reverb.damping = 0.6
	reverb.wet = 0.18
	reverb.dry = 0.95
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), reverb)


func _load_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".wav"):
			continue
		var base := file.get_basename()
		var stream: AudioStream = load(DIR + file)
		if stream == null:
			continue
		var key := base
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			key = parts[0]
		if base in LOOPS and stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / 2  # 16-bit mono frames
		if not _streams.has(key):
			_streams[key] = []
		if not (stream in _streams[key]):
			_streams[key].append(stream)


func _pick(sound: String) -> AudioStream:
	var list: Array = _streams.get(sound, [])
	return list[randi() % list.size()] if list.size() > 0 else null


func has(sound: String) -> bool:
	return _streams.has(sound)


## One-shot at a world position (or non-positional if pos is null).
func play(sound: String, pos: Variant = null, volume_db: float = 0.0, pitch_jitter: float = 0.06, max_dist: float = 25.0) -> void:
	played.emit(sound, pos)  # for subtitles, even when the clip is missing
	var stream := _pick(sound)
	if stream == null or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if pos is Vector3 and scene:
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.bus = "World"
		p.volume_db = volume_db
		p.unit_size = 3.0
		p.max_distance = max_dist
		p.attenuation_filter_cutoff_hz = 6000.0
		p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		scene.add_child(p)
		p.global_position = pos
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "World"
		p.volume_db = volume_db
		p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


## A looping 3D emitter attached to `parent` (e.g. the fridge). Returns it so
## the caller can stop / free it.
func loop_on(sound: String, parent: Node3D, volume_db: float = 0.0, offset: Vector3 = Vector3.ZERO) -> AudioStreamPlayer3D:
	var stream := _pick(sound)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "World"
	p.volume_db = volume_db
	p.unit_size = 2.0
	p.max_distance = 12.0
	p.position = offset
	parent.add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if _ambience.is_empty():
		return
	var alive := Game.is_alive_phase()
	var night := Game.phase == Game.Phase.NIGHT
	var want_day := -12.0 if alive and not night else -80.0
	var want_night := -8.0 if alive and night else -80.0
	if Game.is_storm_mode() and Game.storm_level > 0.3:
		want_day -= 14.0  # the typhoon drowns out the city (its own loops play instead)
		want_night -= 10.0
	_fade(_ambience[0], want_day, delta)
	_fade(_ambience[1], want_night, delta)
	var low := alive and Game.health < Game.max_health * 0.3
	var hb := -4.0 if low else -80.0
	if alive and Game.is_monday():
		hb = -9.0  # something is wrong with you, even this morning
	_fade(_heartbeat, hb, delta * 3.0)


func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	if p.stream == null:
		return
	if target > -79.0 and not p.playing:
		p.play()
	p.volume_db = move_toward(p.volume_db, target, 20.0 * delta)
	if p.volume_db <= -79.0 and p.playing and target <= -79.0:
		p.stop()
