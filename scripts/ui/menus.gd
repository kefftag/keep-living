extends RefCounted
## Front-end screens, built in code on the HUD: the title screen over the live
## apartment, scenario select, settings and credits. The title is its own
## full-screen layout; the others reuse the HUD's sign overlay so they look
## the same from the title and from the pause menu.

const UI := preload("res://scripts/ui/ui_style.gd")
const Scenarios := preload("res://scripts/data/scenarios.gd")
const Perks := preload("res://scripts/data/perks.gd")
const Story := preload("res://scripts/data/story.gd")

## Where the camera sits behind the title: the LDK, looking at the balcony glass.
const TITLE_POS := Vector3(5.7, 0.05, 3.25)
const TITLE_LOOK := Vector3(3.6, 1.25, -0.6)

const TEXTURE_CREDITS := [
	"laminate_floor_03", "rubber_tiles", "floor_tiles_04", "anti_skid_tiles", "concrete_floor_worn_001",
	"concrete_wall_008", "long_white_tiles", "oak_veneer_01", "cherry_veneer", "black_walnut_veneer_01", "rough_linen",
]
const MODEL_CREDITS := [
	"metal_toolbox", "side_table_01", "exterior_aircon_unit", "steel_frame_shelves_01", "dining_chair_02",
	"baseball_bat", "binoculars", "classic_laptop", "television_02", "alarm_clock_01", "vintage_electric_kettle",
	"plastic_bottle_gallon", "trashbag", "rubber_boots", "cardboard_box_01", "potted_plant_02", "wall_clock",
	"russian_food_cans_01", "plastic_broom", "desk_lamp_arm_01", "throw_pillows_01",
]


# --- Title ---------------------------------------------------------------------

static func show_title(hud) -> void:
	hud.overlay.visible = false
	hud.overlay_kind = "title"
	hud._set_front_end(true)
	hud.get_tree().paused = true
	hud._capture_mouse(false)
	_pose_camera(hud)
	if is_instance_valid(hud.title_root):
		hud.title_root.queue_free()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.root.add_child(root)
	hud.title_root = root

	if Meta.true_ending:
		# After the true ending the flat is lit by plain morning sun.
		root.add_child(_sun_wash())
	# Dark wash on the left so the type reads; the apartment shows on the right.
	root.add_child(side_wash())
	# A black poster band along the bottom (the Metro manner-poster footer).
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UI.band_box(14))
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -64
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	band.add_child(foot)
	var stats := "Lives %d   ·   Rescues %d   ·   Echoes %d / %d" % [Meta.runs, Meta.wins, Meta.perks.size(), Perks.PERKS.size()]
	foot.add_child(hud._label(stats, UI.FS_HUD, UI.SIGN_YELLOW))
	foot.add_child(hud._expander())
	foot.add_child(hud._label("v%s   ·   Made with Godot" % ProjectSettings.get_setting("application/config/version", "0.1"), UI.FS_HUD, UI.PAPER))

	var col := VBoxContainer.new()
	col.position = Vector2(88, 70)
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var place := UI.sticker("東京都 · 3F · 1LDK")
	place.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(place)
	col.add_child(hud._spacer(0))
	var jp := UI.poster_label("生きていく", 118, UI.SIGN_YELLOW, 12, UI.WHITE, 5)
	col.add_child(jp)
	var en := UI.poster_label("KEEP LIVING", 58, UI.WHITE, 8, UI.ALERT_RED, 0)
	col.add_child(en)
	var tag = hud._label("Survive the end of the world from inside your Tokyo apartment.", 22, UI.PAPER)
	col.add_child(tag)
	if Scenarios.monday_unlocked() and not Meta.true_ending:
		# The final scenario has opened (docs/STORY.md): a quiet nudge.
		var nudge = hud._label(Scenarios.MONDAY.TAGLINE, 24, UI.SIGN_YELLOW)
		nudge.add_theme_font_override("font", UI.hand_font())
		col.add_child(hud._spacer(0))
		col.add_child(nudge)

	var menu := VBoxContainer.new()
	menu.position = Vector2(88, 410)
	menu.add_theme_constant_override("separation", 10)
	root.add_child(menu)
	var s: Script = Game.scenario
	var cont := "続ける   Continue: %s" % s.TITLE if Meta.runs_in(s.ID) > 0 else "はじめる   New life: %s" % s.TITLE
	var first := _menu_button(hud, cont, func(): hud._title_play(Game.scenario.ID), true)
	menu.add_child(first)
	menu.add_child(_menu_button(hud, "シナリオ   Scenario select", hud._show_scenarios))
	menu.add_child(_menu_button(hud, "設定   Settings", func(): hud._show_settings(hud._show_title)))
	menu.add_child(_menu_button(hud, "クレジット   Credits", func(): hud._show_credits(hud._show_title)))
	menu.add_child(_menu_button(hud, "終了   Quit", func(): hud.get_tree().quit()))
	first.grab_focus.call_deferred()

	# Current scenario plate, top right: a red header block over a white sign face.
	var plate := UI.sign_panel(0)
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.position = Vector2(-40, 40)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.custom_minimum_size = Vector2(360, 0)
	root.add_child(plate)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 0)
	UI.sign_face(plate).add_child(pv)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UI.header_box(UI.ALERT_RED))
	head.add_child(hud._bilingual(s.TITLE_JP, "SCENARIO: " + s.TITLE.to_upper(), 40, UI.FS_NOTE, UI.WHITE, UI.WHITE))
	pv.add_child(head)
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 14)
	pv.add_child(body)
	var plate_text := "%s\nBest: day %d   Clues %d / %d" % [s.TAGLINE, Meta.best_day_in(s.ID),
		Meta.known_clue_list(s.ID).size(), s.CLUES.size()]
	if s == Scenarios.MONDAY:
		plate_text = "%s\nMemories %d / %d%s" % [s.TAGLINE, Meta.memories.size(), Story.FRAGMENTS.size(),
			"   完  Finished" if Meta.true_ending else ""]
	var bl = hud._label(plate_text, UI.FS_HUD, UI.INK)
	bl.add_theme_constant_override("outline_size", 0)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(330, 0)
	body.add_child(bl)


