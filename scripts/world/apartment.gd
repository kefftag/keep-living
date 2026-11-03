extends Node3D
## A typical Tokyo 1LDK (~46 m², 3rd floor) built on the 910 mm module
## (半間) that Japanese floor plans use, with 2.4 m ceilings.
##
## +X east, +Z south. Balcony on the -Z side (the sunny side), shared outdoor
## corridor on the +Z side. Interior spans x 0..6.37, z 0..7.28.
##
##  z=-1.5 ┌──────────── balcony (AC unit, laundry poles) ───────────┐
##         ║隔                                                   隔║  ← kick-through partitions
##  z=0    ├──[腰窓 window]────┬───────[掃き出し窓 sliding glass]──────┤
##         │ bed     wardrobe ↔引│ shelf   kotatsu        TV  desk │
##         │ 洋室 6畳          ↔戸│        LDK                     │
##         │ [closet]          │                                 │
##  z=3.64 ├───────────────────┴[door]┬───────── kitchen ───────────┤
##         │ washroom 洗面所 [door]  hall│ wall kitchen + fridge     │
##  z=5.46 ├──[bath door]──┬────────┤  ├────────┬──────────────────┤
##         │ unit bath     │ toilet [door]│closet│   alcove (MB)     │
##  z=6.37 │               │        ├─step─┴[door]┤                  │
##         │               │        │ genkan 玄関 │                  │
##  z=7.28 └──[barred win]─┴────────┴[front door]┘                  │
##         ═══════════════ outdoor corridor → stairwell ════════════════

const Props := preload("res://scripts/world/props.gd")
const LootContainer := preload("res://scripts/world/loot_container.gd")
const ClueSource := preload("res://scripts/world/clue_source.gd")
const Hazard := preload("res://scripts/world/furniture_hazard.gd")
const Utility := preload("res://scripts/world/utilities.gd")
const Barricade := preload("res://scripts/world/barricade_point.gd")
const Door := preload("res://scripts/world/door.gd")

const M := 0.91           # one module (半間)
const CEIL := 2.4
const EXT_T := 0.15
const INT_T := 0.1
const DOOR_TOP := 2.0
const GENKAN_Y := -0.15   # genkan and outdoor corridor sit one step down

const FACE_S := 0.0          # front faces +Z (south)
const FACE_N := PI           # front faces -Z (north)
const FACE_E := PI * 0.5     # front faces +X (east)
const FACE_W := -PI * 0.5    # front faces -X (west)

const C_WALLPAPER := Color(0.9, 0.89, 0.86)
const C_CONCRETE := Color(0.7, 0.7, 0.68)
const C_FLOORING := Color(0.56, 0.41, 0.28)
const C_CUSHION := Color(0.86, 0.85, 0.8)
const C_TILE := Color(0.36, 0.36, 0.37)
const C_BATH := Color(0.82, 0.84, 0.86)
const C_SKIRTING := Color(0.95, 0.95, 0.94)
const C_WOOD := Color(0.62, 0.45, 0.3)
const C_DOOR := Color(0.78, 0.7, 0.6)

var nav_region: NavigationRegion3D
var barricades := {}  # id -> barricade node
var doors := {}       # id -> door node
var room_lights: Array = []
var window_lights: Array = []
var _rebake_queued := false


func _ready() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.1
	nm.cell_height = 0.05
	nm.agent_radius = 0.2
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.2
	# Stop below the ceiling slab so its roof isn't treated as walkable.
	nm.filter_baking_aabb = AABB(Vector3(-1, -0.5, -2), Vector3(12, 2.0, 11.5))
	nav_region.navigation_mesh = nm
	add_child(nav_region)

	_build_floors()
	_build_walls()
	_build_doors()
	_build_barricades()
	_build_furniture()
	_build_outside()
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
	await get_tree().create_timer(0.7).timeout
	_rebake_queued = false
	if is_inside_tree():
		bake()


# --- Structure -----------------------------------------------------------------

