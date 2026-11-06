extends Node3D
## Set dressing: the clutter of a man in his early 30s who works too much and
## lives alone. Nothing here collides (so the navmesh, zombie paths, the
## look-ray and door swings are untouched) and nothing is interactive.
##
## Items are grouped by room into small scenes ("vignettes"). Small things are
## built from primitives here; a few use Poly Haven scans through Props.visual
## (assets/models/<name>/, credits in assets/models/CREDITS.md).
##
## Coordinates are the apartment's: +X east, +Z south, balcony at -Z, the
## genkan one step down at y = G. Wall faces: exterior walls are 0.15 thick and
## interior partitions 0.1, both centred on their grid line.

const Props := preload("res://scripts/world/props.gd")
const FONT_PATH := "res://assets/fonts/BIZUDPGothic-Bold.ttf"

const G := -0.15           # genkan floor
const FACE_S := 0.0        # local +Z (front) faces south
const FACE_N := PI
const FACE_E := PI * 0.5
const FACE_W := -PI * 0.5

# Surface heights of the furniture built in apartment.gd.
const Y_COUNTER := 0.85
const Y_DESK := 0.72
const Y_KOTATSU := 0.405
const Y_TV_STAND := 0.45
const Y_SIDE_TABLE := 0.45
const Y_DINING := 0.7
const Y_SHOE_CAB := G + 0.9
const Y_WASHER := 1.0

var rng := RandomNumberGenerator.new()
var _mats := {}
var _font: Font


func _ready() -> void:
	name = "Decor"
	rng.seed = 30311
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_genkan()
	_kitchen()
	_living()
	_bedroom()
	_washroom()
	_bath()
	_toilet()
	_balcony()
	_wall_fittings()


# --- Materials -------------------------------------------------------------------

## Plain material (cached). Culling off: many of these meshes are open or thin.
func _m(c: Color, rough: float = 0.6, metal: float = 0.0, coat: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), rough, metal, coat]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic_specular = 0.6
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.1
	_mats[key] = m
	return m


func _fab(c: Color) -> Material:
	return Props.surface("fabric", c, false)


func _fin(key: String, c: Color = Color(0, 0, 0, 0)) -> Material:
	return Props.finish(key, c)


func _paper(c: Color = Color(0.9, 0.89, 0.85)) -> Material:
	return _m(c, 0.9)


func _card() -> Material:
	return _m(Color(0.62, 0.47, 0.3), 0.9)


func _clear(c: Color = Color(0.9, 0.95, 1.0, 0.25)) -> Material:
	return _m(c, 0.12)


# --- Primitives (all local to `p`) -------------------------------------------------