static func _menu_button(hud, text: String, cb: Callable, primary := false) -> Button:
	var b: Button = hud._button(text, cb)
	b.custom_minimum_size = Vector2(500, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 26)
	if primary:
		b.add_theme_stylebox_override("normal", UI.box(UI.ALERT_RED, Color(1, 1, 1, 0.2)))
		b.add_theme_stylebox_override("hover", UI.box(UI.ALERT_RED.lightened(0.1), UI.SIGN_YELLOW))
		b.add_theme_stylebox_override("focus", UI.box(UI.ALERT_RED.lightened(0.1), UI.SIGN_YELLOW))
	for k in ["normal", "hover", "focus", "pressed"]:
		var sb = b.get_theme_stylebox(k)
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			sb.content_margin_left = 22
			b.add_theme_stylebox_override(k, sb)
	return b


## Dark wash on the left so type reads over the flat (title, credits roll).
static func side_wash() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.06, 0.94))
	g.set_color(1, Color(0.02, 0.03, 0.06, 0.0))
	g.add_point(0.55, Color(0.02, 0.03, 0.06, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	wash.offset_right = 1150
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return wash


## Warm, flat morning light over the right of the title once Monday is finished.
static func _sun_wash() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.7, 0.0))
	g.set_color(1, Color(1.0, 0.92, 0.74, 0.34))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.3, 1.0)
	gt.fill_to = Vector2(1.0, 0.0)
	gt.width = 128
	gt.height = 128
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return wash


static func hide_title(hud) -> void:
	if is_instance_valid(hud.title_root):
		hud.title_root.queue_free()
	hud.title_root = null


static func pose_title_camera(hud) -> void:
	_pose_camera(hud)


static func _pose_camera(hud) -> void:
	var p = hud.player
	if p == null:
		return
	p.global_position = TITLE_POS
	var eye: Vector3 = TITLE_POS + Vector3(0, p.EYE_HEIGHT, 0)
	var d := TITLE_LOOK - eye
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	hud.set_meta("title_yaw", p.rotation.y)


## The wake-up spot main.gd uses: next to the bed, facing the phone.
static func restore_camera(hud) -> void:
	var p = hud.player
	if p == null:
		return
	p.global_position = Vector3(1.75, 0.05, 1.15)
	p.rotation.y = 0.0
	p.head.rotation.x = 0.0


# --- Scenario select -----------------------------------------------------------

static func show_scenarios(hud) -> void:
	hide_title(hud)
	hud._open("scenarios", "シナリオ", "Scenario select")
	hud.overlay_box.add_child(hud._label("Each scenario keeps its own clues, theory and records. Echoes carry over between all of them.", UI.FS_NOTE, hud.oc_dim))
	var first_play: Button = null
	for s in Scenarios.ALL:
		var reason := Scenarios.lock_reason_for(s)
		var rec := "Lives %d   ·   Best day %d   ·   Rescues %d   ·   Clues %d / %d" % [Meta.runs_in(s.ID), Meta.best_day_in(s.ID),
			Meta.wins_in(s.ID), Meta.known_clue_list(s.ID).size(), s.CLUES.size()]
		if s == Scenarios.MONDAY:
			if reason != "":
				continue  # the final scenario stays a secret until it opens
			rec = "Memories %d / %d%s" % [Meta.memories.size(), Story.FRAGMENTS.size(), "   ·   完  Finished" if Meta.true_ending else ""]
		var sid: String = s.ID
		var b := _card(hud, s.TITLE_JP, s.TITLE, s.TAGLINE, s.BLURB, rec, reason, func(): hud._title_play(sid), s == Game.scenario)
		if b and first_play == null:
			first_play = b
	for u in Scenarios.UPCOMING:
		var reason := Scenarios.lock_reason(u["unlock_after_win"])
		if reason == "":
			reason = "In development. Coming in a future update."
		_card(hud, u["title_jp"], u["title"], "", u["blurb"], "", reason, Callable(), false)
	hud.overlay_box.add_child(hud._button("戻る  Back  [%s]" % Game.glyph("back"), hud._show_title))
	hud._fit_overlay()


