extends "res://scripts/world/interactable.gd"
## Tall furniture that topples in an earthquake unless secured with a tension
## pole (突っ張り棒). It falls towards its front (local +Z). Dismantling it
## removes the hazard and yields materials.

const FALL_DAMAGE := 75.0
const SECURE_COST := 1
const DISMANTLE_YIELD := 2

var secured := false
var fallen := false
var pivot: Node3D
var shape_node: CollisionShape3D
var pole: MeshInstance3D


func _ready() -> void:
	add_to_group("hazard")
	super._ready()


func _build() -> void:
	# Pivot on the bottom front edge so the fall rotates around it.
	pivot = Node3D.new()
	pivot.position = Vector3(0, 0, size.z * 0.5)
	add_child(pivot)
	visual = Props.visual(model_name, size, color)
	visual.position = Vector3(0, 0, -size.z * 0.5)
	pivot.add_child(visual)
	shape_node = Props.box_shape(size, Vector3(0, size.y * 0.5, 0))
	add_child(shape_node)
	# Tension pole, hidden until secured. Wedged between top and ceiling.
	pole = Props.fbox(Vector3(0.05, 2.5 - size.y, 0.05), "plastic_white",
		Vector3(0, size.y + (2.5 - size.y) * 0.5, 0))
	pole.visible = false
	visual.add_child(pole)


func get_prompt(alt: bool) -> String:
	if fallen:
		return "Break it up for materials (+%d)" % DISMANTLE_YIELD if alt else ""
	if alt:
		return "Dismantle for materials (+%d)" % DISMANTLE_YIELD
	if secured:
		return ""
	return "Secure with a tension pole (%d material)" % SECURE_COST


func get_status() -> String:
	if fallen:
		return "(toppled)"
	return "(secured)" if secured else "(unsecured)"


func get_flag() -> String:
	if Game.has_insight("prepared") and not secured and not fallen:
		return "UNSECURED"
	return ""


func get_hold_sound(_alt: bool) -> String:
	return "hammer"


func get_duration(alt: bool) -> float:
	return 5.0 if alt else 2.5


func get_noise(alt: bool) -> float:
	return 3.0 if alt else 1.0


func perform(alt: bool) -> void:
	if alt:
		Game.materials += DISMANTLE_YIELD
		Game.say("You take the %s apart. +%d materials." % [display_name.to_lower(), DISMANTLE_YIELD], "good")
		Game.stats_changed.emit()
		Game.nav_dirty.emit()
		queue_free()
		return
	if Game.spend_materials(SECURE_COST):
		secured = true
		pole.visible = true
		Game.say("The %s is wedged firmly against the ceiling." % display_name.to_lower(), "good")
		refresh_flag()


## Called by the EventDirector when the shaking peaks.
func on_quake(player: Node3D) -> void:
	if secured or fallen or not is_inside_tree():
		return
	fallen = true
	var tween := create_tween()
	tween.tween_property(pivot, "rotation:x", PI * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Replace the standing collider with a lying one.
	var lying := Vector3(size.x, size.z, size.y)
	(shape_node.shape as BoxShape3D).size = lying
	shape_node.position = Vector3(0, lying.y * 0.5, size.z * 0.5 + size.y * 0.5)
	refresh_flag()
	Game.say("The %s topples over with a crash!" % display_name.to_lower(), "danger")
	Sfx.play("furniture_crash", global_position + Vector3(0, 0.5, 0), 4.0)
	Game.make_noise(global_position, 12.0)
	Game.shake.emit(0.5, 0.4)
	Game.nav_dirty.emit()
	if player and _in_fall_zone(player.global_position):
		if Game.player_sleeping and not Meta.has_perk("light_sleeper"):
			Game.damage(9999.0, "Crushed in your sleep by the unsecured %s." % display_name.to_lower())
		else:
			Game.damage(FALL_DAMAGE, "Crushed by the unsecured %s." % display_name.to_lower())
			if Game.is_alive_phase():
				Game.say("The %s lands on you!" % display_name.to_lower(), "danger")


func _in_fall_zone(point: Vector3) -> bool:
	var local := to_local(point)
	return (abs(local.x) < size.x * 0.5 + 0.35
		and local.z > size.z * 0.5 - 0.1
		and local.z < size.z * 0.5 + size.y + 0.3)
