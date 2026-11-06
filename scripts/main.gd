extends Node3D
## Assembles a run: environment, apartment, player, camera, directors, HUD.
## The scene is reloaded on every new run; persistent data lives in Meta.

const Apartment := preload("res://scripts/world/apartment.gd")
const Player := preload("res://scripts/player/player.gd")
const ScenarioWorld := preload("res://scripts/systems/scenario_world.gd")
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
	# Wake up next to the bed, facing the phone on the bedside table.
	player.global_position = Vector3(1.75, 0.05, 1.15)
	player.rotation.y = 0.0

	var zombies := Node3D.new()
	zombies.name = "Zombies"
	add_child(zombies)

	# The active scenario picks its directors and adjusts the world (clue
	# sources, loot, seal points): scripts/systems/scenario_world.gd.
	ScenarioWorld.build(self, zombies)

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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sky_mat.ground_horizon_color = Color(0.5, 0.5, 0.52)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	we.environment = env
	add_child(we)

	# Sunlight comes in through the balcony side (south-facing, as most
	# Japanese apartments are), low enough to reach under the eaves.
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-28, 165, 0)
	add_child(sun)


func _process(_delta: float) -> void:
	_update_daylight()


func _exit_tree() -> void:
	# Static material caches would otherwise outlive the scene ("resources still in use").
	const Props := preload("res://scripts/world/props.gd")
	Props._materials.clear()
	Props._surfaces.clear()


## Daylight follows the clock: day white, dusk orange, night dark blue.
func _update_daylight() -> void:
	var m := fmod(Game.minutes, 1440.0)
	var day_color := Color(1.0, 0.96, 0.88)
	var dusk_color := Color(1.0, 0.55, 0.3)
	var night_color := Color(0.35, 0.42, 0.65)
	var energy := 1.2
	var c := day_color
	var sky_e := 1.0
	if m >= 17 * 60 and m < 20 * 60:
		var t := (m - 17 * 60) / 180.0
		c = day_color.lerp(dusk_color, t)
		energy = lerp(1.2, 0.4, t)
		sky_e = lerp(1.0, 0.25, t)
	elif m >= 20 * 60 or m < 6 * 60:
		c = night_color
		energy = 0.12
		sky_e = 0.04
	sun.light_color = c
	sun.light_energy = energy
	env.background_energy_multiplier = sky_e
	env.ambient_light_energy = 0.35 if energy > 0.5 else 0.12
	env.ambient_light_color = Color(0.8, 0.8, 0.85) if energy > 0.5 else Color(0.35, 0.4, 0.6)
