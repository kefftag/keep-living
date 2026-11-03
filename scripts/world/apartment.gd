extends Node3D
## Builds the apartment: a Tokyo 1LDK on the 3rd floor, plus the balcony,
## the shared outdoor corridor and a skyline. Everything is grey-boxed in code;
## any prop with a matching .glb in assets/models/ is swapped for the model.
##
## Coordinates (metres): +X east, +Z south (towards the camera). Interior spans
## x 0..9, z 0..7.5. North = balcony side, south = outdoor corridor side.
##
##   z=-1.6 +---------------- balcony ------------------+
##   z=0    | bedroom   [win]    |  LDK      [balcony dr] |
##          |  wardrobe  bed     |  bookshelf  kotatsu  K |
##   z=4    +--------------------+---[ ]-----------------+
##          |               corridor                     |
##   z=5.2  +-[ ]----+--[ ]--+--[ ]--+                    |
##          |  bath  | toilet| closet|   genkan           |
##   z=7.5  +--[win]-+-------+-------+------[front door]--+
##          |            outdoor corridor → stairwell     |
##   z=9    +---------------------------------------------+

const Props := preload("res://scripts/world/props.gd")
const LootContainer := preload("res://scripts/world/loot_container.gd")
const ClueSource := preload("res://scripts/world/clue_source.gd")
const Hazard := preload("res://scripts/world/furniture_hazard.gd")
const Utility := preload("res://scripts/world/utilities.gd")
const Barricade := preload("res://scripts/world/barricade_point.gd")

const WALL_T := 0.15
const WALL_H := 2.6
const CUT_H := 1.25  # walls are drawn sliced at this height so the camera sees in

const FACE_S := 0.0          # front faces +Z (south)
const FACE_N := PI           # front faces -Z (north)
const FACE_E := PI * 0.5     # front faces +X (east)
const FACE_W := -PI * 0.5    # front faces -X (west)

const C_EXT := Color(0.74, 0.72, 0.69)
const C_INT := Color(0.82, 0.8, 0.76)
const C_WOOD := Color(0.62, 0.45, 0.3)

var nav_region: NavigationRegion3D
var barricades := {}  # id -> barricade node
var room_lights: Array = []
var window_lights: Array = []  # emissive skyline windows (go dark when power fails city-wide)
var _rebake_queued := false


func _ready() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.3
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.2
	nm.filter_baking_aabb = AABB(Vector3(-1, -0.5, -2), Vector3(14, 3, 12))
	nav_region.navigation_mesh = nm
	add_child(nav_region)

	_build_floors()
	_build_walls()
	_build_barricades()
	_build_furniture()
	_build_lights()
	_build_skyline()
	Game.nav_dirty.connect(_queue_rebake)
	Game.world_changed.connect(_on_world_changed)
	bake()


func bake() -> void:
	nav_region.bake_navigation_mesh(false)


func _queue_rebake() -> void:
	if _rebake_queued:
		return
	_rebake_queued = true
	# Wait for queue_free / collider changes to land before re-parsing.
	await get_tree().create_timer(0.7).timeout
	_rebake_queued = false
	if is_inside_tree():
		bake()


# --- Structure -----------------------------------------------------------------

