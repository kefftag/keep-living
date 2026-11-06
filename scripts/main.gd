extends Node3D
## Assembles a run: environment, apartment, player, camera, directors, HUD.
## The scene is reloaded on every new run; persistent data lives in Meta.

const Apartment := preload("res://scripts/world/apartment.gd")
const Player := preload("res://scripts/player/player.gd")
const NightDirector := preload("res://scripts/systems/night_director.gd")
const EventDirector := preload("res://scripts/systems/event_director.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const SmokeTest := preload("res://scripts/dev/smoke_test.gd")
const EnvironmentRig := preload("res://scripts/world/environment_rig.gd")

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
	var rig := EnvironmentRig.new()
	rig.name = "Environment"
	add_child(rig)
	env = rig.env
	sun = rig.sun


func _exit_tree() -> void:
	# Static material caches would otherwise outlive the scene ("resources still in use").
	const Props := preload("res://scripts/world/props.gd")
	Props._materials.clear()
	Props._surfaces.clear()