func _node(p: Node, pos: Vector3, yaw: float = 0.0, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = Vector3(rot.x, yaw + rot.y, rot.z)
	p.add_child(n)
	return n


func _mesh(p: Node, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	p.add_child(mi)
	return mi


## Box by its centre.
func _bx(p: Node, size: Vector3, mat: Material, center: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(p, b, mat, center, rot)


## Box resting on `base` (bottom centre).
func _bxb(p: Node, size: Vector3, mat: Material, base: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return _bx(p, size, mat, base + Vector3(0, size.y * 0.5, 0), rot)


## Cylinder standing on `base` (bottom centre), optionally tilted about that base.
func _cy(p: Node, r_top: float, r_bot: float, h: float, mat: Material, base: Vector3, rot := Vector3.ZERO,
		seg: int = 20, caps: bool = true) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	var pivot := _node(p, base, 0.0, rot)
	return _mesh(pivot, c, mat, Vector3(0, h * 0.5, 0))


## A rod between two points.
func _rod(p: Node, a: Vector3, b: Vector3, r: float, mat: Material, seg: int = 8) -> void:
	var d := b - a
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = d.length()
	c.radial_segments = seg
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if abs(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	p.add_child(mi)


func _sph(p: Node, r: float, scl: Vector3, mat: Material, center: Vector3, rot := Vector3.ZERO, half: bool = false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if half else r * 2.0
	s.is_hemisphere = half
	s.radial_segments = 20
	s.rings = 10
	return _mesh(p, s, mat, center, rot, scl)


func _torus(p: Node, r_in: float, r_out: float, mat: Material, center: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 16
	t.ring_segments = 8
	return _mesh(p, t, mat, center, rot)


## Extrude a 2D outline (XY plane, any winding) `depth` along Z, centred.
func _ext(p: Node, pts: PackedVector2Array, depth: float, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	var tris := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := depth * 0.5
	for side in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, side))
		for i in tris.size():
			var v := pts[tris[i]]
			st.add_vertex(Vector3(v.x, v.y, h * side))
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var e := b - a
		var n := Vector3(e.y, -e.x, 0).normalized() * (1.0 if ccw else -1.0)
		st.set_normal(n)
		for v in [Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h),
				Vector3(a.x, a.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h)]:
			st.add_vertex(v)
	return _mesh(p, st.commit(), mat, pos, rot)


## Flat printed text on a surface (front = local +Z of the label).
func _text(p: Node, txt: String, pos: Vector3, rot: Vector3, px: float, col: Color, font_size: int = 32) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	if _font:
		l.font = _font
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.no_depth_test = false
	l.fixed_size = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.rotation = rot
	p.add_child(l)
	return l


## A Poly Haven scan / kit model, fitted into `size` (bottom centre at pos).
func _scan(p: Node, model: String, size: Vector3, pos: Vector3, yaw: float = 0.0, rot := Vector3.ZERO) -> Node3D:
	var n := _node(p, pos, yaw, rot)
	n.add_child(Props.visual(model, size, Color(0.6, 0.6, 0.6)))
	return n


func _j(a: float) -> float:
	return rng.randf_range(-a, a)


# --- Item builders: return a Node3D whose origin is the bottom centre ------------

func _item(p: Node, pos: Vector3, yaw: float = 0.0, rot := Vector3.ZERO) -> Node3D:
	return _node(p, pos, yaw, rot)


## 500 ml PET bottle. kind: tea (緑茶), water, cola, sports.
func _pet(p: Node, pos: Vector3, kind: String = "tea", fill: float = 1.0, rot := Vector3.ZERO) -> Node3D:
	var n := _item(p, pos, _j(PI), rot)
	var liquid: Color = {"tea": Color(0.55, 0.6, 0.2, 0.75), "water": Color(0.85, 0.92, 1.0, 0.25),
		"cola": Color(0.12, 0.05, 0.02, 0.92), "sports": Color(0.85, 0.9, 1.0, 0.45)}[kind]
	var band: Color = {"tea": Color(0.12, 0.42, 0.18), "water": Color(0.25, 0.55, 0.85),
		"cola": Color(0.75, 0.08, 0.08), "sports": Color(0.1, 0.35, 0.8)}[kind]
	var r := 0.033
	_cy(n, r, r, 0.15, _clear(Color(0.92, 0.96, 1.0, 0.18)), Vector3.ZERO)
	if fill > 0.02:
		_cy(n, r - 0.002, r - 0.002, 0.145 * fill, _m(liquid, 0.1), Vector3(0, 0.003, 0))
	_cy(n, r + 0.0008, r + 0.0008, 0.07, _m(band, 0.5), Vector3(0, 0.05, 0))
	_cy(n, 0.0125, r, 0.04, _clear(Color(0.92, 0.96, 1.0, 0.18)), Vector3(0, 0.15, 0))
	_cy(n, 0.0145, 0.0145, 0.016, _m(Color(0.95, 0.95, 0.93) if kind != "tea" else Color(0.15, 0.45, 0.2), 0.45),
		Vector3(0, 0.19, 0))
	return n


## 2 L PET (tea or water), for the stock under the rack.
func _pet2l(p: Node, pos: Vector3, kind: String = "water") -> Node3D:
	var n := _item(p, pos, _j(PI))
	var liquid := Color(0.55, 0.6, 0.2, 0.75) if kind == "tea" else Color(0.85, 0.92, 1.0, 0.25)
	_bxb(n, Vector3(0.1, 0.25, 0.1), _clear(Color(0.92, 0.96, 1.0, 0.2)), Vector3.ZERO)
	_bxb(n, Vector3(0.095, 0.24, 0.095), _m(liquid, 0.1), Vector3(0, 0.003, 0))
	_bxb(n, Vector3(0.102, 0.08, 0.102), _m(Color(0.15, 0.45, 0.2) if kind == "tea" else Color(0.3, 0.6, 0.9), 0.5), Vector3(0, 0.1, 0))
	_cy(n, 0.016, 0.05, 0.05, _clear(Color(0.92, 0.96, 1.0, 0.2)), Vector3(0, 0.25, 0))
	_cy(n, 0.017, 0.017, 0.018, _m(Color(0.95, 0.95, 0.93), 0.45), Vector3(0, 0.3, 0))
	return n


## 350 ml can (beer, chu-hi, coffee). Lying on its side if `down`.
func _can(p: Node, pos: Vector3, body: Color, down: bool = false, tall: bool = false) -> Node3D:
	var h := 0.168 if tall else 0.122
	var r := 0.033
	var rot := Vector3(PI * 0.5, 0, 0) if down else Vector3.ZERO
	var n := _item(p, pos + (Vector3(0, r, 0) if down else Vector3.ZERO), _j(PI), rot)
	if down:
		n.position -= n.basis.y * h * 0.5
	_cy(n, r, r, h - 0.012, _m(body, 0.3, 0.6), Vector3(0, 0.006, 0))
	_cy(n, r * 0.85, r, 0.006, _fin("aluminium"), Vector3.ZERO)
	_cy(n, r * 0.88, r, 0.006, _fin("aluminium"), Vector3(0, h - 0.006, 0), Vector3(PI, 0, 0))
	_cy(n, r * 0.88, r * 0.88, 0.003, _fin("aluminium"), Vector3(0, h - 0.009, 0))
	_cy(n, r + 0.0005, r + 0.0005, h * 0.3, _m(body.lightened(0.55), 0.35, 0.3), Vector3(0, h * 0.4, 0))
	return n


## Cup noodle (カップ麺), empty with its lid peeled back and 割り箸 in it, or new.
func _ramen(p: Node, pos: Vector3, eaten: bool = true, brand: Color = Color(0.8, 0.1, 0.1)) -> Node3D:
	var n := _item(p, pos, _j(PI))
	var h := 0.105
	_cy(n, 0.047, 0.034, h, _m(Color(0.95, 0.94, 0.9), 0.55), Vector3.ZERO, Vector3.ZERO, 24, not eaten)
	_cy(n, 0.0475, 0.0435, 0.035, _m(brand, 0.5), Vector3(0, 0.06, 0), Vector3.ZERO, 24, false)
	if eaten:
		_cy(n, 0.044, 0.044, 0.004, _m(Color(0.55, 0.35, 0.15, 0.95), 0.2), Vector3(0, 0.03, 0))  # dregs
		var lid := _node(n, Vector3(0, h, -0.045), 0.0, Vector3(-1.9, 0, 0))
		_cy(lid, 0.05, 0.05, 0.002, _m(Color(0.92, 0.9, 0.85), 0.35, 0.4), Vector3(0, 0, 0.05))
		for k in 2:
			_bx(n, Vector3(0.006, 0.006, 0.21), _m(Color(0.86, 0.76, 0.58), 0.8),
				Vector3(0.01 * k - 0.005, h + 0.03, 0.02), Vector3(0.45, 0.1 * k, 0))
	else:
		_cy(n, 0.049, 0.049, 0.003, _m(Color(0.95, 0.93, 0.88), 0.35, 0.3), Vector3(0, h, 0))
		_cy(n, 0.03, 0.03, 0.0006, _m(brand, 0.4), Vector3(0, h + 0.003, 0))
	return n


## Convenience-store bento container (black base, clear lid), empty-ish.
func _bento(p: Node, pos: Vector3, yaw: float, eaten: bool = true) -> Node3D:
	var n := _item(p, pos, yaw)
	_bxb(n, Vector3(0.21, 0.03, 0.16), _m(Color(0.04, 0.04, 0.04), 0.35), Vector3.ZERO)
	_bxb(n, Vector3(0.09, 0.012, 0.13), _m(Color(0.92, 0.92, 0.9), 0.6), Vector3(-0.05, 0.02, 0))  # rice
	if not eaten:
		_bxb(n, Vector3(0.08, 0.02, 0.06), _m(Color(0.6, 0.35, 0.15), 0.6), Vector3(0.05, 0.02, -0.03))
		_bxb(n, Vector3(0.06, 0.015, 0.05), _m(Color(0.85, 0.7, 0.3), 0.6), Vector3(0.05, 0.02, 0.035))
	else:
		_bxb(n, Vector3(0.02, 0.004, 0.015), _m(Color(0.7, 0.2, 0.1), 0.6), Vector3(0.06, 0.03, 0.04))
	var lid := _node(n, Vector3(0, 0.03, 0) if not eaten else Vector3(0.0, 0.0, 0.0), 0.0)
	if eaten:
		lid.position = Vector3(0.02, 0.031, -0.01)
		lid.rotation = Vector3(0, 0.3, 0.06)
	_bxb(lid, Vector3(0.215, 0.025, 0.165), _clear(Color(0.95, 0.97, 1.0, 0.15)), Vector3.ZERO)
	return n


## Convenience-store plastic bag (レジ袋), slumped, with something inside.
func _conbini_bag(p: Node, pos: Vector3, yaw: float) -> Node3D:
	var n := _item(p, pos, yaw)
	var film := _m(Color(0.95, 0.95, 0.94, 0.85), 0.45)
	_sph(n, 0.14, Vector3(1.15, 0.6, 0.75), film, Vector3(0, 0.08, 0))
	_sph(n, 0.08, Vector3(1.0, 0.55, 0.9), film, Vector3(0.1, 0.06, 0.05), Vector3(0, 0.4, 0))
	_torus(n, 0.035, 0.045, film, Vector3(-0.06, 0.15, 0.0), Vector3(0.3, 0, 1.2))
	_torus(n, 0.035, 0.045, film, Vector3(0.05, 0.14, -0.02), Vector3(-0.3, 0, 1.4))
	_bxb(n, Vector3(0.05, 0.003, 0.03), _m(Color(0.1, 0.45, 0.25), 0.5), Vector3(0.0, 0.16, 0.07), Vector3(-0.6, 0, 0))
	return n


func _mug(p: Node, pos: Vector3, col: Color, coffee: bool = true) -> Node3D:
	var n := _item(p, pos, _j(PI))
	var ceramic := _m(col, 0.25, 0.0, 0.6)
	_cy(n, 0.041, 0.038, 0.095, ceramic, Vector3.ZERO, Vector3.ZERO, 24, false)
	_cy(n, 0.038, 0.038, 0.004, ceramic, Vector3.ZERO)
	if coffee:
		_cy(n, 0.039, 0.039, 0.002, _m(Color(0.1, 0.05, 0.02), 0.1), Vector3(0, 0.05, 0))
		_cy(n, 0.0405, 0.0395, 0.01, _m(Color(0.25, 0.14, 0.06, 0.7), 0.5), Vector3(0, 0.07, 0), Vector3.ZERO, 24, false)  # stain ring
	_torus(n, 0.022, 0.03, ceramic, Vector3(0.045, 0.05, 0), Vector3(PI * 0.5, 0, 0))
	return n


## Paperbacks/manga lying in a messy stack.
func _book_stack(p: Node, pos: Vector3, count: int, size := Vector3(0.113, 0.016, 0.177), yaw: float = 0.0) -> Node3D:
	var n := _item(p, pos, yaw)
	var cols := [Color(0.85, 0.2, 0.15), Color(0.95, 0.85, 0.3), Color(0.2, 0.35, 0.7), Color(0.95, 0.95, 0.92),
		Color(0.15, 0.15, 0.17), Color(0.3, 0.65, 0.4), Color(0.9, 0.5, 0.2)]
	var y := 0.0
	for i in count:
		var c: Color = cols[rng.randi() % cols.size()]
		var b := _node(n, Vector3(_j(0.012), y, _j(0.012)), _j(0.25))
		_bxb(b, size, _paper(Color(0.93, 0.91, 0.85)), Vector3.ZERO)
		_bxb(b, Vector3(size.x + 0.002, size.y * 0.98, size.z + 0.002), _m(c, 0.5), Vector3.ZERO).scale = Vector3(1, 1, 1)
		_bxb(b, Vector3(size.x - 0.006, size.y + 0.002, size.z - 0.004), _paper(Color(0.96, 0.95, 0.9)), Vector3(0.004, -0.001, 0))
		y += size.y
	return n


## A sheet (or a loose stack) of paper.
func _papers(p: Node, pos: Vector3, yaw: float, count: int = 5, size := Vector2(0.21, 0.297), col := Color(0.93, 0.93, 0.9)) -> Node3D:
	var n := _item(p, pos, yaw)
	for i in count:
		_bxb(n, Vector3(size.x, 0.0012, size.y), _paper(col.darkened(rng.randf_range(0.0, 0.06))),
			Vector3(_j(0.015), i * 0.0012, _j(0.015)), Vector3(0, _j(0.12), 0))
	return n


func _remote(p: Node, pos: Vector3, yaw: float) -> Node3D:
	var n := _item(p, pos, yaw)
	_bxb(n, Vector3(0.048, 0.02, 0.19), _fin("plastic_black"), Vector3.ZERO)
	_bxb(n, Vector3(0.012, 0.004, 0.012), _m(Color(0.75, 0.1, 0.1), 0.4), Vector3(-0.012, 0.02, -0.075))
	for i in 4:
		for k in 3:
			_bxb(n, Vector3(0.009, 0.003, 0.007), _fin("plastic_grey"), Vector3(-0.013 + k * 0.013, 0.02, -0.03 + i * 0.016))
	return n


func _tissue_box(p: Node, pos: Vector3, yaw: float) -> Node3D:
	var n := _item(p, pos, yaw)
	_bxb(n, Vector3(0.24, 0.06, 0.115), _m(Color(0.93, 0.93, 0.95), 0.6), Vector3.ZERO)
	_bxb(n, Vector3(0.1, 0.002, 0.03), _m(Color(0.5, 0.65, 0.85), 0.6), Vector3(0.07, 0.06, 0.03))
	_sph(n, 0.03, Vector3(1.4, 0.9, 0.5), _m(Color(0.98, 0.98, 0.98), 0.9), Vector3(0, 0.07, 0), Vector3(0, 0, 0.3))
	return n


## Business shoe / sneaker side profile, extruded across its width. Toe = local +Z.
func _shoe(p: Node, pos: Vector3, yaw: float, kind: String = "business", on_side: bool = false) -> Node3D:
	var biz := kind == "business"
	var w := 0.094 if biz else 0.102
	var rot := Vector3(0, 0, PI * 0.5) if on_side else Vector3.ZERO
	var n := _item(p, pos + (Vector3(0, w * 0.5, 0) if on_side else Vector3.ZERO), yaw, rot)
	var upper: Material = _m(Color(0.03, 0.026, 0.024), 0.3, 0.0, 0.7) if biz else _fab(Color(0.86, 0.86, 0.87))
	var sole_m: Material = _m(Color(0.05, 0.04, 0.035), 0.7) if biz else _m(Color(0.93, 0.93, 0.9), 0.7)
	var sole_h := 0.014 if biz else 0.028
	# Sole: plan outline (X across, Y along the foot, toe at +Y), wider at the ball.
	var sole := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var y := sin(a) * 0.142
		var half := w * 0.5 * (1.0 if y > -0.02 else 0.8)
		if y > 0.09:
			half *= 0.85 if biz else 0.95
		sole.append(Vector2(cos(a) * half, y))
	_ext(n, sole, sole_h, sole_m, Vector3(0, sole_h * 0.5, 0), Vector3(PI * 0.5, 0, 0))
	if biz:
		_bxb(n, Vector3(w * 0.78, 0.024, 0.07), sole_m, Vector3(0, 0, -0.1))  # heel block
	# Upper: a half-ellipsoid over the sole, lower at the toe.
	var hy := 0.075 if biz else 0.085
	var upper_base := sole_h + (0.01 if biz else 0.0)
	_sph(n, 1.0, Vector3(w * 0.47, hy, 0.135), upper, Vector3(0, upper_base, 0.0), Vector3.ZERO, true)
	_sph(n, 1.0, Vector3(w * 0.44, hy * 0.55, 0.06), upper, Vector3(0, upper_base, 0.085), Vector3.ZERO, true)  # toe box
	# Collar opening.
	_cy(n, 1.0, 1.0, 0.004, _m(Color(0.15, 0.12, 0.1) if biz else Color(0.3, 0.3, 0.32), 0.9),
		Vector3(0, upper_base + hy * 0.86, -0.065), Vector3(-0.15, 0, 0), 20).scale = Vector3(w * 0.33, 1.0, 0.05)
	if not biz:
		for i in 4:
			_bx(n, Vector3(w * 0.42, 0.004, 0.006), _m(Color(0.97, 0.97, 0.97), 0.7),
				Vector3(0, upper_base + hy * 0.93 - i * 0.008, -0.01 + i * 0.022), Vector3(0.35, 0, 0))
		_bx(n, Vector3(0.004, 0.02, 0.07), _m(Color(0.15, 0.3, 0.6), 0.5), Vector3(w * 0.47, upper_base + 0.03, -0.02))
	return n


## Plastic sandals (ベランダ/便所サンダル) or slippers (スリッパ).
func _sandal(p: Node, pos: Vector3, yaw: float, col: Color, slipper: bool = false) -> Node3D:
	var n := _item(p, pos, yaw)
	var mat := _m(col, 0.55) if not slipper else _fab(col)
	var L := 0.26 if not slipper else 0.27
	var sole := PackedVector2Array()
	for i in 16:  # rounded sole outline in plan (X across, Y = along length)
		var a := TAU * i / 16.0
		sole.append(Vector2(cos(a) * 0.047 * (1.0 if sin(a) > 0 else 0.88), sin(a) * L * 0.5))
	_ext(n, sole, 0.022 if not slipper else 0.015, mat, Vector3(0, 0.011, 0), Vector3(PI * 0.5, 0, 0))
	if slipper:
		_sph(n, 0.05, Vector3(1.0, 0.75, 1.4), mat, Vector3(0, 0.015, 0.05), Vector3.ZERO, true)
	else:
		_bxb(n, Vector3(0.1, 0.035, 0.07), mat, Vector3(0, 0.02, 0.04))
		_bxb(n, Vector3(0.08, 0.03, 0.06), _m(col.darkened(0.6), 0.9), Vector3(0, 0.018, 0.04))
	return n


## Clothes hanger with the garment hanging below. Origin = top of the hook.
## Garment plane is local XY (shoulders along X), front facing +Z.
func _hanger(p: Node, pos: Vector3, yaw: float, garment: String, col: Color) -> Node3D:
	var n := _item(p, pos, yaw)
	var wire := _fin("chrome") if garment != "jacket" else _m(Color(0.35, 0.22, 0.12), 0.5)
	_torus(n, 0.012, 0.016, _fin("chrome"), Vector3(0, -0.012, 0), Vector3(PI * 0.5, 0, 0))
	_rod(n, Vector3(0, -0.026, 0), Vector3(0, -0.055, 0), 0.0025, _fin("chrome"))
	_rod(n, Vector3(0, -0.055, 0), Vector3(-0.2, -0.12, 0), 0.006, wire)
	_rod(n, Vector3(0, -0.055, 0), Vector3(0.2, -0.12, 0), 0.006, wire)
	var cloth := _fab(col)
	match garment:
		"jacket":
			var pts := PackedVector2Array([Vector2(-0.07, -0.06), Vector2(-0.21, -0.1), Vector2(-0.25, -0.16), Vector2(-0.26, -0.72),
				Vector2(-0.215, -0.8), Vector2(0.215, -0.8), Vector2(0.26, -0.72), Vector2(0.25, -0.16), Vector2(0.21, -0.1),
				Vector2(0.07, -0.06), Vector2(0.0, -0.3)])
			_ext(n, pts, 0.07, cloth)
			_ext(n, PackedVector2Array([Vector2(-0.06, -0.075), Vector2(0.06, -0.075), Vector2(0.0, -0.3)]), 0.005,
				_fab(Color(0.92, 0.93, 0.95)), Vector3(0, 0, 0.034))  # shirt-white V where the lapels part
			for i in 2:
				_cy(n, 0.008, 0.008, 0.004, _m(Color(0.05, 0.05, 0.06), 0.3), Vector3(0.02, -0.42 - i * 0.1, 0.036), Vector3(PI * 0.5, 0, 0))
		"shirt":
			var pts := PackedVector2Array([Vector2(-0.06, -0.06), Vector2(-0.2, -0.1), Vector2(-0.24, -0.16), Vector2(-0.245, -0.7),
				Vector2(-0.2, -0.76), Vector2(0.2, -0.76), Vector2(0.245, -0.7), Vector2(0.24, -0.16), Vector2(0.2, -0.1),
				Vector2(0.06, -0.06)])
			_ext(n, pts, 0.035, cloth)
			_bx(n, Vector3(0.13, 0.035, 0.04), cloth, Vector3(0, -0.07, 0.003))
			for i in 5:
				_cy(n, 0.005, 0.005, 0.003, _m(Color(0.95, 0.95, 0.95), 0.3), Vector3(0.0, -0.16 - i * 0.11, 0.018), Vector3(PI * 0.5, 0, 0))
		"trousers":
			_rod(n, Vector3(-0.2, -0.12, 0), Vector3(0.2, -0.12, 0), 0.006, wire)
			_bx(n, Vector3(0.34, 0.5, 0.03), cloth, Vector3(0, -0.37, 0))
			_cy(n, 0.016, 0.016, 0.34, cloth, Vector3(-0.17, -0.12, 0), Vector3(0, 0, -PI * 0.5))
		"hoodie":
			var pts := PackedVector2Array([Vector2(-0.08, -0.06), Vector2(-0.22, -0.11), Vector2(-0.27, -0.2), Vector2(-0.28, -0.62),
				Vector2(-0.23, -0.66), Vector2(0.23, -0.66), Vector2(0.28, -0.62), Vector2(0.27, -0.2), Vector2(0.22, -0.11),
				Vector2(0.08, -0.06)])
			_ext(n, pts, 0.06, cloth)
			_sph(n, 0.09, Vector3(1.0, 0.7, 0.45), cloth, Vector3(0, -0.1, -0.05))
		"towel":
			_rod(n, Vector3(-0.2, -0.12, 0), Vector3(0.2, -0.12, 0), 0.006, wire)
			_bx(n, Vector3(0.34, 0.42, 0.012), cloth, Vector3(0, -0.33, 0.008))
			_bx(n, Vector3(0.34, 0.42, 0.012), cloth, Vector3(0, -0.33, -0.008))
	return n


## ピンチハンガー: a square frame of pegs with socks and a towel. Origin = hook top.
func _pinch_hanger(p: Node, pos: Vector3, yaw: float) -> Node3D:
	var n := _item(p, pos, yaw)
	var frame := _m(Color(0.88, 0.9, 0.92), 0.4)
	var y := -0.25
	_torus(n, 0.016, 0.021, frame, Vector3(0, -0.018, 0), Vector3(PI * 0.5, 0, 0))
	for c in [Vector3(-0.2, y, -0.15), Vector3(0.2, y, -0.15), Vector3(-0.2, y, 0.15), Vector3(0.2, y, 0.15)]:
		_rod(n, Vector3(0, -0.04, 0), c, 0.002, _fin("plastic_white"))
	_rod(n, Vector3(-0.2, y, -0.15), Vector3(0.2, y, -0.15), 0.006, frame)
	_rod(n, Vector3(-0.2, y, 0.15), Vector3(0.2, y, 0.15), 0.006, frame)
	_rod(n, Vector3(-0.2, y, -0.15), Vector3(-0.2, y, 0.15), 0.006, frame)
	_rod(n, Vector3(0.2, y, -0.15), Vector3(0.2, y, 0.15), 0.006, frame)
	_rod(n, Vector3(0, y, -0.15), Vector3(0, y, 0.15), 0.005, frame)
	var sock_cols := [Color(0.06, 0.06, 0.07), Color(0.12, 0.12, 0.14), Color(0.06, 0.06, 0.07), Color(0.3, 0.3, 0.32)]
	var i := 0
	for z in [-0.15, 0.15]:
		for x in [-0.15, -0.06, 0.06, 0.15]:
			_bx(n, Vector3(0.012, 0.03, 0.015), _m(Color(0.55, 0.8, 0.95), 0.5), Vector3(x, y - 0.02, z))
			var c: Color = sock_cols[i % sock_cols.size()]
			i += 1
			if i == 7:
				continue
			var sock := PackedVector2Array([Vector2(-0.035, 0), Vector2(0.035, 0), Vector2(0.035, -0.2), Vector2(0.11, -0.22),
				Vector2(0.115, -0.26), Vector2(0.03, -0.27), Vector2(-0.035, -0.24)])
			_ext(n, sock, 0.01, _fab(c), Vector3(x, y - 0.03, z), Vector3(0, PI * 0.5 if z < 0 else -PI * 0.5, 0))
	# A face towel and boxers on the middle bar.
	_bx(n, Vector3(0.012, 0.3, 0.26), _fab(Color(0.85, 0.82, 0.74)), Vector3(0.0, y - 0.15, 0.0))
	_bx(n, Vector3(0.22, 0.2, 0.012), _fab(Color(0.2, 0.25, 0.4)), Vector3(-0.1, y - 0.12, 0.02), Vector3(0, 0.15, 0))
	return n


## 45 L translucent garbage bag (指定袋), tied, with contents showing.
func _garbage_bag(p: Node, pos: Vector3, yaw: float, tint: Color, contents: Array, label: String = "") -> Node3D:
	var n := _item(p, pos, yaw)
	for c in contents:
		_bx(n, Vector3(rng.randf_range(0.06, 0.14), rng.randf_range(0.04, 0.12), rng.randf_range(0.06, 0.14)), _m(c, 0.5),
			Vector3(_j(0.1), rng.randf_range(0.06, 0.26), _j(0.08)), Vector3(_j(1.0), _j(1.0), _j(1.0)))
	var film := _m(tint, 0.42)
	_sph(n, 0.2, Vector3(1.1, 0.75, 0.9), film, Vector3(0, 0.15, 0))
	_sph(n, 0.15, Vector3(1.0, 0.9, 0.9), film, Vector3(0.04, 0.26, 0.02), Vector3(0, 0.5, 0.15))
	_sph(n, 0.12, Vector3(1.0, 0.7, 0.9), film, Vector3(-0.08, 0.1, 0.06))
	_sph(n, 0.06, Vector3(0.8, 1.0, 0.7), film, Vector3(0.03, 0.4, 0.01))
	for k in 2:
		_sph(n, 0.05, Vector3(1.4, 0.35, 0.6), film, Vector3(0.03 + k * 0.03, 0.46, 0), Vector3(0, k * 1.4, 0.6 - k * 1.2))
	if label != "":
		_bx(n, Vector3(0.1, 0.035, 0.002), _paper(Color(0.95, 0.95, 0.9)), Vector3(0, 0.26, 0.173), Vector3(-0.25, 0, 0))
		_text(n, label, Vector3(0, 0.26, 0.1745), Vector3(-0.25, 0, 0), 0.0006, Color(0.1, 0.1, 0.1), 40)
	return n


func _switch_plate(p: Node, pos: Vector3, yaw: float, gangs: int = 2) -> void:
	var n := _item(p, pos, yaw)
	_bx(n, Vector3(0.07, 0.12, 0.008), _fin("plastic_white"), Vector3(0, 0, 0.004))
	for i in gangs:
		var h := 0.09 / gangs
		_bx(n, Vector3(0.045, h - 0.006, 0.006), _m(Color(0.93, 0.93, 0.91), 0.35), Vector3(0, -0.045 + h * (i + 0.5), 0.009))
		_bx(n, Vector3(0.004, 0.004, 0.002), _m(Color(0.3, 0.8, 0.3), 0.3), Vector3(0.015, -0.045 + h * (i + 0.5), 0.0125))


func _socket(p: Node, pos: Vector3, yaw: float) -> void:
	var n := _item(p, pos, yaw)
	_bx(n, Vector3(0.07, 0.12, 0.008), _fin("plastic_white"), Vector3(0, 0, 0.004))
	for y in [-0.025, 0.025]:
		_bx(n, Vector3(0.045, 0.04, 0.005), _m(Color(0.93, 0.93, 0.91), 0.35), Vector3(0, y, 0.009))
		for x in [-0.0065, 0.0065]:
			_bx(n, Vector3(0.0025, 0.009, 0.002), _m(Color(0.05, 0.05, 0.05), 0.8), Vector3(x, y, 0.0115))


## A cable lying along a list of points.
func _cable(p: Node, pts: Array, col: Color = Color(0.92, 0.92, 0.9), r: float = 0.0022) -> void:
	for i in pts.size() - 1:
		_rod(p, pts[i], pts[i + 1], r, _m(col, 0.5), 6)


# --- Genkan -----------------------------------------------------------------------

func _genkan() -> void:
	# Shoes kicked off on the tiles, toes pointing into the flat (he never turns them round).
	_shoe(self, Vector3(3.38, G, 6.66), PI + 0.15, "business")
	_shoe(self, Vector3(3.5, G, 6.7), PI - 0.35, "business", true)
	_shoe(self, Vector3(3.14, G, 6.82), PI * 0.62, "sneaker")
	_shoe(self, Vector3(3.24, G, 6.88), PI * 0.55, "sneaker")
	_sandal(self, Vector3(3.6, G, 7.0), 0.4, Color(0.15, 0.2, 0.35))
	_sandal(self, Vector3(3.5, G, 7.06), 0.2, Color(0.15, 0.2, 0.35))
	# Cans and bottles waiting for collection day (缶・びん・ペットボトル), out on the balcony.
	_garbage_bag(self, Vector3(0.75, -0.02, -1.22), 0.3, Color(0.82, 0.88, 0.93, 0.5),
		[Color(0.7, 0.72, 0.75), Color(0.85, 0.75, 0.2), Color(0.7, 0.72, 0.75), Color(0.9, 0.95, 1.0), Color(0.2, 0.4, 0.8)], "缶・ペット")
	# Umbrella stand by the step, a clear convenience-store umbrella against the wall.
	var stand := _item(self, Vector3(2.86, G, 6.5), 0.0)
	_cy(stand, 0.085, 0.08, 0.42, _fin("stainless"), Vector3.ZERO, Vector3.ZERO, 20, false)
	_cy(stand, 0.08, 0.08, 0.01, _fin("stainless"), Vector3.ZERO)
	_umbrella(stand, Vector3(-0.02, 0.01, 0.01), Vector3(0.12, 0, -0.08), Color(0.08, 0.1, 0.2), 0.88)
	_umbrella(stand, Vector3(0.02, 0.01, -0.01), Vector3(-0.08, 0, 0.14), Color(0.1, 0.1, 0.1), 0.82)
	_umbrella(self, Vector3(4.5, G, 6.45), Vector3(0.0, 0, 0.17), Color(0.92, 0.95, 0.97, 0.45), 0.86)
	# Top of the shoe cabinet: key tray, delivery slips (不在票), flyers, hand sanitiser.
	var top := Y_SHOE_CAB
	var tray := _item(self, Vector3(4.24, top, 6.94), 0.2)
	_cy(tray, 0.085, 0.075, 0.015, _m(Color(0.3, 0.2, 0.12), 0.4, 0.0, 0.5), Vector3.ZERO, Vector3.ZERO, 24, true)
	_bxb(tray, Vector3(0.025, 0.004, 0.06), _fin("stainless"), Vector3(0.02, 0.015, 0.0), Vector3(0, 0.6, 0))
	_bxb(tray, Vector3(0.03, 0.012, 0.02), _fin("plastic_black"), Vector3(0.0, 0.015, -0.035), Vector3(0, 0.3, 0))
	_cy(tray, 0.012, 0.012, 0.002, _m(Color(0.75, 0.55, 0.3), 0.3, 0.8), Vector3(-0.04, 0.015, 0.02))
	_cy(tray, 0.011, 0.011, 0.002, _fin("aluminium"), Vector3(-0.03, 0.015, -0.02))
	var slips := _item(self, Vector3(4.38, top + 0.0085, 7.1), -0.3)
	var slip_cols := [Color(0.98, 0.85, 0.3), Color(0.55, 0.75, 0.95), Color(0.95, 0.55, 0.5), Color(0.98, 0.85, 0.3)]
	for i in slip_cols.size():
		_bxb(slips, Vector3(0.1, 0.001, 0.15), _paper(slip_cols[i]), Vector3(_j(0.02), i * 0.0012, _j(0.02)), Vector3(0, _j(0.3), 0))
	_text(slips, "ご不在連絡票", Vector3(0.0, 0.0055, -0.04), Vector3(-PI * 0.5, 0, 0), 0.00045, Color(0.2, 0.2, 0.2), 32)
	_papers(self, Vector3(4.36, top, 7.05), 0.15, 6, Vector2(0.18, 0.257), Color(0.95, 0.92, 0.85))
	var flyer := _item(self, Vector3(4.36, top + 0.0075, 7.05), 0.2)
	_bxb(flyer, Vector3(0.18, 0.001, 0.257), _paper(Color(0.95, 0.75, 0.2)), Vector3.ZERO)
	_text(flyer, "宅配ピザ\n2枚目半額", Vector3(0, 0.0012, 0.0), Vector3(-PI * 0.5, 0, 0), 0.0009, Color(0.75, 0.1, 0.05), 40)
	var gel := _item(self, Vector3(3.79, top, 7.12), 0.0)
	_cy(gel, 0.03, 0.03, 0.13, _m(Color(0.85, 0.92, 0.95, 0.6), 0.2), Vector3.ZERO)
	_cy(gel, 0.012, 0.012, 0.03, _fin("plastic_white"), Vector3(0, 0.13, 0))
	_bx(gel, Vector3(0.035, 0.008, 0.012), _fin("plastic_white"), Vector3(0, 0.165, 0.012))
	# Lanyard + staff ID and a shoehorn hanging on adhesive hooks above the boots.
	_lanyard(Vector3(4.474, 1.15, 6.66), FACE_W)
	var horn := _item(self, Vector3(4.474, 0.62, 6.84), FACE_W)
	_bx(horn, Vector3(0.02, 0.02, 0.012), _fin("plastic_white"), Vector3(0, 0.0, 0.006))
	_ext(horn, PackedVector2Array([Vector2(-0.008, 0.0), Vector2(0.008, 0.0), Vector2(0.012, -0.38), Vector2(0.025, -0.48),
		Vector2(0.02, -0.53), Vector2(-0.02, -0.53), Vector2(-0.025, -0.48), Vector2(-0.012, -0.38)]), 0.006,
		_m(Color(0.3, 0.18, 0.08), 0.3, 0.0, 0.5), Vector3(0, -0.01, 0.016))


func _umbrella(p: Node, base: Vector3, lean: Vector3, col: Color, length: float) -> void:
	var n := _item(p, base, 0.0, lean)
	var canopy := _m(col, 0.4) if col.a >= 1.0 else _clear(col)
	_cy(n, 0.004, 0.004, 0.06, _fin("stainless"), Vector3.ZERO)  # ferrule
	_cy(n, 0.045, 0.012, length * 0.62, canopy, Vector3(0, 0.05, 0), Vector3.ZERO, 8)
	_cy(n, 0.006, 0.006, length * 0.3, _fin("plastic_black") if col.a >= 1.0 else _fin("plastic_white"), Vector3(0, length * 0.62, 0))
	_cy(n, 0.013, 0.013, 0.11, _fin("plastic_black") if col.a >= 1.0 else _fin("plastic_white"),
		Vector3(0, length * 0.9, 0), Vector3(0, 0, 0.35))
	_cy(n, 0.02, 0.012, 0.03, _m(Color(0.95, 0.95, 0.95, 0.9), 0.5), Vector3(0, length * 0.5, 0))  # strap


func _lanyard(pos: Vector3, yaw: float) -> void:
	var n := _item(self, pos, yaw)
	_bx(n, Vector3(0.02, 0.02, 0.012), _fin("plastic_white"), Vector3(0, 0, 0.006))
	var strap := _m(Color(0.1, 0.25, 0.55), 0.6)
	_rod(n, Vector3(0, 0.0, 0.018), Vector3(-0.05, -0.28, 0.012), 0.004, strap)
	_rod(n, Vector3(0, 0.0, 0.018), Vector3(0.05, -0.28, 0.012), 0.004, strap)
	_bx(n, Vector3(0.06, 0.09, 0.004), _clear(Color(0.9, 0.95, 1.0, 0.35)), Vector3(0, -0.33, 0.012))
	_bx(n, Vector3(0.054, 0.085, 0.002), _paper(Color(0.95, 0.95, 0.95)), Vector3(0, -0.33, 0.011))
	_bx(n, Vector3(0.054, 0.012, 0.0025), _m(Color(0.1, 0.25, 0.55), 0.5), Vector3(0, -0.293, 0.0115))
	_bx(n, Vector3(0.022, 0.028, 0.0025), _m(Color(0.6, 0.62, 0.66), 0.6), Vector3(-0.012, -0.325, 0.0115))
	_text(n, "社員証", Vector3(0.012, -0.36, 0.0128), Vector3.ZERO, 0.0003, Color(0.1, 0.1, 0.1), 32)
	# Keys on a ring hanging from the same hook.
	_torus(n, 0.01, 0.012, _fin("stainless"), Vector3(0.012, -0.03, 0.018), Vector3(0, 0, 0))
	_bx(n, Vector3(0.018, 0.05, 0.002), _fin("stainless"), Vector3(0.016, -0.065, 0.02), Vector3(0, 0, 0.2))


# --- Kitchen ----------------------------------------------------------------------

func _kitchen() -> void:
	# A steel rack (スチールラック) against the hall wall: rice cooker on top, stock below.
	var rack := _item(self, Vector3(3.87, 0, 4.48), FACE_E)  # local X runs along the wall (z)
	var w := 0.46
	var d := 0.3
	for x in [-w * 0.5 + 0.01, w * 0.5 - 0.01]:
		for z in [-d * 0.5 + 0.01, d * 0.5 - 0.01]:
			_cy(rack, 0.0095, 0.0095, 0.9, _fin("chrome"), Vector3(x, 0, z), Vector3.ZERO, 10)
	for y in [0.05, 0.45, 0.86]:
		_bx(rack, Vector3(w, 0.008, d), _fin("steel_painted_light", Color(0.75, 0.75, 0.74)), Vector3(0, y, 0))
	_rice_cooker(rack, Vector3(0.02, 0.865, 0.0), 0.1)
	var rice := _item(rack, Vector3(-0.08, 0.455, 0.0), 0.1)
	_bxb(rice, Vector3(0.25, 0.1, 0.3), _m(Color(0.93, 0.9, 0.82), 0.6), Vector3.ZERO)
	_bxb(rice, Vector3(0.2, 0.02, 0.26), _m(Color(0.93, 0.9, 0.82), 0.6), Vector3(0, 0.1, 0))
	_text(rice, "新米\nこしひかり 5kg", Vector3(0, 0.124, 0.02), Vector3(-PI * 0.5, 0, 0), 0.0012, Color(0.15, 0.4, 0.15), 40)
	for i in 3:
		_ramen(rack, Vector3(0.1 + (i % 2) * 0.03, 0.455 + (i / 2) * 0.106, -0.07 + (i % 2) * 0.1), false,
			[Color(0.8, 0.1, 0.1), Color(0.9, 0.6, 0.1), Color(0.8, 0.1, 0.1)][i])
	_pet2l(rack, Vector3(-0.15, 0.055, 0.04), "tea")
	_pet2l(rack, Vector3(-0.04, 0.055, 0.05), "water")
	_pet2l(rack, Vector3(0.07, 0.055, 0.04), "water")
	# Plastics bag next to the burnables, full of bento trays.
	_garbage_bag(self, Vector3(4.28, 0, 4.12), 0.6, Color(0.95, 0.95, 0.9, 0.55),
		[Color(0.05, 0.05, 0.05), Color(0.05, 0.05, 0.05), Color(0.9, 0.9, 0.9), Color(0.85, 0.2, 0.15), Color(0.9, 0.95, 1.0)], "プラ")
	# Flattened delivery boxes tied with string, leaning between the water jugs and fridge.
	var flat := _item(self, Vector3(6.24, 0, 4.38), FACE_W, Vector3(0.12, 0, 0))
	for i in 4:
		_bxb(flat, Vector3(0.52 - i * 0.03, 0.6 - i * 0.04, 0.008), _card(), Vector3(_j(0.02), 0.0, -0.02 + i * 0.009))
	_bx(flat, Vector3(0.004, 0.62, 0.05), _paper(Color(0.9, 0.88, 0.8)), Vector3(0.0, 0.3, 0.0))
	_bx(flat, Vector3(0.54, 0.004, 0.05), _paper(Color(0.9, 0.88, 0.8)), Vector3(0.0, 0.3, 0.0))
	# Sink: drainer with a few dishes, detergent, sponge, cutting board.
	var c := Y_COUNTER
	var drainer := _item(self, Vector3(4.47, c, 5.12), 0.04)
	var wire := _fin("stainless")
	for x in [-0.14, 0.14]:
		_rod(drainer, Vector3(x, 0.0, -0.11), Vector3(x, 0.0, 0.11), 0.003, wire)
		_rod(drainer, Vector3(x, 0.12, -0.11), Vector3(x, 0.12, 0.11), 0.003, wire)
		for z in [-0.11, 0.11]:
			_rod(drainer, Vector3(x, 0.0, z), Vector3(x, 0.12, z), 0.003, wire)
	for z in [-0.11, 0.11]:
		_rod(drainer, Vector3(-0.14, 0.12, z), Vector3(0.14, 0.12, z), 0.003, wire)
	for i in 7:
		_rod(drainer, Vector3(-0.14, 0.005, -0.09 + i * 0.03), Vector3(0.14, 0.005, -0.09 + i * 0.03), 0.002, wire)
	_bxb(drainer, Vector3(0.3, 0.006, 0.24), _m(Color(0.88, 0.9, 0.92, 0.7), 0.3), Vector3(0, -0.006, 0))
	for i in 2:
		_cy(drainer, 0.1 - i * 0.015, 0.1 - i * 0.015, 0.012, _fin("porcelain"), Vector3(-0.08 + i * 0.04, 0.1, 0.0), Vector3(0, 0, PI * 0.5 - 0.18))
	var bowl := _cy(drainer, 0.065, 0.035, 0.06, _fin("porcelain", Color(0.75, 0.66, 0.55)), Vector3(0.07, 0.07, -0.04), Vector3(PI * 0.6, 0, 0), 20, false)
	bowl.get_parent().rotation.y = 0.3
	_cy(drainer, 0.035, 0.03, 0.09, _clear(Color(0.9, 0.95, 1.0, 0.3)), Vector3(0.09, 0.006, 0.07), Vector3.ZERO, 16, false)
	for k in 2:
		_bx(drainer, Vector3(0.006, 0.006, 0.23), _m(Color(0.2, 0.08, 0.05), 0.4), Vector3(0.12, 0.06, 0.0 + k * 0.01), Vector3(0.5, 0, 0))
	var soap := _item(self, Vector3(4.83, c, 5.3), 0.3)
	_cy(soap, 0.028, 0.03, 0.15, _m(Color(0.6, 0.85, 0.35, 0.8), 0.15), Vector3.ZERO)
	_cy(soap, 0.013, 0.013, 0.025, _m(Color(0.95, 0.95, 0.93), 0.4), Vector3(0, 0.15, 0))
	var sponge := _item(self, Vector3(4.92, c, 5.27), -0.4)
	_bxb(sponge, Vector3(0.11, 0.025, 0.07), _m(Color(0.95, 0.85, 0.25), 0.95), Vector3.ZERO)
	_bxb(sponge, Vector3(0.11, 0.008, 0.07), _m(Color(0.15, 0.45, 0.25), 0.95), Vector3(0, 0.025, 0))
	_scan(self, "cutting_board", Vector3(0.36, 0.36, 0.36), Vector3(4.47, c + 0.01, 5.355), 0.0, Vector3(-PI * 0.5 + 0.18, 0, 0))
	# Stove: last night's frying pan, never washed.
	var pan := _item(self, Vector3(5.2, 0.935, 5.0), 0.7)
	_cy(pan, 0.12, 0.1, 0.045, _fin("plastic_black", Color(0.06, 0.06, 0.065)), Vector3.ZERO, Vector3.ZERO, 28, false)
	_cy(pan, 0.1, 0.1, 0.003, _fin("plastic_black", Color(0.06, 0.06, 0.065)), Vector3.ZERO)
	_cy(pan, 0.08, 0.08, 0.002, _m(Color(0.45, 0.32, 0.12, 0.6), 0.2), Vector3(0, 0.004, 0))
	_bx(pan, Vector3(0.025, 0.02, 0.18), _m(Color(0.12, 0.08, 0.05), 0.5), Vector3(0, 0.035, 0.2), Vector3(0.15, 0, 0))
	# Cabinet top: chopsticks and cutlery in a cup, salt and soy sauce, a stack of disposable cutlery.
	var cup := _item(self, Vector3(3.78, c, 5.3), 0.0)
	_cy(cup, 0.04, 0.035, 0.12, _fin("porcelain", Color(0.3, 0.38, 0.5)), Vector3.ZERO, Vector3.ZERO, 20, false)
	var stick_cols := [Color(0.2, 0.08, 0.05), Color(0.2, 0.08, 0.05), Color(0.8, 0.7, 0.5), Color(0.8, 0.7, 0.5), Color(0.7, 0.7, 0.72)]
	for i in stick_cols.size():
		var a := TAU * i / stick_cols.size()
		_cy(cup, 0.003, 0.003, 0.23, _m(stick_cols[i], 0.4), Vector3(cos(a) * 0.012, 0.005, sin(a) * 0.012), Vector3(sin(a) * 0.1, 0, -cos(a) * 0.1), 6)
	var soy := _item(self, Vector3(4.24, c, 5.3), 0.0)
	_cy(soy, 0.032, 0.032, 0.17, _m(Color(0.2, 0.05, 0.02, 0.9), 0.15), Vector3.ZERO)
	_cy(soy, 0.015, 0.015, 0.03, _m(Color(0.8, 0.1, 0.1), 0.4), Vector3(0, 0.17, 0))
	_bxb(soy, Vector3(0.066, 0.06, 0.002), _paper(Color(0.95, 0.93, 0.88)), Vector3(0, 0.05, 0.033))
	_text(soy, "しょうゆ", Vector3(0, 0.08, 0.035), Vector3.ZERO, 0.00055, Color(0.1, 0.1, 0.1), 32)
	# Fridge door: garbage-day calendar under magnets, a takeout menu.
	_fridge_door()


func _rice_cooker(p: Node, base: Vector3, yaw: float) -> void:
	var n := _item(p, base, yaw)
	var white := _fin("plastic_white", Color(0.86, 0.86, 0.84))
	_cy(n, 0.125, 0.13, 0.17, white, Vector3.ZERO, Vector3.ZERO, 28)
	_sph(n, 0.125, Vector3(1.0, 0.35, 1.0), white, Vector3(0, 0.17, 0), Vector3.ZERO, true)
	_bx(n, Vector3(0.13, 0.06, 0.03), _fin("plastic_black"), Vector3(0, 0.1, 0.12))
	_bx(n, Vector3(0.05, 0.015, 0.004), _m(Color(0.3, 0.6, 0.9), 0.3), Vector3(-0.02, 0.11, 0.136))
	_bx(n, Vector3(0.12, 0.018, 0.03), white, Vector3(0, 0.19, 0.105))
	_cy(n, 0.02, 0.02, 0.006, _fin("plastic_grey"), Vector3(0, 0.205, -0.03))
	_bx(n, Vector3(0.2, 0.012, 0.03), _fin("plastic_grey"), Vector3(0, 0.23, -0.01))
	_bx(n, Vector3(0.012, 0.05, 0.03), _fin("plastic_grey"), Vector3(-0.1, 0.205, -0.01))
	_bx(n, Vector3(0.012, 0.05, 0.03), _fin("plastic_grey"), Vector3(0.1, 0.205, -0.01))
	_cable(n, [Vector3(0.0, 0.03, -0.13), Vector3(0.05, 0.0, -0.16), Vector3(0.15, -0.02, -0.15)], Color(0.1, 0.1, 0.1), 0.003)


func _fridge_door() -> void:
	var z := 4.735  # door face (fridge front faces north)
	var n := _item(self, Vector3(6.05, 1.02, z), FACE_N)
	_bx(n, Vector3(0.21, 0.297, 0.001), _paper(Color(0.97, 0.97, 0.95)), Vector3(0, 0, 0.001), Vector3(0, 0, 0.03))
	var cal := "ゴミ出しカレンダー\n\n月・木　燃やすごみ\n水　　　プラスチック\n金　　　缶・びん・ペット\n第2土　古紙・段ボール"
	_text(n, cal, Vector3(-0.0, -0.01, 0.0022), Vector3(0, 0, 0.03), 0.00042, Color(0.15, 0.25, 0.15), 36)
	_bx(n, Vector3(0.18, 0.025, 0.0015), _m(Color(0.25, 0.6, 0.3), 0.6), Vector3(0.004, 0.12, 0.0018), Vector3(0, 0, 0.03))
	for pos in [Vector3(-0.09, 0.13, 0.006), Vector3(0.1, 0.12, 0.006)]:
		_cy(n, 0.013, 0.013, 0.008, _m(Color(0.9, 0.2, 0.2), 0.3), pos - Vector3(0, 0, 0.004), Vector3(PI * 0.5, 0, 0))
	var menu := _item(self, Vector3(5.88, 0.75, z), FACE_N)
	_bx(menu, Vector3(0.15, 0.21, 0.001), _paper(Color(0.95, 0.88, 0.7)), Vector3(0, 0, 0.001), Vector3(0, 0, -0.06))
	_text(menu, "出前\nラーメン\n餃子", Vector3(0, 0.02, 0.0022), Vector3(0, 0, -0.06), 0.0008, Color(0.7, 0.1, 0.05), 40)
	_cy(menu, 0.012, 0.012, 0.008, _m(Color(0.2, 0.4, 0.85), 0.3), Vector3(0.0, 0.085, 0.002), Vector3(PI * 0.5, 0, 0))
	for pos in [Vector3(6.18, 1.3, z), Vector3(5.95, 1.38, z), Vector3(6.2, 0.6, z)]:
		var m := _item(self, pos, FACE_N)
		_bx(m, Vector3(0.04, 0.03, 0.008), _m(Color.from_hsv(rng.randf(), 0.6, 0.85), 0.3), Vector3(0, 0, 0.004))


# --- Living -----------------------------------------------------------------------

func _living() -> void:
	# Zabuton on the west side of the kotatsu, where he sits facing the TV, and a spare.
	_zabuton(Vector3(3.92, 0, 1.92), 0.1, Color(0.18, 0.22, 0.35))
	_zabuton(Vector3(4.62, 0, 2.56), 0.45, Color(0.45, 0.3, 0.22))
	# On the kotatsu: remote, mug, cans, tissues, the gamepad.
	var t := Y_KOTATSU
	_remote(self, Vector3(4.38, t, 2.12), 0.4)
	_mug(self, Vector3(4.33, t, 1.68), Color(0.9, 0.9, 0.88))
	_can(self, Vector3(4.82, t, 2.15), Color(0.85, 0.75, 0.2))
	_can(self, Vector3(4.9, t, 2.05), Color(0.82, 0.84, 0.86), true)
	_tissue_box(self, Vector3(4.8, t, 1.63), 1.3)
	_scan(self, "gamepad", Vector3(0.16, 0.16, 0.16), Vector3(4.47, t, 1.95), 1.9)
	# Floor around it: manga, a convenience-store bag, a magazine.
	_book_stack(self, Vector3(5.17, 0, 1.56), 6, Vector3(0.113, 0.016, 0.177), 0.3)
	_book_stack(self, Vector3(5.3, 0, 1.72), 3, Vector3(0.113, 0.016, 0.177), -0.4)
	_conbini_bag(self, Vector3(5.2, 0, 2.42), 0.8)
	_pet(self, Vector3(5.32, 0, 2.28), "tea", 0.3)
	var mag := _item(self, Vector3(3.95, 0, 2.45), 0.6)
	_bxb(mag, Vector3(0.21, 0.006, 0.28), _paper(Color(0.85, 0.85, 0.82)), Vector3.ZERO)
	_bxb(mag, Vector3(0.21, 0.001, 0.2), _m(Color(0.2, 0.3, 0.5), 0.4), Vector3(0, 0.006, 0.03))
	_text(mag, "週刊\nビジネス", Vector3(0, 0.0075, -0.09), Vector3(-PI * 0.5, 0, 0), 0.0009, Color(0.85, 0.1, 0.1), 40)
	# Game console in front of the TV stand, its cable running behind.
	_scan(self, "game_console", Vector3(0.32, 0.32, 0.32), Vector3(5.72, 0, 2.38), FACE_W + 0.08)
	_cable(self, [Vector3(5.85, 0.01, 2.38), Vector3(5.9, 0.01, 2.5), Vector3(5.92, 0.01, 2.6)], Color(0.05, 0.05, 0.05), 0.003)
	# The photo frame on the TV stand lies face down: it's a hidden spot (keepsake.gd).
	# Desk: papers from work, a mug, an energy drink, a binder, the succulent.
	var dsk := Y_DESK
	_scan(self, "notepads", Vector3(0.3, 0.3, 0.3), Vector3(5.98, dsk, 0.3), FACE_W + 0.2)
	_papers(self, Vector3(5.92, dsk, 0.78), FACE_W - 0.1, 4)
	_mug(self, Vector3(5.88, dsk, 0.98), Color(0.18, 0.3, 0.45))
	_can(self, Vector3(6.2, dsk, 0.26), Color(0.15, 0.15, 0.17), false, true)
	_scan(self, "binder", Vector3(0.3, 0.3, 0.3), Vector3(6.18, dsk, 0.78), FACE_W)
	_scan(self, "succulent", Vector3(0.13, 0.13, 0.13), Vector3(6.2, dsk, 1.0), 0.4)
	_cable(self, [Vector3(6.1, dsk + 0.005, 0.5), Vector3(6.25, dsk + 0.005, 0.42), Vector3(6.28, dsk, 0.4),
		Vector3(6.28, 0.3, 0.4), Vector3(6.27, 0.01, 0.45), Vector3(6.27, 0.01, 1.05)], Color(0.1, 0.1, 0.1), 0.0025)
	# Work bag on the floor by the desk.
	_briefcase(Vector3(5.62, 0, 1.18), FACE_W + 0.35)
	# Jacket thrown over the dining chair; dinner things on the dining table.
	_jacket_on_chair(Vector3(4.2, 0, 2.5))
	var dt := Y_DINING
	_bento(self, Vector3(4.12, dt, 3.12), 0.2)
	_bento(self, Vector3(4.15, dt + 0.031, 3.14), -0.15)
	_ramen(self, Vector3(4.38, dt, 2.9))
	_can(self, Vector3(4.42, dt, 3.25), Color(0.85, 0.75, 0.2))
	_can(self, Vector3(4.33, dt, 3.31), Color(0.75, 0.1, 0.12))
	_pet(self, Vector3(3.95, dt, 2.88), "tea", 0.6)
	_papers(self, Vector3(3.97, dt, 3.28), 0.4, 3, Vector2(0.148, 0.21), Color(0.95, 0.95, 0.97))
	# Delivery box (unopened) and an older one by the bookshelf.
	_scan(self, "cardboard_box", Vector3(0.42, 0.32, 0.32), Vector3(3.12, 0, 2.48), 0.2)
	_scan(self, "cardboard_box", Vector3(0.3, 0.22, 0.24), Vector3(3.14, 0.32, 2.5), -0.25)
	# A tired electric fan nobody put away after summer.
	_fan(Vector3(5.62, 0, 3.42), FACE_N + 0.6)
	# Wall calendar on the east wall, still on October.
	_wall_calendar(Vector3(6.293, 1.55, 2.86), FACE_W)


func _zabuton(pos: Vector3, yaw: float, col: Color) -> void:
	var n := _item(self, pos, yaw)
	var f := _fab(col)
	_bxb(n, Vector3(0.53, 0.035, 0.57), f, Vector3.ZERO)
	_sph(n, 0.28, Vector3(0.95, 0.09, 1.0), f, Vector3(0, 0.035, 0))
	_cy(n, 0.012, 0.012, 0.03, _fab(col.darkened(0.3)), Vector3(0, 0.045, 0))


func _briefcase(pos: Vector3, yaw: float) -> void:
	var n := _item(self, pos, yaw, Vector3(-0.12, 0, 0))
	var leather := _m(Color(0.03, 0.03, 0.035), 0.55, 0.0, 0.2)
	_bxb(n, Vector3(0.4, 0.29, 0.1), leather, Vector3.ZERO)
	_bxb(n, Vector3(0.38, 0.18, 0.012), leather, Vector3(0, 0.1, 0.056))
	_bx(n, Vector3(0.38, 0.004, 0.103), _m(Color(0.15, 0.15, 0.16), 0.5), Vector3(0, 0.285, 0))
	_torus(n, 0.04, 0.05, leather, Vector3(0, 0.285, 0), Vector3(PI * 0.5, 0, 0)).scale = Vector3(1.3, 1, 1)
	_bx(n, Vector3(0.05, 0.03, 0.008), _fin("stainless"), Vector3(0, 0.2, 0.063))


func _jacket_on_chair(chair: Vector3) -> void:
	# The chair (facing south, 0.85 tall) has its back on the north side.
	var n := _item(self, chair + Vector3(0.02, 0.8, -0.19), 0.08)
	var f := _fab(Color(0.16, 0.17, 0.21))
	_cy(n, 0.022, 0.022, 0.4, f, Vector3(-0.2, 0.02, 0), Vector3(0, 0, -PI * 0.5), 12)
	_ext(n, PackedVector2Array([Vector2(-0.2, 0.03), Vector2(0.2, 0.03), Vector2(0.22, -0.3), Vector2(0.17, -0.42),
		Vector2(-0.17, -0.42), Vector2(-0.22, -0.3)]), 0.012, f, Vector3(0, 0, -0.04), Vector3(0.1, 0, 0))
	_ext(n, PackedVector2Array([Vector2(-0.2, 0.03), Vector2(0.2, 0.03), Vector2(0.21, -0.22), Vector2(0.03, -0.3),
		Vector2(-0.21, -0.24)]), 0.012, f, Vector3(0, 0, 0.035), Vector3(-0.08, 0, 0))
	_bx(n, Vector3(0.07, 0.36, 0.03), f, Vector3(-0.25, -0.2, -0.05), Vector3(0.1, 0, 0.1))
	# A tie slung over it.
	_bx(n, Vector3(0.04, 0.34, 0.004), _fab(Color(0.4, 0.08, 0.1)), Vector3(0.09, -0.15, 0.048), Vector3(-0.08, 0, 0.05))


func _fan(pos: Vector3, yaw: float) -> void:
	var n := _item(self, pos, yaw)
	var white := _fin("plastic_white", Color(0.85, 0.85, 0.83))
	_cy(n, 0.12, 0.14, 0.04, white, Vector3.ZERO, Vector3.ZERO, 24)
	_cy(n, 0.015, 0.015, 0.75, white, Vector3(0, 0.04, -0.03))
	_bx(n, Vector3(0.08, 0.02, 0.05), _m(Color(0.3, 0.6, 0.9), 0.4), Vector3(0, 0.05, 0.08))
	_cy(n, 0.055, 0.06, 0.12, white, Vector3(0, 0.8, -0.1), Vector3(PI * 0.5, 0, 0))
	var cage := _clear(Color(0.92, 0.92, 0.9, 0.35))
	_cy(n, 0.17, 0.17, 0.08, cage, Vector3(0, 0.8, 0.02), Vector3(PI * 0.5, 0, 0), 28)
	_torus(n, 0.165, 0.178, white, Vector3(0, 0.8, 0.06), Vector3(PI * 0.5, 0, 0))
	for i in 5:
		var b := _node(n, Vector3(0, 0.8, 0.055), 0.0, Vector3(0, 0, TAU * i / 5.0))
		_bx(b, Vector3(0.07, 0.13, 0.004), _m(Color(0.75, 0.88, 0.95, 0.7), 0.3), Vector3(0, 0.075, 0), Vector3(0.3, 0, 0))
	_cy(n, 0.03, 0.03, 0.03, white, Vector3(0, 0.8, 0.06), Vector3(PI * 0.5, 0, 0))
	_cable(n, [Vector3(0, 0.01, -0.13), Vector3(0.1, 0.005, -0.3), Vector3(0.35, 0.005, -0.35)], Color(0.9, 0.9, 0.88), 0.003)


func _wall_calendar(pos: Vector3, yaw: float) -> void:
	var n := _item(self, pos, yaw)
	_cy(n, 0.004, 0.004, 0.004, _fin("stainless"), Vector3(0, 0.25, 0.0), Vector3(PI * 0.5, 0, 0))
	_bx(n, Vector3(0.3, 0.46, 0.003), _paper(Color(0.97, 0.97, 0.96)), Vector3(0, 0.0, 0.002))
	_bx(n, Vector3(0.3, 0.2, 0.001), _m(Color(0.35, 0.55, 0.65), 0.6), Vector3(0, 0.12, 0.004))  # photo: sea, sky
	_bx(n, Vector3(0.3, 0.08, 0.001), _m(Color(0.55, 0.7, 0.85), 0.6), Vector3(0, 0.18, 0.0045))
	_text(n, "10  OCTOBER", Vector3(0, 0.0, 0.005), Vector3.ZERO, 0.0011, Color(0.15, 0.15, 0.15), 32)
	var grid := ""
	var day := -2  # 2026-10-01 is a Thursday
	for row in 5:
		var line := ""
		for col in 7:
			day += 1
			line += ("%2d " % day) if day >= 1 and day <= 31 else "   "
		grid += line + "\n"
	_text(n, grid, Vector3(0, -0.13, 0.005), Vector3.ZERO, 0.00085, Color(0.25, 0.25, 0.25), 32)
	_text(n, "〆切", Vector3(0.085, -0.155, 0.006), Vector3(0, 0, 0.1), 0.0007, Color(0.85, 0.1, 0.1), 32)


# --- Bedroom ---------------------------------------------------------------------

func _bedroom() -> void:
	# Duvet thrown back in a heap on the bed, a second pillow askew.
	var bed := _item(self, Vector3(0.69, 0.45, 1.25), 0.0)
	var duvet := _fab(Color(0.42, 0.5, 0.62))
	_sph(bed, 0.3, Vector3(1.6, 0.22, 0.9), duvet, Vector3(0.02, 0.0, 0.05), Vector3(0, 0.25, 0))
	_sph(bed, 0.24, Vector3(1.5, 0.28, 0.9), duvet, Vector3(-0.12, 0.02, 0.32), Vector3(0, -0.4, 0.05))
	_sph(bed, 0.2, Vector3(1.4, 0.22, 1.0), duvet, Vector3(0.22, 0.0, 0.38), Vector3(0, 0.7, 0))
	_sph(bed, 0.16, Vector3(1.3, 0.25, 1.0), _fab(Color(0.86, 0.87, 0.88)), Vector3(-0.2, 0.0, -0.2), Vector3(0, 0.9, 0))
	# Phone charger running from the bedside table to the socket.
	_cable(self, [Vector3(1.48, Y_SIDE_TABLE + 0.004, 0.5), Vector3(1.5, Y_SIDE_TABLE + 0.002, 0.52), Vector3(1.53, Y_SIDE_TABLE, 0.53),
		Vector3(1.54, 0.25, 0.54), Vector3(1.6, 0.01, 0.6), Vector3(1.78, 0.01, 0.35), Vector3(1.8, 0.01, 0.1), Vector3(1.8, 0.23, 0.085)])
	# Clothes on the floor by the foot of the bed: yesterday's shirt, jeans, socks.
	var pile := _item(self, Vector3(1.55, 0, 2.45), 0.4)
	_sph(pile, 0.22, Vector3(1.2, 0.22, 0.9), _fab(Color(0.2, 0.25, 0.4)), Vector3(0, 0.03, 0))
	_sph(pile, 0.2, Vector3(1.1, 0.25, 0.8), _fab(Color(0.85, 0.87, 0.9)), Vector3(0.12, 0.06, 0.08), Vector3(0, 0.8, 0))
	_sph(pile, 0.05, Vector3(1.6, 0.4, 0.7), _fab(Color(0.08, 0.08, 0.09)), Vector3(-0.25, 0.01, 0.15))
	_sph(pile, 0.05, Vector3(1.6, 0.4, 0.7), _fab(Color(0.08, 0.08, 0.09)), Vector3(-0.3, 0.01, 0.25), Vector3(0, 1.0, 0))
	# Hanger rack in the corner by the closet: suits and shirts for the week.
	var rack := _item(self, Vector3(2.28, 0, 3.32), 0.0)
	var chrome := _fin("chrome")
	for x in [-0.36, 0.36]:
		_cy(rack, 0.012, 0.012, 1.6, chrome, Vector3(x, 0.05, 0))
		_rod(rack, Vector3(x, 0.04, -0.22), Vector3(x, 0.04, 0.22), 0.012, chrome)
		for z in [-0.22, 0.22]:
			_cy(rack, 0.02, 0.02, 0.04, _fin("plastic_black"), Vector3(x, 0.0, z))
	_rod(rack, Vector3(-0.37, 1.62, 0), Vector3(0.37, 1.62, 0), 0.012, chrome)
	var hung := [["jacket", Color(0.1, 0.11, 0.14)], ["trousers", Color(0.1, 0.11, 0.14)], ["jacket", Color(0.22, 0.23, 0.25)],
		["shirt", Color(0.92, 0.93, 0.95)], ["shirt", Color(0.75, 0.83, 0.92)], ["shirt", Color(0.92, 0.93, 0.95)], ["hoodie", Color(0.45, 0.46, 0.48)]]
	for i in hung.size():
		_hanger(rack, Vector3(-0.3 + i * 0.095, 1.645, 0), FACE_E + _j(0.12), hung[i][0], hung[i][1])
	# Full-length mirror leaning on the west wall.
	var mirror := _item(self, Vector3(0.12, 0, 2.6), FACE_E, Vector3(-0.12, 0, 0))
	_bxb(mirror, Vector3(0.36, 1.5, 0.025), _m(Color(0.3, 0.2, 0.12), 0.5), Vector3.ZERO)
	_bxb(mirror, Vector3(0.32, 1.46, 0.004), _fin("mirror"), Vector3(0, 0.02, 0.013))
	# Room-dried laundry hanging from the curtain rail (部屋干し).
	_pinch_hanger(self, Vector3(1.72, 2.02, 0.3), 0.05)
	_hanger(self, Vector3(1.22, 2.02, 0.3), FACE_E + 0.1, "shirt", Color(0.92, 0.93, 0.95))
	# Business books and an old laptop bag under the window.
	_book_stack(self, Vector3(1.97, 0, 0.32), 4, Vector3(0.13, 0.025, 0.188), 0.2)
	_scan(self, "stationery", Vector3(0.22, 0.22, 0.22), Vector3(1.55, Y_SIDE_TABLE, 0.22), FACE_S - 0.4)


# --- Washroom ---------------------------------------------------------------------

func _washroom() -> void:
	# Towel bar on the wall shared with the bedroom.
	var bar := _item(self, Vector3(1.25, 1.12, 3.69), FACE_S)
	_rod(bar, Vector3(-0.3, 0, 0.05), Vector3(0.3, 0, 0.05), 0.009, _fin("stainless"))
	for x in [-0.3, 0.3]:
		_rod(bar, Vector3(x, 0, 0.0), Vector3(x, 0, 0.05), 0.008, _fin("stainless"))
	for t in [[-0.15, Color(0.75, 0.78, 0.82)], [0.14, Color(0.92, 0.9, 0.84)]]:
		var tw := _node(bar, Vector3(t[0], 0, 0.05), _j(0.05))
		var f := _fab(t[1])
		_cy(tw, 0.016, 0.016, 0.3, f, Vector3(-0.15, 0.0, 0), Vector3(0, 0, -PI * 0.5))
		_bx(tw, Vector3(0.3, 0.36, 0.01), f, Vector3(0, -0.18, 0.012))
		_bx(tw, Vector3(0.3, 0.28, 0.01), f, Vector3(0, -0.14, -0.012))
	# Laundry hamper with clothes spilling over, next to the bath door.
	_scan(self, "hamper", Vector3(0.48, 0.48, 0.48), Vector3(1.9, 0, 5.12), 0.3)
	var top := _item(self, Vector3(1.9, 0.09, 5.12), 0.3)
	_sph(top, 0.16, Vector3(1.0, 0.3, 0.75), _fab(Color(0.85, 0.87, 0.9)), Vector3(-0.03, 0.0, 0))
	_sph(top, 0.1, Vector3(1.3, 0.3, 0.8), _fab(Color(0.1, 0.1, 0.12)), Vector3(0.06, 0.03, 0.03), Vector3(0, 0.6, 0))
	_sph(top, 0.08, Vector3(1.4, 0.3, 0.8), _fab(Color(0.45, 0.47, 0.5)), Vector3(-0.08, 0.04, -0.04), Vector3(0, -0.4, 0))
	# Washing machine lid: detergent, bleach, a net bag.
	var w := Y_WASHER
	var det := _item(self, Vector3(0.22, w, 5.12), FACE_E + 0.2)
	_bxb(det, Vector3(0.1, 0.24, 0.16), _m(Color(0.25, 0.45, 0.85), 0.35), Vector3.ZERO)
	_cy(det, 0.025, 0.025, 0.03, _fin("plastic_white"), Vector3(0, 0.24, 0.03))
	_bx(det, Vector3(0.02, 0.07, 0.06), _m(Color(0.25, 0.45, 0.85), 0.35), Vector3(0, 0.2, -0.08))
	_bx(det, Vector3(0.101, 0.1, 0.12), _m(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, 0.1, 0.0))
	_text(det, "洗たく\n洗剤", Vector3(0.052, 0.11, 0.0), Vector3(0, PI * 0.5, 0), 0.0009, Color(0.15, 0.35, 0.8), 40)
	_scan(self, "bleach", Vector3(0.25, 0.25, 0.25), Vector3(0.24, w, 4.82), 0.4)
	var net := _item(self, Vector3(0.45, w, 4.95), 0.3)
	_sph(net, 0.09, Vector3(1.0, 0.35, 0.8), _m(Color(0.95, 0.95, 0.95, 0.6), 0.8), Vector3(0, 0.02, 0))
	# Vanity basin counter: toothbrush cup, paste, razor, hand soap.
	var v := 0.8
	var cup := _item(self, Vector3(0.24, v, 3.83), 0.0)
	_cy(cup, 0.035, 0.03, 0.1, _m(Color(0.75, 0.88, 0.95, 0.55), 0.2), Vector3.ZERO, Vector3.ZERO, 16, false)
	_cy(cup, 0.03, 0.03, 0.003, _m(Color(0.75, 0.88, 0.95, 0.55), 0.2), Vector3.ZERO)
	_cy(cup, 0.005, 0.005, 0.19, _m(Color(0.2, 0.5, 0.9), 0.4), Vector3(0.006, 0.005, 0), Vector3(0, 0, -0.2), 8)
	_bx(cup, Vector3(0.012, 0.025, 0.01), _m(Color(0.95, 0.95, 0.95), 0.9), Vector3(0.047, 0.19, 0.0), Vector3(0, 0, -0.2))
	var paste := _item(self, Vector3(0.25, v, 3.95), FACE_E + 0.4)
	_cy(paste, 0.016, 0.016, 0.16, _m(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, 0.016, 0.08), Vector3(PI * 0.5, 0, 0)).scale = Vector3(1, 1, 0.55)
	_bx(paste, Vector3(0.032, 0.006, 0.05), _m(Color(0.1, 0.4, 0.85), 0.4), Vector3(0, 0.022, 0.02))
	var soap := _item(self, Vector3(0.22, v, 4.38), 0.0)
	_cy(soap, 0.035, 0.035, 0.13, _m(Color(0.95, 0.95, 0.9, 0.8), 0.2), Vector3.ZERO)
	_cy(soap, 0.01, 0.01, 0.04, _fin("plastic_white"), Vector3(0, 0.13, 0))
	_bx(soap, Vector3(0.012, 0.012, 0.05), _fin("plastic_white"), Vector3(0, 0.17, 0.02))
	var razor := _item(self, Vector3(0.28, v, 4.25), 0.5)
	_bxb(razor, Vector3(0.012, 0.01, 0.13), _m(Color(0.15, 0.2, 0.3), 0.3), Vector3.ZERO)
	_bxb(razor, Vector3(0.04, 0.012, 0.012), _fin("chrome"), Vector3(0, 0.0, 0.07))
	# Bath mat in front of the bath door.
	_bxb(self, Vector3(0.6, 0.012, 0.4), _fab(Color(0.55, 0.62, 0.58)), Vector3(1.15, 0, 5.18), Vector3(0, 0.06, 0))


# --- Unit bath --------------------------------------------------------------------

func _bath() -> void:
	# Bath stool and washbowl (風呂椅子・洗面器).
	var stool := _item(self, Vector3(0.48, 0, 6.05), 0.25)
	var pl := _m(Color(0.88, 0.9, 0.92), 0.3)
	_bxb(stool, Vector3(0.32, 0.03, 0.24), pl, Vector3(0, 0.22, 0))
	for x in [-0.14, 0.14]:
		_bxb(stool, Vector3(0.025, 0.22, 0.22), pl, Vector3(x, 0, 0))
	var bowl := _item(self, Vector3(0.48, 0.25, 6.05), -0.2)
	_cy(bowl, 0.14, 0.11, 0.09, _m(Color(0.88, 0.9, 0.92), 0.3), Vector3.ZERO, Vector3.ZERO, 28, false)
	_cy(bowl, 0.11, 0.11, 0.003, _m(Color(0.88, 0.9, 0.92), 0.3), Vector3.ZERO)
	# Shampoo, conditioner and body soap pump bottles in the corner.
	var cols := [Color(0.1, 0.1, 0.12), Color(0.9, 0.9, 0.88), Color(0.85, 0.5, 0.65)]
	for i in cols.size():
		var b := _item(self, Vector3(0.18 + i * 0.09, 0, 5.62 + (i % 2) * 0.03), _j(0.6))
		_cy(b, 0.035, 0.037, 0.2, _m(cols[i], 0.3), Vector3.ZERO)
		_cy(b, 0.012, 0.012, 0.04, _fin("plastic_white"), Vector3(0, 0.2, 0))
		_bx(b, Vector3(0.014, 0.012, 0.055), _fin("plastic_white"), Vector3(0, 0.245, 0.02))
	_scan(self, "spray_cleaner", Vector3(0.25, 0.25, 0.25), Vector3(1.6, 0, 6.33), -0.5)


# --- Toilet ------------------------------------------------------------------------

func _toilet() -> void:
	# Toilet slippers by the door, toes pointing out for the next visit.
	_sandal(self, Vector3(2.38, 0, 5.88), FACE_E + 0.1, Color(0.6, 0.65, 0.55), true)
	_sandal(self, Vector3(2.4, 0, 6.02), FACE_E - 0.05, Color(0.6, 0.65, 0.55), true)
	# 12-roll pack in the corner, one roll already gone.
	var pack := _item(self, Vector3(2.0, 0, 5.66), 0.1)
	var roll := _m(Color(0.97, 0.97, 0.96), 0.9)
	var core := _m(Color(0.6, 0.48, 0.32), 0.9)
	var i := 0
	for layer in 2:
		for row in 2:
			for col in 3:
				i += 1
				if i == 12:
					continue
				var b := Vector3(-0.11 + col * 0.11, layer * 0.115, -0.055 + row * 0.11)
				_cy(pack, 0.054, 0.054, 0.113, roll, b)
				_cy(pack, 0.02, 0.02, 0.114, core, b - Vector3(0, 0.0005, 0))
	_bxb(pack, Vector3(0.34, 0.235, 0.23), _m(Color(0.95, 0.97, 1.0, 0.18), 0.2), Vector3(0, 0, 0))
	_bx(pack, Vector3(0.16, 0.05, 0.002), _m(Color(0.3, 0.55, 0.85), 0.5), Vector3(0, 0.15, 0.117))
	_scan(self, "plunger", Vector3(0.42, 0.42, 0.42), Vector3(2.6, 0, 7.08), 0.3, Vector3(0.0, 0, 0.12))


# --- Balcony ---------------------------------------------------------------------

func _balcony() -> void:
	var pole_y := 2.05 + 0.015
	_hanger(self, Vector3(2.3, pole_y, -0.9), FACE_E + 0.08, "shirt", Color(0.92, 0.93, 0.95))
	_hanger(self, Vector3(2.45, pole_y, -0.9), FACE_E - 0.05, "shirt", Color(0.92, 0.93, 0.95))
	_hanger(self, Vector3(2.62, pole_y, -0.9), FACE_E, "towel", Color(0.6, 0.72, 0.8))
	_pinch_hanger(self, Vector3(1.4, pole_y, -0.9), 0.0)
	# A clay pot with what's left of a herb, and the sandals by the sliding door.
	_scan(self, "clay_pot", Vector3(0.24, 0.24, 0.24), Vector3(3.15, -0.02, -1.28), 0.0)
	var dead := _item(self, Vector3(3.15, 0.17, -1.28), 0.0)
	for k in 5:
		_cy(dead, 0.002, 0.003, rng.randf_range(0.12, 0.22), _m(Color(0.42, 0.33, 0.2), 0.9), Vector3(_j(0.04), 0, _j(0.04)),
			Vector3(_j(0.4), 0, _j(0.4)), 5)
	_sandal(self, Vector3(4.05, -0.02, -0.38), FACE_S + 0.25, Color(0.2, 0.22, 0.25))
	_sandal(self, Vector3(4.16, -0.02, -0.4), FACE_S + 0.05, Color(0.2, 0.22, 0.25))
	# Air-con pipe cover from the sleeve above the window down to the outdoor unit.
	var duct := _fin("plastic_white", Color(0.84, 0.82, 0.76))
	_bx(self, Vector3(1.2, 0.075, 0.06), duct, Vector3(5.47, 2.2, -0.11))
	_bx(self, Vector3(0.075, 2.0, 0.06), duct, Vector3(6.04, 1.2, -0.11))
	_bx(self, Vector3(0.075, 0.06, 1.12), duct, Vector3(6.04, 0.2, -0.64))
	_bx(self, Vector3(0.16, 0.06, 0.075), duct, Vector3(5.95, 0.2, -1.2))
	_cable(self, [Vector3(5.85, 0.08, -1.2), Vector3(5.95, 0.01, -1.25), Vector3(6.05, 0.0, -1.38)], Color(0.55, 0.55, 0.52), 0.008)
	_scan(self, "broom", Vector3(0.3, 1.2, 0.3), Vector3(6.25, -0.02, -0.25), 0.0, Vector3(0, 0, 0.12))


# --- Switches and sockets -------------------------------------------------------

func _wall_fittings() -> void:
	_switch_plate(self, Vector3(3.59, 1.2, 6.15), FACE_W, 2)      # genkan + hall
	_switch_plate(self, Vector3(2.78, 1.2, 4.62), FACE_E, 2)      # washroom (outside the door)
	_switch_plate(self, Vector3(2.78, 1.2, 5.5), FACE_E, 1)       # toilet
	_switch_plate(self, Vector3(3.6, 1.2, 3.59), FACE_N, 2)       # LDK, by the door
	_switch_plate(self, Vector3(2.68, 1.2, 2.85), FACE_W, 1)      # bedroom
	_switch_plate(self, Vector3(3.69, 1.2, 4.2), FACE_E, 1)       # kitchen
	_socket(self, Vector3(1.8, 0.25, 0.075), FACE_S)              # bedside
	_socket(self, Vector3(6.295, 0.25, 2.72), FACE_W)             # TV
	_socket(self, Vector3(6.295, 0.25, 1.1), FACE_W)              # desk
	_socket(self, Vector3(3.69, 0.25, 4.85), FACE_E)              # kitchen rack
	_socket(self, Vector3(2.68, 0.25, 4.95), FACE_W)              # washroom
	_cable(self, [Vector3(3.87, 0.86, 4.32), Vector3(3.75, 0.6, 4.4), Vector3(3.71, 0.4, 4.6), Vector3(3.7, 0.25, 4.82)], Color(0.1, 0.1, 0.1), 0.003)