func _static(parent: Node, size: Vector3, center: Vector3, color: Color, visual_h: float = -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	body.add_child(Props.box_shape(size))
	var vh: float = size.y if visual_h < 0.0 else min(visual_h, size.y)
	var bottom := -size.y * 0.5
	body.add_child(Props.box(Vector3(size.x, vh, size.z), color, Vector3(0, bottom + vh * 0.5, 0)))
	parent.add_child(body)
	return body


func _build_floors() -> void:
	# One collider for everything walkable.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.add_child(Props.box_shape(Vector3(12.5, 0.2, 10.6), Vector3(5.75, -0.1, 3.7)))
	nav_region.add_child(floor_body)
	# Visual floors per room.
	var floors := [
		[Rect2(0, 0, 4, 4), Color(0.72, 0.74, 0.55)],        # bedroom (tatami)
		[Rect2(4, 0, 5, 4), Color(0.6, 0.46, 0.33)],          # LDK (wood)
		[Rect2(0, 4, 9, 1.2), Color(0.58, 0.45, 0.33)],       # corridor
		[Rect2(0, 5.2, 3, 2.3), Color(0.78, 0.82, 0.85)],     # bath (tile)
		[Rect2(3, 5.2, 1.5, 2.3), Color(0.8, 0.8, 0.8)],      # toilet
		[Rect2(4.5, 5.2, 1.5, 2.3), Color(0.55, 0.43, 0.32)], # closet
		[Rect2(6, 5.2, 3, 2.3), Color(0.45, 0.45, 0.47)],     # genkan (stone)
		[Rect2(0, -1.6, 9, 1.6), Color(0.5, 0.5, 0.52)],      # balcony
		[Rect2(-0.5, 7.5, 12.5, 1.5), Color(0.42, 0.42, 0.44)], # outdoor corridor
	]
	for f in floors:
		var r: Rect2 = f[0]
		add_child(Props.box(Vector3(r.size.x, 0.02, r.size.y), f[1],
			Vector3(r.position.x + r.size.x * 0.5, 0.0, r.position.y + r.size.y * 0.5)))


## Axis-aligned wall from a to b (XZ) with gaps at `openings` ([start, end]
## distances along the wall from a).
func _wall(a: Vector2, b: Vector2, openings: Array = [], color: Color = C_INT, height: float = WALL_H, cut: float = CUT_H) -> void:
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var solid: Array = []
	var cursor := 0.0
	var sorted := openings.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for o in sorted:
		if o[0] > cursor:
			solid.append([cursor, o[0]])
		cursor = o[1]
	if cursor < length:
		solid.append([cursor, length])
	for seg in solid:
		var seg_len: float = seg[1] - seg[0]
		var mid: Vector2 = a + dir * (seg[0] + seg_len * 0.5)
		var size: Vector3 = Vector3(seg_len + WALL_T, height, WALL_T) if abs(dir.x) > 0.5 else Vector3(WALL_T, height, seg_len + WALL_T)
		_static(nav_region, size, Vector3(mid.x, height * 0.5, mid.y), color, cut)


func _build_walls() -> void:
	# Exterior
	_wall(Vector2(0, 0), Vector2(9, 0), [[1.0, 3.0], [5.5, 7.5]], C_EXT)        # north
	_wall(Vector2(0, 7.5), Vector2(9, 7.5), [[1.2, 2.1], [7.0, 8.0]], C_EXT)    # south
	_wall(Vector2(0, 0), Vector2(0, 7.5), [], C_EXT)                             # west
	_wall(Vector2(9, 0), Vector2(9, 7.5), [], C_EXT)                             # east
	# Interior
	_wall(Vector2(4, 0), Vector2(4, 4), [[1.5, 2.5]])            # bedroom | LDK
	_wall(Vector2(0, 4), Vector2(9, 4), [[4.6, 5.6]])            # rooms | corridor
	_wall(Vector2(0, 5.2), Vector2(6, 5.2), [[1.0, 2.0], [3.3, 4.3], [4.8, 5.7]])
	_wall(Vector2(3, 5.2), Vector2(3, 7.5))
	_wall(Vector2(4.5, 5.2), Vector2(4.5, 7.5))
	_wall(Vector2(6, 5.2), Vector2(6, 7.5))
	# Balcony: railing + the thin emergency partitions to the neighbours.
	_wall(Vector2(0, -1.6), Vector2(9, -1.6), [], Color(0.4, 0.42, 0.45), 1.1, 1.1)
	_wall(Vector2(0, -1.6), Vector2(0, 0), [], Color(0.75, 0.75, 0.7), 1.8, 1.25)
	_wall(Vector2(9, -1.6), Vector2(9, 0), [], Color(0.75, 0.75, 0.7), 1.8, 1.25)
	# Outdoor corridor: railing, end wall, neighbours' facades.
	_wall(Vector2(-0.5, 9), Vector2(12, 9), [], Color(0.4, 0.42, 0.45), 1.1, 1.1)
	_wall(Vector2(-0.5, 7.5), Vector2(-0.5, 9), [], C_EXT)
	_wall(Vector2(9, 7.5), Vector2(12, 7.5), [], C_EXT)
	_wall(Vector2(12, 7.5), Vector2(12, 9), [], C_EXT)
	# A neighbour's door (unit 304), just for set dressing.
	add_child(Props.box(Vector3(0.9, 1.25, 0.06), Color(0.4, 0.42, 0.46), Vector3(10.5, 0.62, 7.56)))


# --- Entrances ---------------------------------------------------------------

func _build_barricades() -> void:
	var balcony_spawns := [Vector3(0.5, 0, -0.8), Vector3(8.5, 0, -0.8)]
	var stair_spawns := [Vector3(11.5, 0, 8.25)]
	_add_barricade("bedroom_window", "Bedroom window", Vector3(2.0, 0, 0), FACE_N, 2.0, 100.0, 0.8, 2.0, false, balcony_spawns)
	_add_barricade("balcony_door", "Balcony door", Vector3(6.5, 0, 0), FACE_N, 2.0, 120.0, 0.0, 2.1, false, balcony_spawns)
	_add_barricade("front_door", "Front door", Vector3(7.5, 0, 7.5), FACE_S, 1.0, 300.0, 0.0, 2.1, true, stair_spawns)
	_add_barricade("bath_window", "Bathroom window", Vector3(1.65, 0, 7.5), FACE_S, 0.9, 70.0, 1.0, 1.6, false, stair_spawns)


func _add_barricade(id: String, label: String, pos: Vector3, facing: float, width: float, hp: float,
		sill: float, opening_h: float, is_door: bool, spawns: Array) -> void:
	var b = Barricade.new()
	b.name = id
	b.point_id = id
	b.display_name = label
	b.size = Vector3(width, CUT_H, 0.2)
	b.base_hp = hp
	b.sill = sill
	b.opening_height = opening_h
	b.is_door = is_door
	b.spawn_origins = spawns
	b.position = pos
	b.rotation.y = facing
	add_child(b)  # not under the nav region: the navmesh keeps a path through it
	barricades[id] = b


# --- Furniture & interactables --------------------------------------------------

func _place(node: Node3D, pos: Vector3, facing: float) -> Node3D:
	node.position = pos
	node.rotation.y = facing
	nav_region.add_child(node)
	return node


func _loot(id: String, label: String, model: String, size: Vector3, color: Color, pos: Vector3, facing: float,
		loot: Dictionary, clue := "", verb := "Search") -> Node3D:
	var c = LootContainer.new()
	c.name = id
	c.container_id = id
	c.display_name = label
	c.model_name = model
	c.size = size
	c.color = color
	c.loot = loot
	c.clue_id = clue
	c.search_verb = verb
	return _place(c, pos, facing)


func _clue(id: String, label: String, model: String, size: Vector3, color: Color, pos: Vector3, facing: float,
		verb: String, entries: Array, idle := "(nothing new)") -> Node3D:
	var c = ClueSource.new()
	c.name = id
	c.display_name = label
	c.model_name = model
	c.size = size
	c.color = color
	c.verb = verb
	c.entries = entries
	c.idle_status = idle
	return _place(c, pos, facing)


func _utility(kind: String, label: String, model: String, size: Vector3, color: Color, pos: Vector3, facing: float) -> Node3D:
	var u = Utility.new()
	u.name = kind
	u.kind = kind
	u.display_name = label
	u.model_name = model
	u.size = size
	u.color = color
	return _place(u, pos, facing)


func _hazard(id: String, label: String, model: String, size: Vector3, color: Color, pos: Vector3, facing: float) -> Node3D:
	var h = Hazard.new()
	h.name = id
	h.display_name = label
	h.model_name = model
	h.size = size
	h.color = color
	return _place(h, pos, facing)


func _deco(model: String, size: Vector3, color: Color, pos: Vector3, facing: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.add_child(Props.visual(model, size, color))
	body.add_child(Props.box_shape(size, Vector3(0, size.y * 0.5, 0)))
	_place(body, pos, facing)


func _build_furniture() -> void:
	var day2 := 1440 + 7 * 60
	# Bedroom
	_utility("bed", "Futon bed", "bed", Vector3(1.4, 0.45, 2.0), Color(0.85, 0.85, 0.92), Vector3(2.0, 0, 2.9), FACE_S)
	_hazard("wardrobe", "Wardrobe", "wardrobe", Vector3(1.0, 1.9, 0.6), Color(0.55, 0.4, 0.28), Vector3(3.63, 0, 3.3), FACE_W)
	_clue("phone", "Phone", "side_table", Vector3(0.4, 0.45, 0.4), Color(0.3, 0.3, 0.35), Vector3(0.85, 0, 3.55), FACE_E,
		"Check", [{"clue": "jalert"}], "(no new messages)")
	_loot("drawer_chest", "Chest of drawers", "drawer_chest", Vector3(1.0, 0.9, 0.5), C_WOOD, Vector3(0.33, 0, 1.0), FACE_E,
		{"medkits": 1, "materials": 1})
	_clue("laptop", "Laptop", "desk", Vector3(0.9, 0.72, 0.55), Color(0.5, 0.5, 0.55), Vector3(3.5, 0, 0.35), FACE_S,
		"Use", [{"clue": "forum_rescue", "from": day2, "needs_power": true}], "(the forums won't load yet)")
	# LDK
	_loot("kitchen_cabinets", "Kitchen cabinets", "kitchen_cabinet", Vector3(1.0, 0.9, 0.55), Color(0.8, 0.8, 0.78),
		Vector3(8.65, 0, 0.9), FACE_W, {"food": 3})
	_utility("tap", "Kitchen sink", "kitchen_sink", Vector3(0.7, 0.9, 0.55), Color(0.75, 0.78, 0.8), Vector3(8.65, 0, 1.75), FACE_W)
	_utility("stove", "Gas stove", "gas_stove", Vector3(0.7, 0.9, 0.55), Color(0.3, 0.3, 0.32), Vector3(8.65, 0, 2.45), FACE_W)
	var fridge = _loot("fridge", "Fridge", "fridge", Vector3(0.7, 1.8, 0.65), Color(0.9, 0.9, 0.92), Vector3(8.6, 0, 3.35), FACE_W,
		{"food": 2, "water": 2})
	fridge.spoils_without_power = true
	_hazard("bookshelf", "Bookshelf", "bookshelf", Vector3(1.0, 1.9, 0.45), Color(0.5, 0.36, 0.25), Vector3(4.31, 0, 3.3), FACE_E)
	_clue("tv", "TV", "tv_stand", Vector3(1.2, 0.55, 0.4), Color(0.15, 0.15, 0.17), Vector3(7.1, 0, 3.7), FACE_N,
		"Watch", [{"clue": "tv_shibuya", "needs_power": true}], "(colour bars)")
	_clue("radio", "Hand-crank radio", "kotatsu", Vector3(0.9, 0.4, 0.9), Color(0.6, 0.42, 0.3), Vector3(6.4, 0, 2.0), FACE_S,
		"Listen to", [{"clue": "radio_sound", "night_only": true}], "(static... maybe at night)")
	_clue("binoculars", "Binoculars", "binocular_stand", Vector3(0.4, 0.6, 0.4), Color(0.25, 0.25, 0.25), Vector3(5.05, 0, 0.35), FACE_N,
		"Look through", [{"clue": "balcony_view", "day_only": true}], "(too dark to see)")
	# Bath, toilet, closet
	_utility("bathtub", "Bathtub", "bathtub", Vector3(1.6, 0.55, 0.75), Color(0.92, 0.93, 0.95), Vector3(0.48, 0, 6.3), FACE_E)
	_loot("medicine_cabinet", "Medicine cabinet", "medicine_cabinet", Vector3(0.6, 1.0, 0.35), Color(0.9, 0.9, 0.9),
		Vector3(2.6, 0, 7.25), FACE_N, {"medkits": 1})
	_loot("toilet_shelf", "Shelf above the toilet", "toilet", Vector3(0.45, 0.8, 0.7), Color(0.95, 0.95, 0.97),
		Vector3(3.75, 0, 7.05), FACE_N, {"materials": 1, "water": 1})
	_loot("storage_closet", "Storage closet", "storage_closet", Vector3(1.2, 1.6, 0.5), Color(0.7, 0.6, 0.48),
		Vector3(5.25, 0, 7.15), FACE_N, {"materials": 4})
	_loot("emergency_bag", "Emergency bag", "emergency_bag", Vector3(0.45, 0.35, 0.3), Color(0.85, 0.4, 0.15),
		Vector3(4.85, 0, 6.2), FACE_N, {"food": 2, "water": 3}, "prep_pamphlet", "Open")
	_loot("toolbox", "Toolbox", "toolbox", Vector3(0.5, 0.25, 0.3), Color(0.75, 0.15, 0.12),
		Vector3(5.65, 0, 6.2), FACE_N, {"materials": 3}, "", "Open")
	# Genkan
	_loot("shoe_cabinet", "Shoe cabinet", "shoe_cabinet", Vector3(1.2, 1.0, 0.4), C_WOOD, Vector3(6.28, 0, 6.6), FACE_E,
		{"materials": 1})
	_clue("mail", "Mail slot", "mail_slot", Vector3(0.35, 1.0, 0.12), Color(0.55, 0.55, 0.58), Vector3(8.4, 0, 7.35), FACE_N,
		"Check", [{"clue": "building_notice"}, {"clue": "neighbor_note", "from": day2}], "(nothing new)")
	# Set dressing
	_deco("dining_chair", Vector3(0.45, 0.85, 0.45), C_WOOD, Vector3(7.5, 0, 1.2), FACE_W)
	_deco("washing_machine", Vector3(0.6, 0.85, 0.6), Color(0.88, 0.88, 0.9), Vector3(2.6, 0, 5.6), FACE_N)


# --- Lights & world --------------------------------------------------------------

func _build_lights() -> void:
	for p in [Vector3(2, 2.3, 2), Vector3(6.5, 2.3, 2), Vector3(4.5, 2.3, 4.6), Vector3(1.5, 2.3, 6.3), Vector3(7.5, 2.3, 6.3), Vector3(5.2, 2.3, 6.3)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 4.5
		l.light_energy = 0.55
		l.light_color = Color(1.0, 0.92, 0.8)
		add_child(l)
		room_lights.append(l)
	var corridor := OmniLight3D.new()
	corridor.position = Vector3(9.5, 2.4, 8.2)
	corridor.omni_range = 5.0
	corridor.light_energy = 0.6
	corridor.light_color = Color(0.8, 0.95, 1.0)
	add_child(corridor)
	room_lights.append(corridor)


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3150  # same Tokyo every run
	add_child(Props.box(Vector3(200, 0.2, 200), Color(0.18, 0.18, 0.2), Vector3(5, -9.2, 0)))  # street level
	# Street lamps far below, some flickering fires.
	for i in 40:
		var north := i % 2 == 0
		var x := rng.randf_range(-40, 50)
		var z := rng.randf_range(-70, -8) if north else rng.randf_range(16, 70)
		var w := rng.randf_range(5, 14)
		var d := rng.randf_range(5, 14)
		var h := rng.randf_range(10, 45)
		var tone := rng.randf_range(0.22, 0.4)
		var building := Props.box(Vector3(w, h, d), Color(tone, tone, tone * 1.08), Vector3(x, -9 + h * 0.5, z))
		add_child(building)
		# Lit windows: a few emissive strips on the face towards us.
		var face_z := z + d * 0.5 + 0.05 if north else z - d * 0.5 - 0.05
		for j in rng.randi_range(2, 6):
			var wy := -9 + rng.randf_range(2, h - 1)
			var strip := Props.box(Vector3(rng.randf_range(1, w * 0.8), 0.6, 0.05), Color(1.0, 0.85, 0.55), Vector3(x + rng.randf_range(-w * 0.3, w * 0.3), wy, face_z), 1.5)
			add_child(strip)
			window_lights.append(strip)
		if h > 35:
			add_child(Props.box(Vector3(0.4, 0.4, 0.4), Color(1, 0.1, 0.1), Vector3(x, -9 + h + 0.3, z), 3.0))
	for p in [Vector3(-18, -6, -30), Vector3(30, -5, -45), Vector3(10, -6, 35)]:
		var fire := OmniLight3D.new()
		fire.position = p
		fire.omni_range = 18
		fire.light_energy = 3.0
		fire.light_color = Color(1.0, 0.45, 0.15)
		fire.add_to_group("fire_light")
		add_child(fire)


func _on_world_changed() -> void:
	for l in room_lights:
		l.visible = Game.power_on
	if not Game.power_on:
		for s in window_lights:
			s.visible = randf() < 0.15  # a few buildings have generators
