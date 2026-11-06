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
const Decor := preload("res://scripts/world/decor.gd")

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
const C_DOOR := Color(1.0, 0.95, 0.88)
const C_PARTITION := Color(0.86, 0.86, 0.82)  # balcony 隔て板

var nav_region: NavigationRegion3D
var barricades := {}  # id -> barricade node
var doors := {}       # id -> door node
var room_lights: Array = []
var window_lights: Array = []
var _rebake_queued := false
var _probes: Array = []


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
	add_child(Decor.new())  # lived-in clutter, no collision
	_build_outside()
	_build_lights()
	_build_skyline()
	_build_reflection_probes()
	Game.nav_dirty.connect(_queue_rebake)
	Game.world_changed.connect(_on_world_changed)
	Game.phase_changed.connect(_refresh_city_windows)
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

func _solid(size: Vector3, center: Vector3, color: Color, parent: Node = null, surf: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	body.add_child(Props.box_shape(size))
	body.add_child(Props.sbox(size, surf, Vector3.ZERO, color) if surf != "" else Props.box(size, color))
	(parent if parent else nav_region).add_child(body)
	return body


## Floor slab from x0..x1, z0..z1 whose top is at `top`.
func _floor(x0: float, x1: float, z0: float, z1: float, top: float, surf: String, tint: Color = Color.WHITE) -> void:
	var t := 0.2
	_solid(Vector3(x1 - x0, t, z1 - z0), Vector3((x0 + x1) * 0.5, top - t * 0.5, (z0 + z1) * 0.5), tint, null, surf)


func _build_floors() -> void:
	# Rooms at 0, wet areas use cushion floor / FRP.
	_floor(0, 2.73, 0, 3.64, 0, "floor_wood")        # bedroom
	_floor(2.73, 6.37, 0, 5.46, 0, "floor_wood")     # LDK + kitchen
	_floor(2.73, 3.64, 3.64, 6.37, 0, "floor_wood")  # hallway (overlaps LDK slab a little, fine)
	_floor(3.64, 4.55, 5.46, 6.37, 0, "floor_wood")  # closet
	_floor(0, 2.73, 3.64, 5.46, 0, "floor_cushion")   # washroom
	_floor(0, 1.82, 5.46, 7.28, 0, "floor_bath")      # unit bath
	_floor(1.82, 2.73, 5.46, 7.28, 0, "floor_cushion")  # toilet
	# One step down: genkan, alcove, outdoor corridor.
	_floor(2.73, 4.55, 6.37, 7.28, GENKAN_Y, "floor_genkan")
	_floor(4.55, 6.37, 5.46, 7.28, GENKAN_Y, "concrete_floor")
	_floor(-0.5, 10.5, 7.28, 8.78, GENKAN_Y, "concrete_floor")
	_floor(-0.1, 6.47, -1.5, 0, -0.02, "balcony_floor")  # balcony
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
	# 上がり框: a solid-wood nosing on the step, its riser faced in the same wood.
	add_child(Props.sbox(Vector3(1.82, 0.025, 0.1), "wood", Vector3(3.64, -0.0105, 6.335)))
	add_child(Props.sbox(Vector3(1.82, 0.152, 0.022), "wood", Vector3(3.64, -0.074, 6.381)))
	# Ceiling over everything (the floor above / the upper balcony and corridor).
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = 1
	ceiling.position = Vector3(5.0, CEIL + 0.1, 3.6)
	ceiling.add_child(Props.box_shape(Vector3(12, 0.2, 10.4)))
	ceiling.add_child(Props.sbox(Vector3(12, 0.2, 10.4), "wallpaper", Vector3.ZERO, Color(1.0, 1.0, 1.0)))
	add_child(ceiling)  # not under the nav region
	# Outdoors the "ceiling" is the bare concrete slab of the balcony / corridor above.
	add_child(Props.sbox(Vector3(6.6, 0.01, 1.52), "concrete_wall", Vector3(3.18, CEIL - 0.004, -0.75), Color(0.95, 0.95, 0.93)))
	add_child(Props.sbox(Vector3(11.1, 0.01, 1.52), "concrete_wall", Vector3(5.0, CEIL - 0.004, 8.03), Color(0.95, 0.95, 0.93)))
	add_child(Props.sbox(Vector3(1.82, 0.01, 1.82), "concrete_wall", Vector3(5.46, CEIL - 0.004, 6.37), Color(0.95, 0.95, 0.93)))
	# Unit bath: its own satin panel ceiling.
	add_child(Props.sbox(Vector3(1.75, 0.01, 1.7), "bath_panel", Vector3(0.92, CEIL - 0.006, 6.36)))


## Axis-aligned wall from a to b with door/window openings
## ([start, end, top] measured along the wall from a). Lintels fill above.
func _wall(a: Vector2, b: Vector2, openings: Array = [], thick: float = INT_T, color: Color = C_WALLPAPER,
		bottom: float = 0.0, height: float = CEIL, skirting: bool = true, outer: float = 0.0) -> void:
	# outer: which side is outdoors (+1/-1 along the wall's +Z/+X normal) for a concrete skin.
	var surf := "wallpaper" if color == C_WALLPAPER else ("concrete_wall" if color == C_CONCRETE else "")
	if color == C_PARTITION:
		surf = "board_cream"
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
		var center := Vector3(mid.x, (p[2] + p[3]) * 0.5, mid.y)
		_solid(sz, center, Color.WHITE if surf != "" else color, null, surf)
		if outer != 0.0:
			var n: Vector3 = Vector3(0, 0, outer) if along_x else Vector3(outer, 0, 0)
			var skin: Vector3 = Vector3(sz.x, sz.y, 0.012) if along_x else Vector3(0.012, sz.y, sz.z)
			add_child(Props.sbox(skin, "concrete_wall", center + n * (thick * 0.5 + 0.006), Color(0.92, 0.91, 0.88)))
		if skirting and not is_lintel:
			# ソフト巾木: 60 mm vinyl skirting, 8 mm proud. Exterior walls only get it inside.
			var faces: Array = [-1.0, 1.0] if outer == 0.0 else [-outer]
			for f in faces:
				var sk: Vector3 = Vector3(seg + (ext * 2.0 if outer != 0.0 else 0.0), 0.06, 0.008) if along_x \
					else Vector3(0.008, 0.06, seg + (ext * 2.0 if outer != 0.0 else 0.0))
				var off: Vector3 = (Vector3(0, 0, f) if along_x else Vector3(f, 0, 0)) * (thick * 0.5 + 0.004)
				add_child(Props.fbox(sk, "vinyl_white", Vector3(mid.x, bottom + 0.03, mid.y) + off))
	if skirting and outer == 0.0:
		for o in sorted:
			_casing(a, dir, along_x, o, thick, bottom)


## 額縁/ケーシング: the door trim around an interior opening, on both faces,
## plus the jamb lining across the wall's thickness.
func _casing(a: Vector2, dir: Vector2, along_x: bool, o: Array, thick: float, bottom: float) -> void:
	var trim := Props.surface("wood_light", C_DOOR)
	var w := 0.05      # trim width
	var proud := 0.012
	var top: float = o[2]
	var h: float = top - bottom
	var s0: float = o[0]
	var s1: float = o[1]
	var pieces: Array = [  # [along-wall centre, along-wall size, y centre, height]
		[s0 - w * 0.5, w, bottom + (h + w) * 0.5, h + w],
		[s1 + w * 0.5, w, bottom + (h + w) * 0.5, h + w],
		[(s0 + s1) * 0.5, s1 - s0, top + w * 0.5, w],
	]
	for f in [-1.0, 1.0]:
		for p in pieces:
			var c2: Vector2 = a + dir * float(p[0])
			var off: float = f * (thick * 0.5 + proud * 0.5)
			var sz: Vector3 = Vector3(p[1], p[3], proud) if along_x else Vector3(proud, p[3], p[1])
			var pos := Vector3(c2.x, p[2], c2.y) + (Vector3(0, 0, off) if along_x else Vector3(off, 0, 0))
			var mi := Props.box(sz, Color.WHITE, pos)
			mi.material_override = trim
			add_child(mi)
	if s1 - s0 > 1.2:
		return  # the bedroom's sliding doors run into the wall pockets: no lining
	var lin := 0.006
	for p in [[s0 + lin * 0.5, lin, bottom + h * 0.5, h], [s1 - lin * 0.5, lin, bottom + h * 0.5, h], [(s0 + s1) * 0.5, s1 - s0, top - lin * 0.5, lin]]:
		var c2: Vector2 = a + dir * float(p[0])
		var sz: Vector3 = Vector3(p[1], p[3], thick + 0.002) if along_x else Vector3(thick + 0.002, p[3], p[1])
		if p[3] == lin:
			sz = Vector3(p[1], lin, thick + 0.002) if along_x else Vector3(thick + 0.002, lin, p[1])
		var mi := Props.box(sz, Color.WHITE, Vector3(c2.x, p[2], c2.y))
		mi.material_override = trim
		add_child(mi)


## Aluminium handrail capping a parapet: a flat rail on short posts.
func _handrail(center: Vector3, length: float, along_x: bool) -> void:
	var rail: Vector3 = Vector3(length, 0.035, 0.07) if along_x else Vector3(0.07, 0.035, length)
	add_child(Props.fbox(rail, "aluminium", center + Vector3(0, 0.1, 0)))
	var n := int(length / 1.2) + 1
	for i in n + 1:
		var t := -length * 0.5 + 0.05 + (length - 0.1) * float(i) / float(n)
		var p: Vector3 = center + (Vector3(t, 0.045, 0) if along_x else Vector3(0, 0.045, t))
		add_child(Props.fbox(Vector3(0.03, 0.09, 0.03), "aluminium", p))


## A thin non-colliding lining on a wall face, from a to b (on the face plane),
## with openings [start, end, top, sill] measured from a.
func _lining(a: Vector2, b: Vector2, openings: Array, surf: String, y0: float, y1: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var along_x: bool = abs(dir.x) > 0.5
	var t := 0.004
	var rects: Array = []  # [s0, s1, ya, yb]
	var cursor := 0.0
	for o in openings:
		rects.append([cursor, o[0], y0, y1])
		rects.append([o[0], o[1], o[2], y1])
		if o.size() > 3:
			rects.append([o[0], o[1], y0, o[3]])
		cursor = o[1]
	rects.append([cursor, length, y0, y1])
	for r in rects:
		var seg: float = r[1] - r[0]
		var h: float = r[3] - r[2]
		if seg <= 0.001 or h <= 0.001:
			continue
		var mid: Vector2 = a + dir * ((r[0] + r[1]) * 0.5)
		var sz: Vector3 = Vector3(seg, h, t) if along_x else Vector3(t, h, seg)
		add_child(Props.sbox(sz, surf, Vector3(mid.x, (r[2] + r[3]) * 0.5, mid.y)))


func _build_walls() -> void:
	# Exterior (RC)
	_wall(Vector2(0, 0), Vector2(6.37, 0), [[0.45, 2.0, DOOR_TOP], [3.3, 5.8, 2.05]], EXT_T, C_WALLPAPER, 0.0, CEIL, true, -1.0)  # balcony side
	_wall(Vector2(0, 0), Vector2(0, 7.28), [], EXT_T, C_WALLPAPER, 0.0, CEIL, true, -1.0)  # west
	_wall(Vector2(6.37, 0), Vector2(6.37, 5.46), [], EXT_T, C_WALLPAPER, 0.0, CEIL, true, 1.0)  # east
	_wall(Vector2(4.55, 5.46), Vector2(6.37, 5.46), [], EXT_T, C_WALLPAPER, 0.0, CEIL, true, 1.0)  # kitchen back / alcove
	_wall(Vector2(4.55, 5.46), Vector2(4.55, 7.28), [], EXT_T, C_WALLPAPER, GENKAN_Y, CEIL - GENKAN_Y, true, 1.0)  # closet+genkan / alcove
	_wall(Vector2(0, 7.28), Vector2(2.73, 7.28), [[0.5, 1.2, 1.9]], EXT_T, C_WALLPAPER, 0.0, CEIL, true, 1.0)  # bath+toilet / corridor
	_wall(Vector2(2.73, 7.28), Vector2(4.55, 7.28), [[0.12, 0.97, DOOR_TOP]], EXT_T, C_WALLPAPER, GENKAN_Y, CEIL - GENKAN_Y, true, 1.0)
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
	# Balcony: RC parapet (腰壁) with an aluminium handrail; 隔て板 partitions in aluminium frames.
	_wall(Vector2(-0.1, -1.5), Vector2(6.47, -1.5), [], 0.08, C_CONCRETE, 0.0, 1.1, false)
	_handrail(Vector3(3.185, 1.1, -1.5), 6.57, true)
	_wall(Vector2(0, -1.5), Vector2(0, 0), [], 0.04, C_PARTITION, 0.0, 1.9, false)
	_wall(Vector2(6.37, -1.5), Vector2(6.37, 0), [], 0.04, C_PARTITION, 0.0, 1.9, false)
	for px in [0.0, 6.37]:
		for fz in [-1.5 + 0.04, -0.03]:
			add_child(Props.fbox(Vector3(0.05, 1.92, 0.05), "aluminium", Vector3(px, 0.96, fz)))
		add_child(Props.fbox(Vector3(0.05, 0.05, 1.5), "aluminium", Vector3(px, 1.905, -0.75)))
		add_child(Props.fbox(Vector3(0.05, 0.05, 1.5), "aluminium", Vector3(px, 0.08, -0.75)))
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
	_wall(Vector2(-0.5, 8.78), Vector2(10.5, 8.78), [], 0.08, C_CONCRETE, GENKAN_Y, 1.1, false)
	_handrail(Vector3(5.0, GENKAN_Y + 1.1, 8.78), 11.0, true)
	_wall(Vector2(-0.5, 7.28), Vector2(0, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(-0.5, 7.28), Vector2(-0.5, 8.78), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(6.37, 5.46), Vector2(6.37, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	_wall(Vector2(6.37, 7.28), Vector2(10.5, 7.28), [], EXT_T, C_CONCRETE, GENKAN_Y, CEIL - GENKAN_Y, false)
	# Neighbour's door (304) and our meter box (MB) in the alcove.
	add_child(Props.fbox(Vector3(0.95, 2.05, 0.04), "steel_painted", Vector3(8.2, GENKAN_Y + 1.025, 7.21), Color(0.08, 0.075, 0.07)))
	add_child(Props.fbox(Vector3(0.85, 1.95, 0.05), "steel_painted", Vector3(8.2, GENKAN_Y + 0.98, 7.2)))
	add_child(Props.fbox(Vector3(0.14, 0.025, 0.04), "stainless", Vector3(8.55, GENKAN_Y + 1.0, 7.17)))
	add_child(Props.fbox(Vector3(0.28, 0.05, 0.01), "aluminium_dark", Vector3(8.2, GENKAN_Y + 0.75, 7.17)))
	add_child(Props.fbox(Vector3(0.04, 1.8, 0.7), "steel_painted_light", Vector3(6.29, GENKAN_Y + 1.0, 6.4)))
	add_child(Props.fbox(Vector3(0.015, 0.12, 0.03), "plastic_grey", Vector3(6.262, GENKAN_Y + 1.0, 6.12)))
	var mb := Props.label("MB", GENKAN_Y + 1.6, Color(0.2, 0.2, 0.2))
	mb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	mb.no_depth_test = false
	mb.position = Vector3(6.26, GENKAN_Y + 1.6, 6.4)
	mb.rotation.y = FACE_W
	add_child(mb)
	# Unit bath (1216): satin printed wall panels over the walls inside.
	var bp := 0.014
	_lining(Vector2(0.075 + bp, 5.51 + bp), Vector2(0.075 + bp, 7.205 - bp), [], "bath_panel", 0.0, CEIL - 0.01)
	_lining(Vector2(1.77 - bp, 5.51 + bp), Vector2(1.77 - bp, 7.205 - bp), [], "bath_panel", 0.0, CEIL - 0.01)
	_lining(Vector2(0.075 + bp, 5.51 + bp), Vector2(1.77 - bp, 5.51 + bp), [[0.8 - 0.089, 1.5 - 0.089, DOOR_TOP]], "bath_panel", 0.0, CEIL - 0.01)
	_lining(Vector2(0.075 + bp, 7.205 - bp), Vector2(1.77 - bp, 7.205 - bp), [[0.5 - 0.089, 1.2 - 0.089, 1.9, 1.25]], "bath_panel", 0.0, CEIL - 0.01)


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
	d.wood = opts.get("wood", true)
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
	_door("bath_door", "Bathroom door", Vector3(1.15, 0, 5.46), FACE_S, 0.7, "hinged", {"swing": -1.0, "color": Color(0.88, 0.9, 0.92), "glass": true, "wood": false})
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
	var phone = _clue("phone", "Phone", "side_table", Vector3(0.4, 0.45, 0.4), Color(0.75, 0.6, 0.45), Vector3(1.55, 0, 0.32), FACE_S,
		"Check", [{"clue": "jalert"}], "(no new messages)")
	phone.buzz = true
	_deco("alarm_clock", Vector3(0.12, 0.12, 0.08), Color.WHITE, Vector3(1.62, 0.45, 0.24), FACE_S, false)
	add_child(Props.box(Vector3(0.075, 0.009, 0.155), Color(0.05, 0.05, 0.06), Vector3(1.48, 0.455, 0.4)))  # the phone
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
	var radio = _clue("radio", "Hand-crank radio", "kotatsu", Vector3(0.8, 0.4, 0.8), Color(0.6, 0.42, 0.3), Vector3(4.6, 0, 1.9), FACE_S,
		"Listen to", [{"clue": "radio_sound", "night_only": true}], "(static... maybe at night)")
	radio.night_static = true
	_deco("laptop", Vector3(0.34, 0.26, 0.26), Color.WHITE, Vector3(6.06, 0.72, 0.55), FACE_W, false)
	_deco("desk_lamp", Vector3(0.3, 0.45, 0.25), Color.WHITE, Vector3(6.12, 0.72, 0.95), FACE_W, false)
	_deco("cardboard_box", Vector3(0.45, 0.4, 0.4), Color.WHITE, Vector3(6.0, 0, 0.5), FACE_W, false)
	_deco("television", Vector3(1.0, 0.68, 0.25), Color.WHITE, Vector3(6.12, 0.45, 2.0), FACE_W, false)
	_deco("binoculars", Vector3(0.2, 0.1, 0.16), Color.WHITE, Vector3(5.45, 0.6, 0.35), FACE_N, false)
	_deco("plant", Vector3(0.45, 1.1, 0.45), Color.WHITE, Vector3(6.05, 0, 3.15), FACE_W)
	_deco("wall_clock", Vector3(0.3, 0.3, 0.06), Color.WHITE, Vector3(2.8, 2.05, 1.8), FACE_E, false)
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
	add_child(Props.sbox(Vector3(1.95, 0.75, 0.01), "tile_white", Vector3(4.675, 1.23, 5.378)))  # splashback
	_deco("kettle", Vector3(0.22, 0.26, 0.18), Color.WHITE, Vector3(3.95, 0.85, 5.05), FACE_N, false)
	_deco("food_cans", Vector3(0.26, 0.12, 0.16), Color.WHITE, Vector3(4.15, 0.85, 4.95), FACE_N, false)
	_deco("water_jug", Vector3(0.28, 0.32, 0.28), Color.WHITE, Vector3(6.15, 0, 4.0), FACE_W)
	_deco("water_jug", Vector3(0.28, 0.32, 0.28), Color.WHITE, Vector3(6.15, 0, 3.7), FACE_W)
	_deco("trashbag", Vector3(0.45, 0.55, 0.45), Color.WHITE, Vector3(3.92, 0, 4.0), FACE_N)
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
	_deco("boots", Vector3(0.3, 0.38, 0.3), Color.WHITE, Vector3(4.35, GENKAN_Y, 6.6), FACE_W, false)
	_deco("intercom", Vector3(0.18, 0.13, 0.04), Color(0.95, 0.95, 0.95), Vector3(3.75, 1.35, 3.57), FACE_N, false)
	_deco("breaker_panel", Vector3(0.35, 0.3, 0.1), Color(0.95, 0.95, 0.93), Vector3(2.79, 1.85, 5.05), FACE_E, false)


func _build_outside() -> void:
	_deco("ac_outdoor", Vector3(0.7, 0.55, 0.28), Color(0.9, 0.9, 0.88), Vector3(5.55, 0, -1.3), FACE_N)
	for x in [0.6, 5.0]:  # laundry-pole hangers on the ceiling
		add_child(Props.fbox(Vector3(0.03, 0.35, 0.03), "aluminium", Vector3(x, CEIL - 0.18, -0.9)))
	var pole := MeshInstance3D.new()  # 物干し竿: a stainless pole
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 5.0
	cyl.radial_segments = 12
	pole.mesh = cyl
	pole.material_override = Props.finish("stainless")
	pole.rotation.z = PI * 0.5
	pole.position = Vector3(2.8, CEIL - 0.35, -0.9)
	add_child(pole)
	# Drain (排水口) and the gutter strip along the parapet.
	add_child(Props.fbox(Vector3(6.4, 0.012, 0.12), "plastic_grey", Vector3(3.18, -0.016, -1.4), Color(0.18, 0.18, 0.19)))


# --- Lights & world --------------------------------------------------------------

const K_NEUTRAL := Color(1.0, 0.9, 0.8)     # 昼白色 ~5000 K LED
const K_WARM := Color(1.0, 0.82, 0.64)      # 電球色 ~2800 K (toned down: walls are warm already)
const K_FLUO := Color(0.86, 0.96, 1.0)       # cool corridor fluorescent


## A round LED ceiling light (シーリングライト): a shallow white housing with a
## glowing acrylic diffuser, and a soft-shadowed light just below it.
## The diffuser and the light go in room_lights (hidden on a power cut); the
## housing and an unlit diffuser stay.
func _ceiling_light(p: Vector3, energy: float = 1.0, rng: float = 4.5, tint: Color = K_NEUTRAL,
		radius: float = 0.28) -> void:
	var l := OmniLight3D.new()
	l.position = Vector3(p.x, CEIL - 0.2, p.z)  # low enough to wash the ceiling a little, like the dome shade does
	l.omni_range = rng
	l.omni_attenuation = 1.0
	l.light_energy = energy
	l.light_color = tint
	l.shadow_blur = 1.5  # soft edges without PCSS (light_size), which costs ~1 ms per light
	l.shadow_enabled = true
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.5
	l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	l.light_specular = 0.6
	add_child(l)
	room_lights.append(l)
	var housing := _disc(radius + 0.02, 0.05, Props.mat(Color(0.86, 0.86, 0.85)), Vector3(p.x, CEIL - 0.025, p.z))
	housing.mesh.top_radius = radius + 0.01
	var off := _disc(radius, 0.04, Props.mat(Color(0.93, 0.93, 0.92)), Vector3(p.x, CEIL - 0.05, p.z))
	off.mesh.bottom_radius = radius - 0.03
	var lit_mat := StandardMaterial3D.new()
	lit_mat.albedo_color = Color(1, 1, 1)
	lit_mat.emission_enabled = true
	lit_mat.emission = tint.lerp(Color.WHITE, 0.4)
	lit_mat.emission_energy_multiplier = 3.0 * energy
	lit_mat.roughness = 0.6
	var lit := _disc(radius - 0.005, 0.045, lit_mat, Vector3(p.x, CEIL - 0.052, p.z))
	lit.mesh.bottom_radius = radius - 0.035
	room_lights.append(lit)


func _disc(r: float, h: float, m: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	cyl.radial_segments = 48
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	add_child(mi)
	return mi


func _build_lights() -> void:
	_ceiling_light(Vector3(1.36, 0, 1.82), 1.1, 4.5)                      # bedroom 6畳
	_ceiling_light(Vector3(4.55, 0, 1.82), 1.4, 5.5, K_NEUTRAL, 0.32)     # living
	_ceiling_light(Vector3(4.9, 0, 4.15), 0.9, 4.0)                      # kitchen
	_ceiling_light(Vector3(1.36, 0, 4.55), 0.7, 3.0, K_WARM, 0.16)        # washroom
	_ceiling_light(Vector3(0.91, 0, 6.37), 0.6, 2.6, K_WARM, 0.12)        # unit bath
	_ceiling_light(Vector3(2.27, 0, 6.37), 0.5, 2.2, K_WARM, 0.12)        # toilet
	_ceiling_light(Vector3(3.18, 0, 5.0), 0.6, 3.0, K_WARM, 0.14)         # hallway
	_ceiling_light(Vector3(3.64, 0, 6.82), 0.9, 3.2, K_WARM, 0.14)        # genkan
	var corridor := OmniLight3D.new()
	corridor.position = Vector3(5.5, CEIL - 0.2, 8.0)
	corridor.omni_range = 7.0
	corridor.light_energy = 1.0
	corridor.light_color = K_FLUO
	corridor.shadow_enabled = true
	corridor.shadow_blur = 1.5
	add_child(corridor)
	room_lights.append(corridor)
	var tube_mat := StandardMaterial3D.new()
	tube_mat.albedo_color = Color.WHITE
	tube_mat.emission_enabled = true
	tube_mat.emission = K_FLUO
	tube_mat.emission_energy_multiplier = 4.0
	var tube := Props.box(Vector3(1.2, 0.05, 0.1), Color.WHITE, Vector3(5.5, CEIL - 0.03, 8.0))
	tube.material_override = tube_mat
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tube)
	room_lights.append(tube)


## Kept for callers from the lighting rig: re-capture the per-room probes.
func refresh_probes() -> void:
	_recapture_probes()


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3150  # same Tokyo every run
	var street := Props.sbox(Vector3(220, 0.2, 220), "asphalt", Vector3(5, -9.3, 0))  # street level
	add_child(street)
	var facades := [_facade_material("facade_tile"), _facade_material("facade_paint")]
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
		var tone := rng.randf_range(0.85, 1.15)
		var style := rng.randi() % 2
		var bld := Props.box(Vector3(w, h, d), Color.WHITE, Vector3(x, -9.2 + h * 0.5, z))
		bld.material_override = facades[style]
		var warm := rng.randf_range(-0.04, 0.06)
		bld.set_instance_shader_parameter("bsize", Vector3(w, h, d))
		bld.set_instance_shader_parameter("tone", Color(tone + warm, tone, tone - warm))
		bld.set_instance_shader_parameter("seed", float(i) * 1.37)
		var lit := rng.randf_range(0.15, 0.45)
		bld.set_meta("lit", lit)
		bld.set_instance_shader_parameter("lit", 0.0)
		add_child(bld)
		window_lights.append(bld)
		# Pavement around the block, and rooftop plant (elevator room, water tank).
		add_child(Props.sbox(Vector3(w + 3.0, 0.15, d + 3.0), "concrete_floor", Vector3(x, -9.2 + 0.075, z), Color(1.05, 1.05, 1.03)))
		var roof := -9.2 + h
		var rw := rng.randf_range(2.0, 4.0)
		add_child(Props.sbox(Vector3(rw, 2.6, rw * 0.8), "concrete_wall", Vector3(x + rng.randf_range(-w, w) * 0.25, roof + 1.3, z), Color(0.85, 0.85, 0.83)))
		add_child(Props.sbox(Vector3(w, 0.9, 0.15), "concrete_wall", Vector3(x, roof + 0.45, z - d * 0.5 + 0.075), Color(0.85, 0.85, 0.83)))
		add_child(Props.sbox(Vector3(w, 0.9, 0.15), "concrete_wall", Vector3(x, roof + 0.45, z + d * 0.5 - 0.075), Color(0.85, 0.85, 0.83)))
		if h > 45:
			add_child(Props.box(Vector3(0.4, 0.4, 0.4), Color(1, 0.1, 0.1), Vector3(x, -9.2 + h + 2.9, z), 3.0))
	for p in [Vector3(-18, -6, -40), Vector3(30, -5, -55), Vector3(10, -6, 45)]:
		var fire := OmniLight3D.new()
		fire.position = p
		fire.omni_range = 20
		fire.light_energy = 3.0
		fire.light_color = Color(1.0, 0.45, 0.15)
		add_child(fire)


## One box-projected reflection probe per room, so metal (the stainless sink and
## worktop, door levers, aluminium sashes) reflects the room instead of the sky.
## Captured once; they only affect specular reflections, not ambient light.
func _build_reflection_probes() -> void:
	for r in [
		[0, 2.73, 0, 3.64, 0.0],         # bedroom
		[2.73, 6.37, 0, 3.64, 0.0],      # living
		[3.64, 6.37, 3.64, 5.46, 0.0],   # kitchen
		[2.73, 3.64, 3.64, 6.37, 0.0],   # hall
		[0, 2.73, 3.64, 5.46, 0.0],      # washroom
		[0, 1.82, 5.46, 7.28, 0.0],      # bath
		[1.82, 2.73, 5.46, 7.28, 0.0],   # toilet
		[2.73, 4.55, 6.37, 7.4, GENKAN_Y],   # genkan (reaching into the door reveal)
	]:
		var p := ReflectionProbe.new()
		var y0: float = r[4]
		p.size = Vector3(r[1] - r[0], CEIL - y0, r[3] - r[2])
		var cy := (y0 + CEIL) * 0.5
		p.position = Vector3((r[0] + r[1]) * 0.5, cy, (r[2] + r[3]) * 0.5)
		p.origin_offset = Vector3(0, y0 + 1.4 - cy, 0)  # capture from about eye height
		p.box_projection = true
		p.update_mode = ReflectionProbe.UPDATE_ONCE
		p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		p.blend_distance = 0.3
		p.max_distance = 12.0
		add_child(p)
		_probes.append(p)


## Re-render the once-only probes after the lighting changes (day/night,
## power cut), once now and again when the daylight fade has settled.
func _recapture_probes() -> void:
	for i in 2:
		for p in _probes:
			p.max_distance = 12.0 + randf() * 0.01  # any change re-queues an UPDATE_ONCE probe
		if i == 0 and is_inside_tree():
			await get_tree().create_timer(4.0).timeout
		if not is_inside_tree():
			return


## Distant apartment blocks: facade texture fitted per building (instance params).
func _facade_material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/facade.gdshader")
	m.set_shader_parameter("albedo_tex", load(Props.TEX_DIR + key + "_albedo.jpg"))
	m.set_shader_parameter("normal_tex", load(Props.TEX_DIR + key + "_normal.jpg"))
	m.set_shader_parameter("orm_tex", load(Props.TEX_DIR + key + "_orm.jpg"))
	m.set_shader_parameter("roof_tex", load(Props.TEX_DIR + "concrete_wall_albedo.jpg"))
	m.set_shader_parameter("macro_tex", Props.macro_texture())
	return m


func _on_world_changed() -> void:
	for l in room_lights:
		l.visible = Game.power_on
	# Blackout: only a few buildings with generators keep some windows lit.
	for b in window_lights:
		b.set_meta("generator", randf() < 0.12)
	_refresh_city_windows()


## Lit windows in the blocks around: only at night (in daylight they read as
## dark glass), and only where there's power.
func _refresh_city_windows(_phase: int = 0) -> void:
	_recapture_probes()
	var night: bool = Game.phase == Game.Phase.NIGHT
	for b in window_lights:
		var lit: float = b.get_meta("lit", 0.3) if night else 0.0
		if not Game.power_on and not b.get_meta("generator", false):
			lit = 0.0
		b.set_instance_shader_parameter("lit", lit)