func _solid(size: Vector3, center: Vector3, color: Color, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	body.add_child(Props.box_shape(size))
	body.add_child(Props.box(size, color))
	(parent if parent else nav_region).add_child(body)
	return body


## Floor slab from x0..x1, z0..z1 whose top is at `top`.
func _floor(x0: float, x1: float, z0: float, z1: float, top: float, color: Color) -> void:
	var t := 0.2
	_solid(Vector3(x1 - x0, t, z1 - z0), Vector3((x0 + x1) * 0.5, top - t * 0.5, (z0 + z1) * 0.5), color)


func _build_floors() -> void:
	# Rooms at 0, wet areas use cushion floor / FRP.
	_floor(0, 2.73, 0, 3.64, 0, C_FLOORING)          # bedroom
	_floor(2.73, 6.37, 0, 5.46, 0, C_FLOORING)       # LDK + kitchen
	_floor(2.73, 3.64, 3.64, 6.37, 0, C_FLOORING)    # hallway (overlaps LDK slab a little, fine)
	_floor(3.64, 4.55, 5.46, 6.37, 0, C_FLOORING)    # closet
	_floor(0, 2.73, 3.64, 5.46, 0, C_CUSHION)        # washroom
	_floor(0, 1.82, 5.46, 7.28, 0, C_BATH)           # unit bath
	_floor(1.82, 2.73, 5.46, 7.28, 0, C_CUSHION)     # toilet
	# One step down: genkan, alcove, outdoor corridor.
	_floor(2.73, 4.55, 6.37, 7.28, GENKAN_Y, C_TILE)
	_floor(4.55, 6.37, 5.46, 7.28, GENKAN_Y, Color(0.45, 0.46, 0.48))
	_floor(-0.5, 10.5, 7.28, 8.78, GENKAN_Y, Color(0.45, 0.46, 0.48))
	_floor(-0.1, 6.47, -1.5, 0, -0.02, Color(0.55, 0.55, 0.55))  # balcony
	# The 上がり框 step is drawn vertical, but collides as a short ramp so
	# feet and the navmesh can climb it.
	var ramp_len := 0.3
	var angle := atan2(-GENKAN_Y, ramp_len)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var cs := Props.box_shape(Vector3(1.82, 0.04, sqrt(ramp_len * ramp_len + GENKAN_Y * GENKAN_Y)))
	ramp.add_child(cs)
	ramp.rotation.x = angle
	ramp.position = Vector3(3.64, GENKAN_Y * 0.5 - 0.02 * cos(angle), 6.37 + ramp_len * 0.5)
	nav_region.add_child(ramp)
	add_child(Props.box(Vector3(1.82, 0.04, 0.06), C_WOOD, Vector3(3.64, -0.02, 6.4)))  # wooden step edge
	# Ceiling over everything (the floor above / the upper balcony and corridor).
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = 1
	ceiling.position = Vector3(5.0, CEIL + 0.1, 3.6)
	ceiling.add_child(Props.box_shape(Vector3(12, 0.2, 10.4)))
	ceiling.add_child(Props.box(Vector3(12, 0.2, 10.4), Color(0.93, 0.93, 0.92)))
	add_child(ceiling)  # not under the nav region


## Axis-aligned wall from a to b with door/window openings
## ([start, end, top] measured along the wall from a). Lintels fill above.
func _wall(a: Vector2, b: Vector2, openings: Array = [], thick: float = INT_T, color: Color = C_WALLPAPER,
		bottom: float = 0.0, height: float = CEIL, skirting: bool = true) -> void:
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var along_x: bool = abs(dir.x) > 0.5
	var pieces: Array = []  # [start, end, y0, y1]
	var cursor := 0.0
	var sorted := openings.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for o in sorted:
		if o[0] > cursor:
			pieces.append([cursor, o[0], bottom, bottom + height])
		pieces.append([o[0], o[1], o[2], bottom + height])  # lintel
		cursor = o[1]
	if cursor < length:
		pieces.append([cursor, length, bottom, bottom + height])
	for p in pieces:
		var seg: float = p[1] - p[0]
		var h: float = p[3] - p[2]
		if seg <= 0.001 or h <= 0.001:
			continue
		var is_lintel: bool = p[2] > bottom + 0.01
		var ext := 0.0 if is_lintel else thick * 0.5  # overlap at corners
		var mid: Vector2 = a + dir * ((p[0] + p[1]) * 0.5)
		var sz: Vector3 = Vector3(seg + ext * 2.0, h, thick) if along_x else Vector3(thick, h, seg + ext * 2.0)
		_solid(sz, Vector3(mid.x, (p[2] + p[3]) * 0.5, mid.y), color)
		if skirting and not is_lintel:
			var sk: Vector3 = Vector3(seg, 0.06, thick + 0.02) if along_x else Vector3(thick + 0.02, 0.06, seg)
			add_child(Props.box(sk, C_SKIRTING, Vector3(mid.x, bottom + 0.03, mid.y)))


func _build_walls() -> void:
	# Exterior (RC)
	_wall(Vector2(0, 0), Vector2(6.37, 0), [[0.45, 2.0, DOOR_TOP], [3.3, 5.8, 2.05]], EXT_T)       # balcony side
	_wall(Vector2(0, 0), Vector2(0, 7.28), [], EXT_T)                                                # west
	_wall(Vector2(6.37, 0), Vector2(6.37, 5.46), [], EXT_T)                                          # east
	_wall(Vector2(4.55, 5.46), Vector2(6.37, 5.46), [], EXT_T)                                       # kitchen back / alcove
	_wall(Vector2(4.55, 5.46), Vector2(4.55, 7.28), [], EXT_T, C_WALLPAPER, GENKAN_Y, CEIL - GENKAN_Y) # closet+genkan / alcove
	_wall(Vector2(0, 7.28), Vector2(2.73, 7.28), [[0.5, 1.2, 1.9]], EXT_T)                          # bath+toilet / corridor
	_wall(Vector2(2.73, 7.28), Vector2(4.55, 7.28), [[0.12, 0.97, DOOR_TOP]], EXT_T, C_WALLPAPER, GENKAN_Y, CEIL - GENKAN_Y)
	# Interior partitions
	_wall(Vector2(2.73, 0), Vector2(2.73, 3.64), [[0.9, 2.72, DOOR_TOP]])        # bedroom | LDK (引き戸)
	_wall(Vector2(0, 3.64), Vector2(3.64, 3.64), [[2.83, 3.54, DOOR_TOP]])       # bedroom | washroom, hall → LDK door
	_wall(Vector2(2.73, 3.64), Vector2(2.73, 7.28), [[0.16, 0.86, DOOR_TOP], [1.96, 2.66, DOOR_TOP]])  # washroom & toilet | hall
	_wall(Vector2(0, 5.46), Vector2(2.73, 5.46), [[0.8, 1.5, DOOR_TOP]])         # washroom | bath & toilet
	_wall(Vector2(1.82, 5.46), Vector2(1.82, 7.28))                              # bath | toilet
	_wall(Vector2(3.64, 3.64), Vector2(3.64, 6.37))                              # hall | kitchen & closet
	_wall(Vector2(3.64, 5.46), Vector2(4.55, 5.46))                              # kitchen | closet
	_wall(Vector2(3.64, 6.37), Vector2(4.55, 6.37), [[0.11, 0.81, DOOR_TOP]])    # closet | genkan
	# Outside: balcony railing + partitions, corridor railing, neighbours.
	var rail := Color(0.35, 0.36, 0.38)
	_wall(Vector2(-0.1, -1.5), Vector2(6.47, -1.5), [], 0.08, rail, 0.0, 1.1, false)
	_wall(Vector2(0, -1.5), Vector2(0, 0), [], 0.04, Color(0.86, 0.86, 0.82), 0.0, 1.9, false)
	_wall(Vector2(6.37, -1.5), Vector2(6.37, 0), [], 0.04, Color(0.86, 0.86, 0.82), 0.0, 1.9, false)
	for x in [0.03, 6.34]:
		var sign_l := Props.label("非常の際は、ここを破って\n隣戸へ避難できます。", 1.45, Color(0.15, 0.15, 0.15))
		sign_l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sign_l.no_depth_test = false
		sign_l.fixed_size = false
		sign_l.pixel_size = 0.0012
		sign_l.outline_size = 0
		sign_l.position = Vector3(x + (0.03 if x < 1 else -0.03), 1.45, -0.75)
		sign_l.rotation.y = FACE_E if x < 1 else FACE_W
		add_child(sign_l)
	_wall(Vector2(-0.5, 8.78), Vector2(10.5, 8.78), [], 0.08, rail, GENKAN_Y, 1.1, false)
	_wall(Vector2(-0.5, 7.28), Vector2(0, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(-0.5, 7.28), Vector2(-0.5, 8.78), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(6.37, 5.46), Vector2(6.37, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(6.37, 7.28), Vector2(10.5, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	# Neighbour's door (304) and our meter box (MB) in the alcove.
	add_child(Props.box(Vector3(0.85, 1.95, 0.05), Color(0.36, 0.33, 0.3), Vector3(8.2, GENKAN_Y + 0.98, 7.2)))
	add_child(Props.box(Vector3(0.04, 1.8, 0.7), Color(0.6, 0.6, 0.58), Vector3(6.29, GENKAN_Y + 1.0, 6.4)))
	var mb := Props.label("MB", GENKAN_Y + 1.6, Color(0.2, 0.2, 0.2))
	mb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	mb.no_depth_test = false
	mb.position = Vector3(6.26, GENKAN_Y + 1.6, 6.4)
	mb.rotation.y = FACE_W
	add_child(mb)


# --- Doors ---------------------------------------------------------------------

func _door(id: String, label: String, center: Vector3, facing: float, width: float, kind: String,
		opts: Dictionary = {}) -> void:
	var d = Door.new()
	d.name = id
	d.display_name = label
	d.kind = kind
	d.width = width
	d.height = DOOR_TOP - center.y
	d.color = opts.get("color", C_DOOR)
	d.glass = opts.get("glass", false)
	d.swing = opts.get("swing", 1.0)
	d.hinge_left = opts.get("hinge_left", true)
	d.slide_sign = opts.get("slide_sign", -1.0)
	d.is_open = false
	d.position = center
	d.rotation.y = facing
	add_child(d)
	if opts.get("open", false):
		d.set_open(true)
	doors[id] = d


func _build_doors() -> void:
	# Bedroom ↔ LDK: two sliding panels that slide into wall pockets.
	_door("bedroom_slide_n", "Sliding door", Vector3(2.73, 0, 1.355), FACE_E, 0.91, "sliding", {"slide_sign": 1.0, "open": true})
	_door("bedroom_slide_s", "Sliding door", Vector3(2.73, 0, 2.265), FACE_E, 0.91, "sliding", {"slide_sign": -1.0})
	_door("ldk_door", "Living room door", Vector3(3.185, 0, 3.64), FACE_S, 0.71, "hinged", {"glass": true, "swing": 1.0, "open": true})
	_door("washroom_door", "Washroom door", Vector3(2.73, 0, 4.15), FACE_E, 0.7, "hinged", {"swing": 1.0, "hinge_left": false})
	_door("toilet_door", "Toilet door", Vector3(2.73, 0, 5.95), FACE_E, 0.7, "hinged", {"swing": -1.0})
	_door("bath_door", "Bathroom door", Vector3(1.15, 0, 5.46), FACE_S, 0.7, "hinged", {"swing": -1.0, "color": Color(0.88, 0.9, 0.92), "glass": true})
	_door("closet_door", "Closet door", Vector3(4.1, 0, 6.37), FACE_S, 0.7, "hinged", {"swing": -1.0})


# --- Entrances ---------------------------------------------------------------

func _build_barricades() -> void:
	var balcony_spawns := [Vector3(0.45, 0, -0.75), Vector3(5.92, 0, -0.75)]
	var stair_spawns := [Vector3(10.0, GENKAN_Y, 8.0)]
	_add_barricade("bedroom_window", "Bedroom window", Vector3(1.225, 0, 0), FACE_N, 1.55, 100.0, 0.9, DOOR_TOP, "window", balcony_spawns)
	_add_barricade("balcony_door", "Balcony door", Vector3(4.55, 0, 0), FACE_N, 2.5, 120.0, 0.0, 2.05, "balcony", balcony_spawns)
	_add_barricade("front_door", "Front door", Vector3(3.275, GENKAN_Y, 7.28), FACE_S, 0.85, 300.0, 0.0, DOOR_TOP - GENKAN_Y, "door", stair_spawns)
	_add_barricade("bath_window", "Bathroom window", Vector3(0.85, 0, 7.28), FACE_S, 0.7, 200.0, 1.25, 1.9, "barred", stair_spawns)


func _add_barricade(id: String, label: String, pos: Vector3, facing: float, width: float, hp: float,
		sill: float, top: float, style: String, spawns: Array) -> void:
	var b = Barricade.new()
	b.name = id
	b.point_id = id
	b.display_name = label
	b.size = Vector3(width, top, 0.2)
	b.base_hp = hp
	b.sill = sill
	b.opening_height = top
	b.style = style
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


## Non-interactive dressing. Wall-mounted pieces (collide=false) don't block.
func _deco(model: String, size: Vector3, color: Color, pos: Vector3, facing: float, collide := true) -> void:
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.add_child(Props.box_shape(size, Vector3(0, size.y * 0.5, 0)))
		holder = body
	else:
		holder = Node3D.new()
	holder.add_child(Props.visual(model, size, color))
	holder.position = pos
	holder.rotation.y = facing
	(nav_region if collide else self).add_child(holder)


func _build_furniture() -> void:
	var day2 := 1440 + 7 * 60
	var g := GENKAN_Y
	# --- Bedroom (洋室 6畳) ---
	_utility("bed", "Bed", "bed", Vector3(1.2, 0.45, 1.95), Color(0.85, 0.85, 0.92), Vector3(0.69, 0, 1.13), FACE_S)
	_hazard("wardrobe", "Wardrobe", "wardrobe", Vector3(0.75, 1.8, 0.55), C_WOOD, Vector3(2.405, 0, 0.5), FACE_W)
	_clue("phone", "Phone", "side_table", Vector3(0.4, 0.45, 0.4), Color(0.75, 0.6, 0.45), Vector3(1.55, 0, 0.32), FACE_S,
		"Check", [{"clue": "jalert"}], "(no new messages)")
	_loot("bedroom_closet", "Closet", "closet_builtin", Vector3(1.8, 2.0, 0.55), Color(0.93, 0.92, 0.88),
		Vector3(0.97, 0, 3.315), FACE_N, {"medkits": 1, "materials": 1})
	# --- LDK ---
	_hazard("bookshelf", "Bookshelf", "bookshelf", Vector3(0.8, 1.8, 0.3), Color(0.5, 0.36, 0.25), Vector3(2.93, 0, 0.48), FACE_E)
	_clue("binoculars", "Binoculars", "binocular_stand", Vector3(0.4, 0.6, 0.4), Color(0.25, 0.25, 0.25), Vector3(5.45, 0, 0.35), FACE_N,
		"Look through", [{"clue": "balcony_view", "day_only": true}], "(too dark to see)")
	_clue("laptop", "Laptop", "desk", Vector3(0.85, 0.72, 0.5), Color(0.5, 0.5, 0.55), Vector3(6.045, 0, 0.6), FACE_W,
		"Use", [{"clue": "forum_rescue", "from": day2, "needs_power": true}], "(the forums won't load yet)")
	_clue("tv", "TV", "tv_stand", Vector3(1.2, 0.45, 0.4), Color(0.15, 0.15, 0.17), Vector3(6.095, 0, 2.0), FACE_W,
		"Watch", [{"clue": "tv_shibuya", "needs_power": true}], "(colour bars)")
	_clue("radio", "Hand-crank radio", "kotatsu", Vector3(0.8, 0.4, 0.8), Color(0.6, 0.42, 0.3), Vector3(4.6, 0, 1.9), FACE_S,
		"Listen to", [{"clue": "radio_sound", "night_only": true}], "(static... maybe at night)")
	_deco("dining_table", Vector3(0.75, 0.7, 0.75), C_WOOD, Vector3(4.2, 0, 3.05), FACE_S)
	_deco("dining_chair", Vector3(0.42, 0.85, 0.42), C_WOOD, Vector3(4.2, 0, 2.5), FACE_S)
	_deco("ac_indoor", Vector3(0.8, 0.28, 0.25), Color(0.95, 0.95, 0.95), Vector3(4.55, 2.08, 0.2), FACE_S, false)
	_deco("curtain", Vector3(0.35, 2.0, 0.08), Color(0.55, 0.6, 0.55), Vector3(3.12, 0, 0.13), FACE_S, false)
	_deco("curtain", Vector3(0.35, 2.0, 0.08), Color(0.55, 0.6, 0.55), Vector3(0.28, 0, 0.13), FACE_S, false)
	# --- Kitchen (壁付けキッチン) ---
	_loot("kitchen_cabinets", "Kitchen cabinets", "kitchen_cabinet", Vector3(0.6, 0.85, 0.65), Color(0.85, 0.84, 0.8),
		Vector3(4.0, 0, 5.06), FACE_N, {"food": 3})
	_utility("tap", "Kitchen sink", "kitchen_sink", Vector3(0.7, 0.85, 0.65), Color(0.8, 0.8, 0.8), Vector3(4.65, 0, 5.06), FACE_N)
	_utility("stove", "Gas stove", "gas_stove", Vector3(0.65, 0.85, 0.65), Color(0.3, 0.3, 0.32), Vector3(5.325, 0, 5.06), FACE_N)
	var fridge = _loot("fridge", "Fridge", "fridge", Vector3(0.6, 1.6, 0.62), Color(0.9, 0.9, 0.92), Vector3(6.0, 0, 5.07), FACE_N,
		{"food": 2, "water": 2})
	fridge.spoils_without_power = true
	_deco("range_hood", Vector3(0.65, 0.45, 0.5), Color(0.85, 0.85, 0.85), Vector3(5.325, 1.85, 5.13), FACE_N, false)
	_deco("wall_cabinet", Vector3(1.3, 0.6, 0.35), Color(0.85, 0.84, 0.8), Vector3(4.35, 1.6, 5.2), FACE_N, false)
	# --- Washroom (洗面脱衣所) & unit bath ---
	_loot("vanity", "Washbasin cabinet", "vanity", Vector3(0.75, 1.8, 0.5), Color(0.92, 0.92, 0.92),
		Vector3(0.325, 0, 4.1), FACE_E, {"medkits": 1})
	_deco("washing_machine", Vector3(0.6, 1.0, 0.6), Color(0.92, 0.92, 0.94), Vector3(0.375, 0, 4.95), FACE_E)
	_utility("bathtub", "Bathtub", "bathtub", Vector3(1.7, 0.55, 0.7), Color(0.94, 0.95, 0.97), Vector3(0.91, 0, 6.855), FACE_N)
	# --- Toilet ---
	_loot("toilet_shelf", "Shelf above the toilet", "toilet", Vector3(0.45, 0.8, 0.7), Color(0.95, 0.95, 0.97),
		Vector3(2.275, 0, 6.855), FACE_N, {"materials": 1, "water": 1})
	# --- Closet (物入れ, off the genkan) ---
	_loot("storage_closet", "Storage shelves", "storage_shelf", Vector3(0.8, 1.8, 0.35), Color(0.7, 0.6, 0.48),
		Vector3(4.095, 0, 5.71), FACE_S, {"materials": 4})
	_loot("emergency_bag", "Emergency bag", "emergency_bag", Vector3(0.45, 0.35, 0.3), Color(0.85, 0.4, 0.15),
		Vector3(3.9, 0, 6.1), FACE_S, {"food": 2, "water": 3}, "prep_pamphlet", "Open")
	_loot("toolbox", "Toolbox", "toolbox", Vector3(0.4, 0.22, 0.25), Color(0.75, 0.15, 0.12),
		Vector3(4.33, 0, 6.12), FACE_S, {"materials": 3}, "", "Open")
	# --- Genkan (玄関) ---
	_loot("shoe_cabinet", "Shoe cabinet", "shoe_cabinet", Vector3(0.75, 0.9, 0.35), C_WOOD, Vector3(4.1, g, 7.03), FACE_N,
		{"materials": 1})
	_clue("mail", "Mail on the floor", "mail_pile", Vector3(0.3, 0.04, 0.22), Color(0.92, 0.9, 0.85), Vector3(3.0, g, 6.95), FACE_N,
		"Pick up", [{"clue": "building_notice"}, {"clue": "neighbor_note", "from": day2}], "(nothing new)")
	_deco("intercom", Vector3(0.18, 0.13, 0.04), Color(0.95, 0.95, 0.95), Vector3(3.75, 1.35, 3.57), FACE_N, false)
	_deco("breaker_panel", Vector3(0.35, 0.3, 0.1), Color(0.95, 0.95, 0.93), Vector3(2.79, 1.85, 5.05), FACE_E, false)


func _build_outside() -> void:
	_deco("ac_outdoor", Vector3(0.7, 0.55, 0.28), Color(0.9, 0.9, 0.88), Vector3(5.55, 0, -1.3), FACE_N)
	for x in [0.6, 5.0]:  # laundry-pole hangers on the ceiling
		add_child(Props.box(Vector3(0.03, 0.35, 0.03), Color(0.7, 0.7, 0.7), Vector3(x, CEIL - 0.18, -0.9)))
	add_child(Props.box(Vector3(5.0, 0.03, 0.03), Color(0.75, 0.75, 0.78), Vector3(2.8, CEIL - 0.35, -0.9)))


# --- Lights & world --------------------------------------------------------------

func _ceiling_light(p: Vector3, energy: float = 0.8, rng: float = 4.0) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.omni_range = rng
	l.light_energy = energy
	l.light_color = Color(1.0, 0.95, 0.88)
	add_child(l)
	room_lights.append(l)
	var fixture := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.25
	cyl.height = 0.08
	fixture.mesh = cyl
	fixture.material_override = Props.mat(Color(1.0, 0.98, 0.93), 0.8)
	fixture.position = Vector3(p.x, CEIL - 0.04, p.z)
	add_child(fixture)
	room_lights.append(fixture)


func _build_lights() -> void:
	_ceiling_light(Vector3(1.36, 2.2, 1.82))         # bedroom
	_ceiling_light(Vector3(4.55, 2.2, 1.82), 1.0, 5.0)  # living
	_ceiling_light(Vector3(5.0, 2.2, 4.4))           # kitchen
	_ceiling_light(Vector3(1.36, 2.2, 4.55), 0.6)    # washroom
	_ceiling_light(Vector3(0.91, 2.2, 6.37), 0.5)    # bath
	_ceiling_light(Vector3(2.27, 2.2, 6.37), 0.4)    # toilet
	_ceiling_light(Vector3(3.18, 2.2, 5.0), 0.5)     # hallway
	_ceiling_light(Vector3(3.64, 2.2, 6.82), 0.5)    # genkan
	var corridor := OmniLight3D.new()
	corridor.position = Vector3(5.5, 2.25, 8.0)
	corridor.omni_range = 6.0
	corridor.light_energy = 0.7
	corridor.light_color = Color(0.85, 0.95, 1.0)
	add_child(corridor)
	room_lights.append(corridor)


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3150  # same Tokyo every run
	add_child(Props.box(Vector3(220, 0.2, 220), Color(0.2, 0.2, 0.22), Vector3(5, -9.3, 0)))  # street level
	# Mid-rise residential blocks close by, taller ones further out.
	for i in 48:
		var north := i % 2 == 0
		var near := i < 16
		var x := rng.randf_range(-35, 45)
		var z := (rng.randf_range(-30, -12) if near else rng.randf_range(-90, -30)) if north \
			else (rng.randf_range(18, 34) if near else rng.randf_range(34, 90))
		var w := rng.randf_range(8, 18)
		var d := rng.randf_range(6, 12)
		var h := rng.randf_range(9, 20) if near else rng.randf_range(15, 60)
		var tone := rng.randf_range(0.5, 0.72) if near else rng.randf_range(0.3, 0.45)
		add_child(Props.box(Vector3(w, h, d), Color(tone, tone * 0.98, tone * 0.95), Vector3(x, -9.2 + h * 0.5, z)))
		var face_z := z + d * 0.5 + 0.05 if north else z - d * 0.5 - 0.05
		# Rows of windows / balconies.
		var floors := int(h / 2.9)
		for f in floors:
			if rng.randf() < 0.55:
				var wy := -9.2 + 1.5 + f * 2.9
				var strip := Props.box(Vector3(rng.randf_range(1.0, w * 0.5), 1.0, 0.05), Color(1.0, 0.86, 0.6),
					Vector3(x + rng.randf_range(-w * 0.25, w * 0.25), wy, face_z), 1.2)
				add_child(strip)
				window_lights.append(strip)
		if h > 45:
			add_child(Props.box(Vector3(0.4, 0.4, 0.4), Color(1, 0.1, 0.1), Vector3(x, -9.2 + h + 0.3, z), 3.0))
	for p in [Vector3(-18, -6, -40), Vector3(30, -5, -55), Vector3(10, -6, 45)]:
		var fire := OmniLight3D.new()
		fire.position = p
		fire.omni_range = 20
		fire.light_energy = 3.0
		fire.light_color = Color(1.0, 0.45, 0.15)
		add_child(fire)


func _on_world_changed() -> void:
	for l in room_lights:
		l.visible = Game.power_on
	if not Game.power_on:
		for s in window_lights:
			s.visible = randf() < 0.12  # a few buildings have generators
