extends Node
## Player settings, saved to user://settings.cfg and applied at boot.
## Audio buses come from sfx.gd: "World" is sound effects, "Ambience" is the
## ambience / music bed.

signal changed

const PATH := "user://settings.cfg"
const SMOKE_PATH := "user://settings_smoke.cfg"
const SECTION := "settings"

const DEFAULTS := {
	"master_volume": 0.9,     # 0..1
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"mouse_sensitivity": 1.0, # multiplier on the player's base sensitivity
	"invert_y": false,
	"fov": 72.0,
	"fullscreen": false,
	"resolution_scale": 1.0,  # 3D render scale, 0.5..1.0
	"vsync": true,
	"reduce_shake": false,
	"subtitles": true,        # captions for important sounds
	"large_text": false,
}
const LARGE_TEXT_SCALE := 1.15

var values := DEFAULTS.duplicate()
var path := PATH
var _smoke := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_smoke = "--smoke-test" in OS.get_cmdline_user_args()
	if _smoke:
		path = SMOKE_PATH  # never touch the player's settings
	else:
		load_settings()
	# Sfx creates its buses in its own _ready (it loads after us): apply then.
	apply.call_deferred()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	apply()
	save_settings()
	changed.emit()


func reset_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply()
	save_settings()
	changed.emit()


# Convenience getters for gameplay code.
func mouse_factor() -> float:
	return float(get_value("mouse_sensitivity"))


func invert_y() -> bool:
	return bool(get_value("invert_y"))


func fov() -> float:
	return float(get_value("fov"))


func shake_scale() -> float:
	return 0.25 if bool(get_value("reduce_shake")) else 1.0


func subtitles() -> bool:
	return bool(get_value("subtitles"))


func apply() -> void:
	_set_bus("Master", float(get_value("master_volume")))
	_set_bus("Ambience", float(get_value("music_volume")))
	_set_bus("World", float(get_value("sfx_volume")))
	if not is_inside_tree():
		return
	var root := get_tree().root
	root.scaling_3d_scale = clamp(float(get_value("resolution_scale")), 0.5, 1.0)
	root.content_scale_factor = LARGE_TEXT_SCALE if bool(get_value("large_text")) else 1.0
	if _smoke or DisplayServer.get_name() == "headless":
		return  # screenshot runs keep their background window as it is
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("fullscreen")) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(max(linear, 0.001)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value(SECTION, k, values[k])
	cfg.save(path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for k in DEFAULTS:
		var v = cfg.get_value(SECTION, k, DEFAULTS[k])
		if typeof(v) == typeof(DEFAULTS[k]) or (typeof(DEFAULTS[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
			values[k] = v