static func _card(hud, jp: String, en: String, tagline: String, blurb: String, rec: String, lock: String, play: Callable, current: bool) -> Button:
	var card := PanelContainer.new()
	var edge := UI.JR_GREEN if current else (UI.SIGN_DIM if lock != "" else UI.STEEL_DARK)
	var sb := UI.box(Color(1, 1, 1, 0.0) if lock == "" else Color(0, 0, 0, 0.05), edge, 0, 0)
	sb.set_border_width_all(3 if current else 1)
	card.add_theme_stylebox_override("panel", sb)
	hud.overlay_box.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", UI.header_box(UI.SIGN_DIM if lock != "" else UI.ALERT_RED))
	block.custom_minimum_size = Vector2(150, 0)
	var jl := UI.poster_label(jp, 44, UI.WHITE if lock == "" else UI.STEEL_LIGHT, 0, UI.WHITE, 0)
	jl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block.add_child(jl)
	row.add_child(block)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	for side in ["top", "bottom", "right"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	row.add_child(m)
	var title := en.to_upper() + ("   (current)" if current else "")
	v.add_child(hud._heading(title, 28, hud.oc_text if lock == "" else hud.oc_dim))
	if tagline != "":
		v.add_child(hud._label(tagline, UI.FS_NOTE, hud.oc_accent))
	var bl: Label = hud._text(blurb, UI.FS_BODY, hud.oc_text if lock == "" else hud.oc_dim)
	bl.add_theme_constant_override("line_spacing", 6)
	bl.custom_minimum_size = Vector2(580, 0)
	v.add_child(bl)
	if rec != "":
		v.add_child(hud._label(rec, UI.FS_NOTE, hud.oc_dim))
	if lock != "":
		v.add_child(hud._label("施錠  LOCKED: " + lock, UI.FS_NOTE, UI.SIGN_WARN))
		return null
	var b: Button = hud._button("この人生を始める   Play %s" % en, play)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(b)
	return b


# --- Settings --------------------------------------------------------------------

static func show_settings(hud, back: Callable) -> void:
	hide_title(hud)
	hud._open("settings", "設定", "Settings")
	hud.set_meta("settings_back", back)
	var grid: GridContainer
	for section in [
		["音", "Sound", [
			["slider", "master_volume", "Master volume", 0.0, 1.0, 0.05, "%d%%", 100.0],
			["slider", "music_volume", "Music & ambience", 0.0, 1.0, 0.05, "%d%%", 100.0],
			["slider", "sfx_volume", "Sound effects", 0.0, 1.0, 0.05, "%d%%", 100.0],
		]],
		["操作", "Controls", [
			["slider", "mouse_sensitivity", "Mouse sensitivity", 0.25, 3.0, 0.05, "%.2fx", 1.0],
			["slider", "stick_sensitivity", "Gamepad look speed", 0.25, 3.0, 0.05, "%.2fx", 1.0],
			["toggle", "invert_y", "Invert look Y (mouse and stick)"],
		]],
		["画面", "Display", [
			["slider", "fov", "Field of view", 60.0, 100.0, 1.0, "%d°", 1.0],
			["toggle", "fullscreen", "Fullscreen"],
			["slider", "resolution_scale", "Resolution scale (3D)", 0.5, 1.0, 0.05, "%d%%", 100.0],
			["toggle", "vsync", "V-Sync"],
		]],
		["表示", "Accessibility", [
			["toggle", "reduce_shake", "Reduce camera shake"],
			["toggle", "subtitles", "Subtitles for important sounds"],
			["toggle", "large_text", "Large text (+15%)"],
		]],
	]:
		hud.overlay_box.add_child(hud._section(section[0], section[1]))
		grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 8)
		hud.overlay_box.add_child(grid)
		for item in section[2]:
			var l: Label = hud._label(item[2], UI.FS_BODY, hud.oc_text)
			l.custom_minimum_size = Vector2(330, 0)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(l)
			if item[0] == "slider":
				grid.add_child(_slider(hud, item[1], item[3], item[4], item[5], item[6], item[7]))
			else:
				grid.add_child(_toggle(hud, item[1]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(hud._button("戻る  Back  [%s]" % Game.glyph("back"), back))
	row.add_child(hud._button("初期設定に戻す  Reset to defaults", func():
		Settings.reset_defaults()
		show_settings(hud, back)))
	hud.overlay_box.add_child(hud._spacer(0))
	hud.overlay_box.add_child(row)
	hud._fit_overlay()


static func _slider(hud, key: String, lo: float, hi: float, step: float, fmt: String, mult: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.name = "slider_" + key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(Settings.get_value(key))
	UI.style_slider(s)
	var val: Label = hud._label(fmt % (s.value * mult), UI.FS_BODY, hud.oc_accent)
	val.custom_minimum_size = Vector2(80, 0)
	s.value_changed.connect(func(v: float):
		val.text = fmt % (v * mult)
		Settings.set_value(key, v))
	row.add_child(s)
	row.add_child(val)
	return row


static func _toggle(hud, key: String) -> Button:
	var b := Button.new()
	b.name = "toggle_" + key
	b.toggle_mode = true
	b.button_pressed = bool(Settings.get_value(key))
	b.custom_minimum_size = Vector2(150, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var refresh := func():
		b.text = "入  ON" if b.button_pressed else "切  OFF"
		var on := b.button_pressed
		b.add_theme_stylebox_override("normal", UI.box(UI.JR_GREEN if on else UI.SIGN_DIM, Color(1, 1, 1, 0.2)))
		b.add_theme_stylebox_override("pressed", UI.box(UI.JR_GREEN, UI.SIGN_YELLOW))
		b.add_theme_stylebox_override("hover", UI.box((UI.JR_GREEN if on else UI.SIGN_DIM).lightened(0.1), UI.SIGN_YELLOW))
		b.add_theme_stylebox_override("hover_pressed", UI.box(UI.JR_GREEN.lightened(0.1), UI.SIGN_YELLOW))
	refresh.call()
	b.toggled.connect(func(on: bool):
		refresh.call()
		Settings.set_value(key, on))
	return b


# --- Credits ---------------------------------------------------------------------

static func show_credits(hud, back: Callable) -> void:
	hide_title(hud)
	hud._open("credits", "クレジット", "Credits")
	hud.set_meta("settings_back", back)
	var box = hud.overlay_box
	box.add_child(hud._bilingual("生きていく", "KEEP LIVING  v%s" % ProjectSettings.get_setting("application/config/version", "0.1"), 34, UI.FS_NOTE, hud.oc_accent, hud.oc_dim))
	credits_content(hud, box)
	box.add_child(hud._button("戻る  Back  [%s]" % Game.glyph("back"), back))
	hud._fit_overlay()


## The credits text (also rolled after the true ending). Uses the hud's current
## overlay colours (hud.oc_*).
static func credits_content(hud, box: Control) -> void:
	box.add_child(hud._text("A roguelite about surviving the end of the world from inside a Tokyo 1LDK. Design, code, models and sounds made for this game; all sound effects are synthesised in-house.", UI.FS_BODY))
	box.add_child(hud._section("書体", "Fonts (SIL Open Font License 1.1)"))
	for line in [
		"BIZ UDPGothic: © 2022 The BIZ UDGothic Project Authors (Morisawa)",
		"DSEG7 Classic: © 2017 keshikan (keshikan.net), Reserved Font Name \"DSEG\"",
		"Dela Gothic One: © 2020 The Dela Gothic Project Authors (syakuzen)",
	]:
		box.add_child(hud._text(line, UI.FS_BODY))
	box.add_child(hud._text("The full licence texts ship with the game in assets/fonts/OFL_*.txt.", UI.FS_NOTE, hud.oc_dim))
	box.add_child(hud._section("素材", "Textures and models: Poly Haven (CC0)"))
	box.add_child(hud._text("Photo textures and scanned props are CC0 from Poly Haven (polyhaven.com). Thank you to the Poly Haven team and its supporters.", UI.FS_BODY))
	box.add_child(hud._text("Textures: " + ", ".join(TEXTURE_CREDITS) + ". Wallpaper is generated.", UI.FS_NOTE, hud.oc_dim))
	box.add_child(hud._text("Models: " + ", ".join(MODEL_CREDITS) + ".", UI.FS_NOTE, hud.oc_dim))
	box.add_child(hud._section("エンジン", "Engine"))
	box.add_child(hud._text("Made with the Godot Engine (godotengine.org), MIT licence. © Juan Linietsky, Ariel Manzur and contributors.", UI.FS_BODY))
