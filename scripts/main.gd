extends Node3D
## Assembles a run: environment, apartment, player, camera, directors, HUD.
## The scene is reloaded on every new run; persistent data lives in Meta.

const Apartment := preload("res://scripts/world/apartment.gd")
const Player := preload("res://scripts/player/player.gd")
const CameraRig := preload("res://scripts/systems/camera_rig.gd")
const NightDirector := preload("res://scripts/systems/night_director.gd")
const EventDirector := preload("res://scripts/systems/event_director.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const SmokeTest := preload("res://scripts/dev/smoke_test.gd")

var apartment: Node3D
var player: CharacterBody3D
var sun: DirectionalLight3D
var env: Environment
var hud: CanvasLayer


func _ready() -> void:
	_build_environment()

	apartment = Apartment.new()
	apartment.name = "Apartment"
	add_child(apartment)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(5.0, 0.1, 4.6)

	var cam := CameraRig.new()
	cam.target = player
	add_child(cam)

	var zombies := Node3D.new()
	zombies.name = "Zombies"
	add_child(zombies)

	var night := NightDirector.new()
	night.name = "NightDirector"
	night.barricades = apartment.barricades
	night.player = player
	night.zombie_parent = zombies
	add_child(night)

	var events := EventDirector.new()
	events.name = "EventDirector"
	events.player = player
	add_child(events)

	hud = Hud.new()
	hud.name = "HUD"
	hud.player = player
	hud.barricades = apartment.barricades
	add_child(hud)

	if "--smoke-test" in OS.get_cmdline_user_args():
		var smoke := SmokeTest.new()
		smoke.main = self
		add_child(smoke)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)


func _process(_delta: float) -> void:
	_update_daylight()


## Daylight follows the clock: noon white, dusk orange, night dark blue.
func _update_daylight() -> void:
	var m := fmod(Game.minutes, 1440.0)
	var day_color := Color(1.0, 0.97, 0.9)
	var dusk_color := Color(1.0, 0.55, 0.3)
	var night_color := Color(0.35, 0.42, 0.65)
	var energy := 0.9
	var c := day_color
	var bg := Color(0.55, 0.62, 0.7)
	if m >= 17 * 60 and m < 20 * 60:
		var t := (m - 17 * 60) / 180.0
		c = day_color.lerp(dusk_color, t)
		energy = lerp(0.9, 0.45, t)
		bg = bg.lerp(Color(0.6, 0.35, 0.3), t)
	elif m >= 20 * 60 or m < 6 * 60:
		c = night_color
		energy = 0.18
		bg = Color(0.05, 0.06, 0.1)
	sun.light_color = c
	sun.light_energy = energy
	env.background_color = bg
	env.ambient_light_energy = 0.4 if energy > 0.5 else 0.25
	env.ambient_light_color = Color(0.75, 0.78, 0.85) if energy > 0.5 else Color(0.35, 0.4, 0.6)
