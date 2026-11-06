extends "res://scripts/world/interactable.gd"
## A hidden spot that holds a memory (scripts/data/story.gd SPOTS): behind the
## breaker panel, under the kotatsu, low on the front door, the wall clock, a
## photo frame face down on the TV stand.
##
## It only exists for the look-ray while one of its memories can turn up this
## life (layer 6, which nothing collides with and the navmesh never parses),
## so it never blocks a path, a door swing or another interactable until then.
## Known memories can be looked at again, once a life.

const Story := preload("res://scripts/data/story.gd")
const LAYER_LOOK := 32

var spot_id := ""
var prompt_text := "Look"
var visual_kind := "none"  # none | note_edge | note_floor | scratches | photo
var _shape: CollisionShape3D
var _available := false
var _marks: Node3D
var _marks_count := -1


func _ready() -> void:
	add_to_group("keepsake")
	super._ready()
	collision_layer = 0
	collision_mask = 0
	Game.stats_changed.connect(_refresh)
	Game.memory_found.connect(func(_id, _new): _refresh())
	Game.phase_changed.connect(func(_p): _refresh())
	_refresh()


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	_shape = Props.box_shape(size, Vector3(0, size.y * 0.5, 0))
	add_child(_shape)
	var paper := Props.mat(Color(0.94, 0.93, 0.88))
	match visual_kind:
		"note_edge":
			# A folded note pushed behind the panel, one corner showing below it.
			var n := Props.box(Vector3(0.07, 0.05, 0.002), Color.WHITE, Vector3(0.1, -0.015, -0.035))
			n.material_override = paper
			n.rotation.z = 0.35
			visual.add_child(n)
		"note_floor":
			# Taped to the underside of the kotatsu: a paper corner sticking out at the floor.
			var n := Props.box(Vector3(0.11, 0.002, 0.08), Color.WHITE, Vector3(-0.03, 0.004, 0))
			n.material_override = paper
			n.rotation.y = 0.3
			visual.add_child(n)
			var tape := Props.box(Vector3(0.05, 0.003, 0.02), Color(0.9, 0.85, 0.6, 0.8), Vector3(-0.08, 0.005, 0.02))
			visual.add_child(tape)
		"scratches":
			_marks = Node3D.new()
			visual.add_child(_marks)
		"photo":
			# A small photo frame lying face down: dark back board and a fold-out stand.
			var back := Props.box(Vector3(0.1, 0.016, 0.15), Color(0.22, 0.16, 0.11), Vector3(0, 0.008, 0))
			visual.add_child(back)
			var leg := Props.box(Vector3(0.024, 0.006, 0.07), Color(0.18, 0.13, 0.09), Vector3(0, 0.019, 0.015))
			visual.add_child(leg)
			var edge := Props.box(Vector3(0.104, 0.004, 0.154), Color(0.75, 0.7, 0.6), Vector3(0, 0.002, 0))
			visual.add_child(edge)


## The memory this spot would show right now ("" = none).
func current_memory() -> String:
	return Story.next_at(spot_id, Game.scenario_id(), Game.run_memories, false)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var mem := current_memory()
	_available = mem != "" and Game.phase != Game.Phase.DEAD
	collision_layer = LAYER_LOOK if _available else 0
	# The photo frame is always there; notes and scratches only once they're "real".
	if visual_kind != "photo":
		var any := Story.next_at(spot_id, Game.scenario_id(), [], false) != ""
		visual.visible = any
	if _marks:
		_build_marks()


## Tally marks scratched low on the door: one per morning before this one.
func _build_marks() -> void:
	var count: int = maxi(0, Meta.runs - 1)
	if count == _marks_count:
		return
	_marks_count = count
	for c in _marks.get_children():
		c.queue_free()
	var scratch := Props.mat(Color(0.86, 0.85, 0.82))  # bright bare metal under the paint
	var shown := mini(count, 40)
	for i in shown:
		var group := i / 5
		var k := i % 5
		var row := group / 4
		var x := -0.09 + (group % 4) * 0.055 + k * 0.009
		# On the steel leaf, which sits behind this spot's look-ray box.
		var m := Props.box(Vector3(0.004, 0.07, 0.002), Color.WHITE, Vector3(x * 1.3, 0.16 - row * 0.085, -0.112))
		m.material_override = scratch
		if k == 4:  # the fifth stroke crosses the group
			m.rotation.z = 1.15
			m.position.x = (-0.09 + (group % 4) * 0.055 + 0.018) * 1.3
		_marks.add_child(m)


func get_prompt(alt: bool) -> String:
	if alt or not _available:
		return ""
	return prompt_text


func get_status() -> String:
	return ""


func get_duration(_alt: bool) -> float:
	return 1.0


func perform(_alt: bool) -> void:
	var mem := current_memory()
	if mem == "":
		return
	Game.find_memory(mem)
	_refresh()
