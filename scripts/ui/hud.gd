extends CanvasLayer
## All UI, built in code: status, prompts, message feed, clue popups, the
## journal (clues / insights / theory board / Echoes), intro, death & win
## screens and the pause menu. The title screen, scenario select, settings
## and credits live in menus.gd. Scenario text comes from Game.scenario.

const Scenarios := preload("res://scripts/data/scenarios.gd")
const Menus := preload("res://scripts/ui/menus.gd")
const Perks := preload("res://scripts/data/perks.gd")
const UI := preload("res://scripts/ui/ui_style.gd")

# Roles -> the "Office hours" palette (scripts/ui/ui_style.gd).
const C_TEXT := UI.PAPER
const C_DIM := UI.DIM
const C_GOOD := UI.LINE_GREEN
const C_WARN := UI.SIGN_YELLOW
const C_DANGER := UI.ALERT_TEXT
const C_ACCENT := UI.HANKO_TEXT

var player: Node
var barricades := {}
var seal = null           # Ash: scripts/systems/seal.gd (from the AshDirector)
var seal_mode := false

var title_root: Control   # menus.gd's title screen, while it's up
var air_bar: ProgressBar
var air_row: Control
var _air_fill := -1
var haze: ColorRect       # ash in the room greys the picture a little
var caption_box: VBoxContainer
var _caption_last := {}   # sound -> ticks msec
var _built_scenario := ""

var root: Control
var clock_label: Label      # 7-segment HH:MM
var day_label: Label
var phase_label: Label
var health_bar: ProgressBar
var hunger_bar: ProgressBar
var thirst_bar: ProgressBar
var noise_bar: ProgressBar
var noise_row: Control
var inv_label: Label
var info_label: Label
var feed: VBoxContainer
var prompt_box: PanelContainer
var prompt_label: RichTextLabel
var prompt_rows: Array = []   # [{row, cap, label}] for E and R
var _prompt_sticker: PanelContainer
var _prompt_target: Object
var barricade_rows := {}

# Step 2: alerts and feedback
var vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _hurt := 0.0
var _last_health := -1.0
var eew_banner: PanelContainer
var _eew_style: StyleBoxFlat
var _eew_left := 0.0       # seconds the EEW banner stays up
var _eew_tween: Tween
var _eew_flash: Tween
var top_stack: VBoxContainer  # ticker + feed, top centre
var ticker: VBoxContainer
var hint_bar: HBoxContainer
var _hint_chips := {}         # hint id -> chip
var _look_accum := 0.0

const EEW_HEIGHT := 124.0
const HINT_USES := 3
## Contextual controls: id -> [keys, label, actions]. Shown until each is used
## HINT_USES times (counts survive restarts within a session).
const HINTS := [
	["look", ["Mouse"], "look", []],
	["move", ["WASD"], "move", ["move_up", "move_down", "move_left", "move_right"]],
	["sneak", ["Shift"], "walk quietly", ["sneak"]],
	["use", ["E", "R"], "hold to use", ["interact", "interact_alt"]],
	["attack", ["LMB"], "swing", ["attack"]],
	["flashlight", ["F"], "phone light", ["flashlight"]],
	["items", ["1", "2", "3"], "eat · drink · first aid", ["eat", "drink", "medkit"]],
	["journal", ["J"], "journal", ["journal"]],
	["pause", ["Esc"], "menu", ["pause"]],
]
## The full list for the 取扱説明書 Manual page.
const MANUAL := [
	[["Mouse"], "Look around"],
	[["W", "A", "S", "D"], "Move (arrow keys work too)"],
	[["Shift"], "Walk quietly: makes far less noise"],
	[["E"], "Hold to use what you're looking at"],
	[["R"], "Hold for the second action, when there is one"],
	[["LMB", "Space"], "Swing (bare hands, or the bat once you have it)"],
	[["F"], "Phone light on / off"],
	[["1"], "Eat"],
	[["2"], "Drink"],
	[["3"], "First aid"],
	[["4"], "Put on a dust mask (Ash)"],
	[["J", "Tab"], "Journal: clues, insights, theory, Echoes"],
	[["Esc"], "Menu"],
]
static var _hint_uses := {}

var overlay: ColorRect
var overlay_box: VBoxContainer
var overlay_kind := ""  # intro | reading | journal | pause | manual | end
var _reading_queue: Array = []
var _erase_armed := false
var _erase_button: Button
var _hud_boxes: Array = []  # HUD panel styles whose top rule turns red at night
var _ov_frame: PanelContainer       # steel sign frame (or red/green poster edge)
var _ov_face: PanelContainer        # white sign face (or black poster band)
var _ov_header: PanelContainer      # red header block with the bilingual title
var _ov_header_style: StyleBoxFlat
var _ov_scroll: ScrollContainer
var _ov_frame_sign: StyleBox
var _ov_frame_end: StyleBoxFlat
var _ov_face_sign: StyleBox
var _ov_face_end: StyleBox
var _ov_sign_theme: Theme
# Text roles inside the current overlay (ink on a sign, paper on a poster).
var oc_text := UI.INK
var oc_dim := UI.SIGN_DIM
var oc_good := UI.JR_GREEN
var oc_warn := UI.SIGN_WARN
var oc_accent := UI.JR_GREEN
var _shown_phase := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_built_scenario = Game.scenario.ID
	seal_mode = Game.is_seal_mode()
	var ash = get_parent().get_node_or_null("AshDirector") if get_parent() else null
	if ash:
		seal = ash.seal
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build_theme()
	add_child(root)
	_build_haze()
	_build_vignette()
	_build_status()
	_build_barricade_panel()
	_build_feed()
	_build_prompt()
	_build_help()
	_build_crosshair()
	_build_eew()
	_build_captions()
	_build_overlay()
	Sfx.played.connect(_on_sound)

	Game.message.connect(_on_message)
	Game.earthquake_warning.connect(_on_earthquake_warning)
	Game.earthquake.connect(_on_earthquake)
	Game.clue_found.connect(_on_clue_found)
	Game.player_died.connect(_on_player_died)
	Game.run_won.connect(_on_run_won)

	if Game.phase == Game.Phase.INTRO:
		if Game.show_title:
			_show_title()
		else:
			_show_intro()


# --- Widgets ----------------------------------------------------------------------

## A HUD panel (office grey, coloured top rule that follows the day/night phase).
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var box := UI.panel_box()
	_hud_boxes.append(box)
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, font_size: int = UI.FS_HUD, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _bar(color: Color, width: float = 200.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 10)
	b.max_value = 100
	b.add_theme_stylebox_override("fill", UI.bar_box(color))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _stat_row(parent: Node, title: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(title, UI.FS_HUD, C_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	parent.add_child(row)
	return row


## Signage bilingual pattern (the SOS plate): big bold Japanese, small English
## directly under it.
func _bilingual(jp: String, en: String, jp_size: int, en_size: int, jp_color: Color, en_color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, display := false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var j := _label(jp, jp_size, jp_color)
	j.add_theme_font_override("font", UI.display_font() if display else UI.bold_font())
	j.horizontal_alignment = align
	var e := _label(en, en_size, en_color)
	e.add_theme_font_override("font", UI.bold_font())
	e.horizontal_alignment = align
	v.add_child(j)
	v.add_child(e)
	return v


func _expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


# --- Status (top-left) --------------------------------------------------------------

func _build_status() -> void:
	var p := _panel()
	p.position = Vector2(16, 16)
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	day_label = _label("1日目", UI.FS_HUD, C_DIM)
	day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 7-segment clock over its own faint unlit "88:88", like a bedside LCD.
	var unlit := _label("88:88", UI.FS_CLOCK, Color(UI.PAPER, 0.08))
	unlit.add_theme_font_override("font", UI.clock_font())
	unlit.add_theme_constant_override("outline_size", 0)
	clock_label = _label("08:00", UI.FS_CLOCK)
	clock_label.add_theme_font_override("font", UI.clock_font())
	clock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unlit.add_child(clock_label)
	phase_label = _label("日中 DAY", UI.FS_HUD, C_WARN)
	phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(day_label)
	top.add_child(unlit)
	top.add_child(phase_label)
	v.add_child(top)
	health_bar = _bar(UI.BAR_HEALTH)
	hunger_bar = _bar(UI.BAR_HUNGER)
	thirst_bar = _bar(UI.BAR_THIRST)
	noise_bar = _bar(UI.BAR_NOISE)
	_stat_row(v, "体調  Health", health_bar)
	_stat_row(v, "空腹  Hunger", hunger_bar)
	_stat_row(v, "水分  Thirst", thirst_bar)
	noise_row = _stat_row(v, "物音  Noise", noise_bar)
	air_bar = _bar(UI.BAR_AIR)
	air_row = _stat_row(v, "空気  Air", air_bar)
	air_row.visible = seal_mode
	inv_label = _label("", UI.FS_HUD)
	v.add_child(inv_label)
	info_label = _label("", UI.FS_HUD, C_WARN)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(360, 0)
	v.add_child(info_label)


func _build_barricade_panel() -> void:
	# A backlit JR-style sign in a steel frame, with a red location sticker.
	var p := UI.sign_panel(12)
	p.theme = UI.build_sign_theme()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-16, 16)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	UI.sign_face(p).add_child(v)
	var head := HBoxContainer.new()
	if seal_mode:
		head.add_child(_bilingual("目張り", "Seals", 26, UI.FS_SMALL, UI.JR_GREEN, UI.SIGN_DIM))
	else:
		head.add_child(_bilingual("出入口", "Entrances", 26, UI.FS_SMALL, UI.JR_GREEN, UI.SIGN_DIM))
	head.add_child(_expander())
	var stk := UI.sticker("居室-03")
	stk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(stk)
	v.add_child(head)
	if seal_mode and seal:
		for id in seal.levels:
			var name_l := _label(seal.name_of(id), UI.FS_SMALL, UI.INK)
			var bar := _bar(UI.JR_GREEN, 260)
			bar.max_value = 2.0
			bar.custom_minimum_size.y = 8
			v.add_child(name_l)
			v.add_child(bar)
			barricade_rows[id] = {"label": name_l, "bar": bar, "fill": -1}
		return
	for id in barricades:
		var b = barricades[id]
		var name_l := _label(b.display_name, UI.FS_HUD, UI.INK)
		var bar := _bar(UI.JR_GREEN, 260)
		v.add_child(name_l)
		v.add_child(bar)
		barricade_rows[id] = {"label": name_l, "bar": bar, "fill": -1}


func _build_feed() -> void:
	# Top-centre stack, between the status and entrances panels: the red danger
	# ticker (テロップ) on top, the ordinary message feed under it. Slides down
	# out of the way while the EEW banner is up.
	top_stack = VBoxContainer.new()
	top_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_stack.position = Vector2(-395, 16)
	top_stack.custom_minimum_size = Vector2(790, 0)
	top_stack.add_theme_constant_override("separation", 8)
	top_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_stack)
	ticker = VBoxContainer.new()
	ticker.add_theme_constant_override("separation", 4)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_stack.add_child(ticker)
	feed = VBoxContainer.new()
	feed.custom_minimum_size = Vector2(790, 0)
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.add_theme_constant_override("separation", 4)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_stack.add_child(feed)


## A key cap: small yellow plate with the key in ink.
func _keycap(key: String, font_size: int = UI.FS_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.keycap_box())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(key, font_size, UI.KEYCAP_TEXT)
	l.add_theme_font_override("font", UI.bold_font())
	l.add_theme_constant_override("outline_size", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(font_size * 0.7, 0)
	p.add_child(l)
	return p


## A key cap with a hold-progress ring around it, drawn by hand.
func _ring_cap(key: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(52, 52)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("key", key)
	c.set_meta("fraction", 0.0)
	c.draw.connect(_draw_ring_cap.bind(c))
	return c


func _draw_ring_cap(c: Control) -> void:
	var centre := c.size * 0.5
	var frac: float = c.get_meta("fraction", 0.0)
	var r := 23.0
	if frac > 0.0:
		c.draw_arc(centre, r, 0.0, TAU, 48, UI.SIGN_TRACK, 4.0, true)
		c.draw_arc(centre, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, UI.JR_GREEN, 5.0, true)
	var half := 15.0
	var rect := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
	c.draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), UI.SIGN_YELLOW.darkened(0.45))
	c.draw_rect(rect, UI.SIGN_YELLOW)
	c.draw_rect(Rect2(rect.position, rect.size + Vector2(0, 3)), UI.POSTER_BLACK, false, 1.5)
	var font := UI.bold_font()
	var fs := UI.FS_PROMPT
	var key: String = c.get_meta("key", "")
	var w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := centre.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	c.draw_string(font, Vector2(centre.x - w * 0.5, base), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.KEYCAP_TEXT)


func _build_prompt() -> void:
	# Sign plate under the crosshair: target name + status, then one row per
	# action with a key cap whose ring fills while the key is held.
	# A white backlit JR sign in a steel frame, with a location-code sticker.
	prompt_box = UI.sign_panel(10)
	prompt_box.theme = UI.build_sign_theme()
	prompt_box.set_anchors_preset(Control.PRESET_CENTER)
	prompt_box.position = Vector2(-320, 40)
	prompt_box.custom_minimum_size = Vector2(640, 0)
	root.add_child(prompt_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	UI.sign_face(prompt_box).add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	prompt_label = RichTextLabel.new()
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.bbcode_enabled = true
	prompt_label.fit_content = true
	prompt_label.scroll_active = false
	prompt_label.add_theme_font_size_override("normal_font_size", UI.FS_PROMPT)
	prompt_label.add_theme_font_size_override("bold_font_size", UI.FS_PROMPT)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(prompt_label)
	_prompt_sticker = UI.sticker("")
	_prompt_sticker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_prompt_sticker)
	for key in ["E", "R"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := _ring_cap(key)
		row.add_child(cap)
		var hold := _label("長押し", UI.FS_PROMPT, UI.JR_GREEN)
		hold.add_theme_font_override("font", UI.bold_font())
		hold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hold)
		var l := _label("", UI.FS_PROMPT, UI.INK)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		v.add_child(row)
		prompt_rows.append({"row": row, "cap": cap, "label": l})
	prompt_box.visible = false


func _build_help() -> void:
	# Contextual key-cap chips, bottom-left. Each disappears once used enough.
	hint_bar = HBoxContainer.new()
	hint_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_bar.position = Vector2(16, -50)
	hint_bar.add_theme_constant_override("separation", 6)
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_bar)
	for h in HINTS:
		var id: String = h[0]
		if _hint_uses.get(id, 0) >= HINT_USES:
			continue
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI.chip_box())
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in h[1]:
			row.add_child(_keycap(k))
		row.add_child(_spacer(4))
		var l := _label(h[2], UI.FS_SMALL, C_TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		chip.add_child(row)
		hint_bar.add_child(chip)
		_hint_chips[id] = chip


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _use_hint(id: String) -> void:
	_hint_uses[id] = _hint_uses.get(id, 0) + 1
	if _hint_uses[id] >= HINT_USES and _hint_chips.has(id):
		var chip: Control = _hint_chips[id]
		_hint_chips.erase(id)
		var t := chip.create_tween()
		t.tween_property(chip, "modulate:a", 0.0, 0.6)
		t.tween_callback(chip.queue_free)


func _input(event: InputEvent) -> void:
	if overlay_kind != "" or not Game.is_alive_phase():
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _hint_chips.has("look"):
			_look_accum += event.relative.length()
			if _look_accum > 400.0:
				_look_accum = 0.0
				_use_hint("look")
		return
	if event.is_echo():
		return
	for h in HINTS:
		for a in h[3]:
			if event.is_action_pressed(a):
				_use_hint(h[0])
				return


# --- Hurt vignette ---------------------------------------------------------------

func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = UI.vignette_material()
	vignette.material = _vignette_mat
	vignette.visible = false
	root.add_child(vignette)


func _refresh_vignette(delta: float) -> void:
	if _last_health >= 0.0 and Game.health < _last_health - 0.01:
		var dmg := _last_health - Game.health
		_hurt = min(1.0, _hurt + 0.45 + dmg / 25.0)
	_last_health = Game.health
	if not get_tree().paused:
		_hurt = max(0.0, _hurt - delta * 0.9)
	var frac: float = Game.health / max(1.0, Game.max_health)
	var low: float = clamp((0.3 - frac) / 0.3, 0.0, 1.0)
	if low > 0.0 and not get_tree().paused:
		# A slow heartbeat in the dark edges.
		low *= 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	vignette.visible = _hurt > 0.001 or low > 0.001
	if vignette.visible:
		_vignette_mat.set_shader_parameter("hurt", _hurt)
		_vignette_mat.set_shader_parameter("low", low)


# --- Earthquake early warning (緊急地震速報) ------------------------------------------

func _build_eew() -> void:
	eew_banner = PanelContainer.new()
	eew_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	eew_banner.offset_bottom = EEW_HEIGHT
	eew_banner.position.y = -EEW_HEIGHT - 8.0
	eew_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eew_style = UI.alert_box(12)
	eew_banner.add_theme_stylebox_override("panel", _eew_style)
	root.add_child(eew_banner)
	# Poster style: a starburst "!", 緊急地震速報 in heavy yellow lettering with
	# black and white strokes, English small under each Japanese line.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eew_banner.add_child(row)
	row.add_child(_bang(Vector2(104, 96)))
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", -4)
	left.add_child(UI.poster_label("緊急地震速報", 56, UI.SIGN_YELLOW, 4, UI.WHITE, 3))
	var en1 := _label("EARTHQUAKE EARLY WARNING", 21, UI.WHITE)
	en1.add_theme_font_override("font", UI.bold_font())
	en1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(en1)
	row.add_child(left)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 0)
	var jp2 := _label("強い揺れに警戒", 34, UI.WHITE)
	jp2.add_theme_font_override("font", UI.bold_font())
	jp2.add_theme_constant_override("outline_size", 6)
	jp2.add_theme_color_override("font_outline_color", UI.POSTER_BLACK)
	right.add_child(jp2)
	var en2 := _label("Strong shaking expected. Take cover.", 21, UI.WHITE)
	en2.add_theme_font_override("font", UI.bold_font())
	right.add_child(en2)
	row.add_child(right)
	row.add_child(_bang(Vector2(104, 96)))
	eew_banner.visible = false


## A starburst with a poster "!" in it (the red 危険 burst, in white so it
## reads on a red banner).
func _bang(sz: Vector2, fill: Color = UI.WHITE, mark: Color = UI.ALERT_RED) -> Control:
	var burst := UI.starburst(sz, fill, UI.POSTER_BLACK, 14)
	burst.add_child(UI.poster_label("!", int(sz.y * 0.55), mark, 6, UI.WHITE, 0))
	return burst


func _on_earthquake_warning() -> void:
	_eew_left = 8.0
	var was_up := eew_banner.visible
	eew_banner.visible = true
	if _eew_tween:
		_eew_tween.kill()
	_eew_tween = create_tween()
	_eew_tween.tween_property(eew_banner, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_eew_tween.parallel().tween_property(top_stack, "position:y", EEW_HEIGHT + 10.0, 0.22)
	if was_up and _eew_flash and _eew_flash.is_valid():
		return
	_eew_flash = create_tween().set_loops()
	_eew_flash.tween_property(_eew_style, "bg_color", UI.ALERT_DARK, 0.35)
	_eew_flash.tween_property(_eew_style, "bg_color", UI.ALERT_RED, 0.35)


func _on_earthquake(_strength: float) -> void:
	# Keep the banner up through the shaking (~3.5 s), then let it go.
	if eew_banner.visible:
		_eew_left = 3.8


func _refresh_eew(delta: float) -> void:
	if not eew_banner.visible or _eew_left <= 0.0:
		return
	if not get_tree().paused:
		_eew_left -= delta
	if _eew_left <= 0.0:
		_hide_eew()


func _hide_eew() -> void:
	if _eew_tween:
		_eew_tween.kill()
	_eew_tween = create_tween()
	_eew_tween.tween_property(eew_banner, "position:y", -EEW_HEIGHT - 8.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_eew_tween.parallel().tween_property(top_stack, "position:y", 16.0, 0.3)
	_eew_tween.tween_callback(_on_eew_hidden)


func _on_eew_hidden() -> void:
	if _eew_left > 0.0:
		return  # a new warning came in while sliding out
	eew_banner.visible = false
	if _eew_flash:
		_eew_flash.kill()
	_eew_style.bg_color = UI.ALERT_RED


func _build_crosshair() -> void:
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.75)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-2, -2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)


func _capture_mouse(captured: bool) -> void:
	# Automated runs (smoke test, screenshots) must never grab the user's mouse.
	if DisplayServer.get_name() == "headless" or "--smoke-test" in OS.get_cmdline_user_args():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


# --- Per-frame refresh ------------------------------------------------------------------

func _process(delta: float) -> void:
	day_label.text = "%d日目" % Game.day
	clock_label.text = Game.clock_string()
	match Game.phase:
		Game.Phase.NIGHT:
			phase_label.text = "夜  NIGHT %d / %d" % [Game.day, Game.scenario.NIGHTS_TO_SURVIVE]
			phase_label.add_theme_color_override("font_color", C_DANGER)
		Game.Phase.DAY:
			phase_label.text = "日中  DAY"
			phase_label.add_theme_color_override("font_color", C_WARN)
		_:
			phase_label.text = ""
	if Game.phase != _shown_phase:
		_shown_phase = Game.phase
		var rule: Color = UI.ALERT_RED if Game.phase == Game.Phase.NIGHT else UI.LINE_GREEN
		for box in _hud_boxes:
			box.border_color = rule
	health_bar.max_value = Game.max_health
	health_bar.value = Game.health
	hunger_bar.value = Game.hunger
	thirst_bar.value = Game.thirst
	noise_row.visible = Game.has_insight("drawn_to_sound")
	noise_bar.value = Game.noise_level * 4.0
	if seal_mode:
		_refresh_air()
		var mask := "Mask on: %dh %02dm" % [int(Game.mask_left / 60.0), int(Game.mask_left) % 60] if Game.mask_left > 0.0 else "No mask on"
		inv_label.text = "Food %d   Water %d   First aid %d   Masks %d\nMaterials %d   %s   %s" % [
			Game.food, Game.water, Game.medkits, Game.masks, Game.materials, "Metal bat" if Game.has_weapon else "Bare hands", mask]
	else:
		inv_label.text = "Food %d   Water %d   First aid %d\nMaterials %d   %s" % [
			Game.food, Game.water, Game.medkits, Game.materials, "Metal bat" if Game.has_weapon else "Bare hands"]
	info_label.text = _info_text()
	info_label.visible = info_label.text != ""
	_refresh_prompt()
	if seal_mode:
		_refresh_seals()
	else:
		_refresh_barricades()
	_refresh_vignette(delta)
	_refresh_eew(delta)
	if overlay_kind == "title" and player and has_meta("title_yaw"):
		# A slow look around the room behind the title.
		player.rotation.y = get_meta("title_yaw") + sin(Time.get_ticks_msec() * 0.00012) * 0.12


func _info_text() -> String:
	var lines: Array = []
	if Game.gas_leaking:
		lines.append("GAS LEAK: %ds. Close the gas valve!" % int(Game.gas_leak_left))
	if Game.player_sleeping:
		lines.append("Resting... (move to get up)")
	if Game.hunger <= 0.0:
		lines.append("You are starving.")
	if Game.thirst <= 0.0:
		lines.append("You are dehydrated.")
	if Game.has_insight("water_will_stop") and Game.water_running:
		lines.append("Water cuts out: day 2, 06:00")
	if seal_mode:
		lines.append_array(_ash_info())
	if Game.has_insight("rescue_day"):
		var left: int = Game.scenario.NIGHTS_TO_SURVIVE - Game.day + (1 if Game.phase == Game.Phase.DAY else 0)
		lines.append("Rescue at dawn on day %d (%d night%s to go)" % [Game.scenario.NIGHTS_TO_SURVIVE + 1, left, "" if left == 1 else "s"])
	if Game.has_insight("they_dont_climb") and Game.phase == Game.Phase.DAY:
		var counts := {}
		for id in Game.tonight_plan:
			counts[id] = counts.get(id, 0) + 1
		var parts: Array = []
		for id in counts:
			if barricades.has(id):
				parts.append("%s x%d" % [barricades[id].display_name, counts[id]])
		lines.append("Tonight: " + ", ".join(parts))
	return "\n".join(lines)


func _refresh_prompt() -> void:
	var f = player.focus if player else null
	if not Game.is_alive_phase() or not is_instance_valid(f):
		prompt_box.visible = false
		return
	prompt_box.visible = true
	prompt_label.text = "[b]%s[/b]  [color=%s]%s[/color]" % [f.display_name, UI.hex(UI.SIGN_DIM), f.get_status()]
	if f != _prompt_target:
		_prompt_target = f
		_prompt_sticker.get_child(0).text = _location_code(f)
	var frac: float = player.hold_fraction()
	var alt_held: bool = player.get("hold_alt") == true
	for i in prompt_rows.size():
		var row: Dictionary = prompt_rows[i]
		var text: String = f.get_prompt(i == 1)
		row["row"].visible = text != ""
		row["label"].text = text
		var cap: Control = row["cap"]
		var want: float = frac if (i == 1) == alt_held else 0.0
		if not is_equal_approx(cap.get_meta("fraction", 0.0), want):
			cap.set_meta("fraction", want)
			cap.queue_redraw()


## A made-up station-style location code for the sticker on the prompt sign
## (like 横浜マー11): room by position, then a stable number per object.
func _location_code(f: Node) -> String:
	var p: Vector3 = f.global_position if f is Node3D else Vector3.ZERO
	var room := "居室"   # LDK
	if p.z < 0.0:
		room = "バル"    # balcony
	elif p.z < 3.64:
		room = "洋室" if p.x < 2.73 else "居室"
	elif p.x < 2.73:
		room = "水回"    # washroom, bath, toilet
	elif p.x < 3.64 or (p.z > 6.37 and p.x < 4.55):
		room = "玄関"    # hall and genkan
	else:
		room = "台所"
	return "%s-%02d" % [room, absi(hash(str(f.name))) % 90 + 10]


func _refresh_barricades() -> void:
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for id in barricade_rows:
		var b = barricades[id]
		var row: Dictionary = barricade_rows[id]
		var bar: ProgressBar = row["bar"]
		var l: Label = row["label"]
		bar.max_value = b.max_hp
		bar.value = b.hp
		var status := "BREACHED" if b.broken else "%d/%d  L%d" % [int(b.hp), int(b.max_hp), b.level]
		l.text = "%s  %s" % [b.display_name, status]
		var c := UI.INK
		if b.broken:
			c = UI.ALERT_RED
		elif b.is_under_attack():
			c = UI.ALERT_RED if blink else UI.SIGN_WARN
		l.add_theme_color_override("font_color", c)
		var ratio: float = 0.0 if b.broken else b.hp / max(1.0, b.max_hp)
		var tier := 0 if ratio > 0.6 else (1 if ratio > 0.3 else 2)
		if tier != row["fill"]:
			row["fill"] = tier
			bar.add_theme_stylebox_override("fill", UI.bar_box([UI.JR_GREEN, UI.SIGN_YELLOW.darkened(0.1), UI.ALERT_RED][tier]))


# --- Ash ------------------------------------------------------------------------

func _build_haze() -> void:
	haze = ColorRect.new()
	haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.color = Color(UI.ASH_GREY, 0.0)
	haze.visible = false
	root.add_child(haze)


func _refresh_air() -> void:
	var air := Game.air_quality()
	air_bar.value = air
	var tier := 0 if air >= 82.0 else (1 if air >= 65.0 else 2)
	if tier != _air_fill:
		_air_fill = tier
		air_bar.add_theme_stylebox_override("fill", UI.bar_box([UI.BAR_AIR, UI.SIGN_YELLOW, UI.BAR_HEALTH][tier]))
	haze.visible = Game.dust > 2.0
	haze.color.a = clamp(Game.dust / 100.0, 0.0, 1.0) * 0.32


func _ash_info() -> Array:
	var s: Script = Game.scenario
	var lines: Array = []
	if Game.is_alive_phase() and Game.air_quality() < s.HARM_BELOW:
		lines.append("The air is hurting you. Seal the gaps, or wear a mask [4].")
	if Game.has_insight("ash_forecast") and not Game.ash_forecast.is_empty():
		var today: float = Game.ash_forecast[clampi(Game.day - 1, 0, 4)]
		var txt := "降灰予報 Ash today: %s" % s.forecast_label(today)
		if not Game.ash_falling:
			txt = "降灰予報 Ash arrives ~10:00, %s" % s.forecast_label(today)
		if Game.day < Game.ash_forecast.size():
			txt += " · tomorrow: %s" % s.forecast_label(Game.ash_forecast[Game.day])
		lines.append(txt)
	if Game.has_insight("water_time") and Game.water_running:
		lines.append("Tap water turns bad: day 2, 06:00")
	if Game.has_insight("wet_ash"):
		if Game.rain_window.size() == 2 and Game.total_minutes() < Game.rain_window[1]:
			var rd: int = int(Game.rain_window[0] / 1440) + 1
			lines.append("Rain: day %d, 13:00-19:00 (wet ash is heavy)" % rd)
		lines.append("Balcony ash load: %d%%" % int(Game.balcony_load))
	if Game.has_insight("looters") and Game.day in Game.looter_nights:
		lines.append("Looters will try the door tonight, after midnight")
	if Game.looters_active:
		lines.append("Someone is forcing the front door!")
	if Game.has_insight("evac_bus"):
		var left: int = s.NIGHTS_TO_SURVIVE - Game.day + (1 if Game.phase == Game.Phase.DAY else 0)
		lines.append("Evacuation bus at dawn on day %d (%d night%s to go)" % [s.NIGHTS_TO_SURVIVE + 1, left, "" if left == 1 else "s"])
	return lines


func _refresh_seals() -> void:
	if seal == null:
		return
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for id in barricade_rows:
		var row: Dictionary = barricade_rows[id]
		var node = seal.nodes.get(id)
		var broken: bool = node != null and node.get("broken") == true
		var lvl: int = seal.levels[id]
		var status: String = "BROKEN" if broken else ["open gap", "taped", "sealed"][lvl]
		if Game.has_insight("leak_meter"):
			status += "  %.1f" % seal.leak_of(id)
		if id == "front_door" and node and (node.hp < node.max_hp or Game.looters_active):
			status += "  door %d/%d" % [int(node.hp), int(node.max_hp)]
		var l: Label = row["label"]
		l.text = "%s  %s" % [seal.name_of(id), status]
		var c := UI.INK
		if broken:
			c = UI.ALERT_RED
		elif id == "front_door" and node and node.is_under_attack():
			c = UI.ALERT_RED if blink else UI.SIGN_WARN
		l.add_theme_color_override("font_color", c)
		var bar: ProgressBar = row["bar"]
		bar.value = 0.0 if broken else float(lvl)
		var tier := 2 if broken or lvl == 0 else (1 if lvl == 1 else 0)
		if lvl == 0 and not broken:
			bar.value = 0.08  # a sliver of red so an open gap still shows
		if tier != row["fill"]:
			row["fill"] = tier
			bar.add_theme_stylebox_override("fill", UI.bar_box([UI.JR_GREEN, UI.SIGN_YELLOW.darkened(0.1), UI.ALERT_RED][tier]))


# --- Subtitles -------------------------------------------------------------------

const CAPTIONS := {
	"bang_door": "Banging on the front door",
	"bang_glass": "Something hammering on glass",
	"door_break": "The door splinters",
	"glass_break": "Glass shatters",
	"shriek": "A shriek",
	"groan": "Groaning",
	"quake_rumble": "A deep rumble",
	"eew_alarm": "Earthquake alarm (チャラン、チャラン)",
	"phone_buzz": "Phone buzzing",
	"pipes_knock": "Pipes knocking",
	"power_down": "The power cuts out",
	"furniture_crash": "A heavy crash",
	"helicopter": "Rotor noise",
	"gas_hiss": "Hissing gas",
}


func _build_captions() -> void:
	caption_box = VBoxContainer.new()
	caption_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	caption_box.position = Vector2(-300, -150)
	caption_box.custom_minimum_size = Vector2(600, 0)
	caption_box.alignment = BoxContainer.ALIGNMENT_END
	caption_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption_box)


func _on_sound(sound: String, pos: Variant) -> void:
	if not Settings.subtitles() or not CAPTIONS.has(sound) or not Game.is_alive_phase():
		return
	var now := Time.get_ticks_msec()
	if now - int(_caption_last.get(sound, -100000)) < 4000:
		return
	_caption_last[sound] = now
	var where := ""
	if pos is Vector3 and player and player.get("camera"):
		var cam: Camera3D = player.camera
		var to: Vector3 = (pos as Vector3) - cam.global_position
		if to.length() > 1.5:
			var local := cam.global_transform.basis.inverse() * to
			if local.z > abs(local.x):
				where = "  (behind)"
			elif local.x > 0.5:
				where = "  (right)"
			elif local.x < -0.5:
				where = "  (left)"
	var l := _label("[%s]%s" % [CAPTIONS[sound], where], UI.FS_FEED, UI.PAPER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UI.regular_font())
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.7), Color(0, 0, 0, 0), 0, 4))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.add_child(l)
	caption_box.add_child(plate)
	while caption_box.get_child_count() > 3:
		var old := caption_box.get_child(0)
		caption_box.remove_child(old)
		old.queue_free()
	var tw := plate.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(plate, "modulate:a", 0.0, 0.6)
	tw.tween_callback(plate.queue_free)


# --- Message feed ------------------------------------------------------------------------

func _on_message(text: String, kind: String) -> void:
	if kind == "danger":
		_ticker_message(text)
		return
	var colors := {"info": C_TEXT, "good": C_GOOD, "warn": C_WARN}
	var l := _label(text, UI.FS_FEED, colors.get(kind, C_TEXT))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(770, 0)
	l.add_theme_constant_override("outline_size", 5)
	# A dark caption strip behind each line, like TV subtitles, so green and
	# white text stay readable over white walls and pale floors.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.box(UI.PROMPT_BG, Color(0, 0, 0, 0), 0, 6))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)
	feed.add_child(plate)
	while feed.get_child_count() > 5:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()
	var tween := plate.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(plate, "modulate:a", 0.0, 1.0)
	tween.tween_callback(plate.queue_free)


## Danger: an NHK-style red テロップ strip with a white 速報 tag. Wipes in from
## the left, holds ~7 s, fades.
func _ticker_message(text: String) -> void:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UI.alert_box(8))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UI.band_box(4))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(UI.poster_label("危険", 26, UI.SIGN_YELLOW, 0, UI.WHITE, 0))
	row.add_child(tag)
	var l := _label(text, 22, UI.WHITE)
	l.add_theme_font_override("font", UI.bold_font())
	l.add_theme_constant_override("outline_size", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	ticker.add_child(strip)
	while ticker.get_child_count() > 3:
		var old := ticker.get_child(0)
		ticker.remove_child(old)
		old.queue_free()
	strip.scale = Vector2(0.0, 1.0)
	strip.modulate.a = 0.0
	var tween := strip.create_tween()
	tween.tween_property(strip, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(strip, "modulate:a", 1.0, 0.12)
	tween.tween_interval(7.0)
	tween.tween_property(strip, "modulate:a", 0.0, 0.8)
	tween.tween_callback(strip.queue_free)


# --- Overlays ---------------------------------------------------------------------------------
# Calm screens (intro, clue, journal, pause, manual) are backlit JR-style sign
# panels: steel frame, white face, red SOS-style header block with the title
# in big Japanese over small English. Death and rescue are poster screens:
# black band, heavy lettering on a starburst.

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = UI.OVERLAY_DIM
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	_ov_frame = UI.sign_panel(0)
	_ov_frame.custom_minimum_size = Vector2(860, 0)
	_ov_frame_sign = _ov_frame.get_theme_stylebox("panel")
	_ov_frame_end = UI.box(UI.ALERT_RED, UI.POSTER_BLACK, 0, 6)
	center.add_child(_ov_frame)
	_ov_face = UI.sign_face(_ov_frame)
	_ov_face_sign = _ov_face.get_theme_stylebox("panel")
	_ov_face_end = UI.band_box(0)
	_ov_sign_theme = UI.build_sign_theme()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_ov_face.add_child(col)
	_ov_header = PanelContainer.new()
	_ov_header_style = UI.header_box(UI.ALERT_RED)
	_ov_header.add_theme_stylebox_override("panel", _ov_header_style)
	col.add_child(_ov_header)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	col.add_child(margin)
	_ov_scroll = ScrollContainer.new()
	_ov_scroll.custom_minimum_size = Vector2(812, 0)
	_ov_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_ov_scroll)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 10)
	overlay_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_scroll.add_child(overlay_box)


## Clear the overlay and show it as `kind`. Calm screens get the sign look and
## a header (`jp` big, `en` small under it); "end" gets the poster look.
func _open(kind: String, jp: String = "", en: String = "") -> void:
	overlay_kind = kind
	var poster := kind == "end"
	_ov_frame.add_theme_stylebox_override("panel", _ov_frame_end if poster else _ov_frame_sign)
	_ov_face.add_theme_stylebox_override("panel", _ov_face_end if poster else _ov_face_sign)
	_ov_face.theme = null if poster else _ov_sign_theme
	if poster:
		oc_text = UI.PAPER
		oc_dim = UI.DIM
		oc_good = UI.LINE_GREEN
		oc_warn = UI.SIGN_YELLOW
		oc_accent = UI.SIGN_YELLOW
	else:
		oc_text = UI.INK
		oc_dim = UI.SIGN_DIM
		oc_good = UI.JR_GREEN
		oc_warn = UI.SIGN_WARN
		oc_accent = UI.JR_GREEN
	for c in _ov_header.get_children():
		_ov_header.remove_child(c)
		c.queue_free()
	_ov_header.visible = jp != ""
	if jp != "":
		var title := _bilingual(jp, en, 42, 20, UI.WHITE, UI.WHITE)
		title.add_theme_constant_override("separation", 0)
		_ov_header.add_child(title)
	for c in overlay_box.get_children():
		overlay_box.remove_child(c)
		c.queue_free()
	overlay.visible = true
	get_tree().paused = true
	_capture_mouse(false)


func _fit_overlay() -> void:
	# Let short panels shrink; cap tall ones (journal) and scroll.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var want: float = overlay_box.get_combined_minimum_size().y
	var head: float = _ov_header.get_combined_minimum_size().y if _ov_header.visible else 0.0
	var max_h: float = root.get_viewport_rect().size.y - 140.0 - head
	_ov_scroll.custom_minimum_size.y = min(want, max_h)


func _close() -> void:
	overlay.visible = false
	overlay_kind = ""
	get_tree().paused = false
	_capture_mouse(Game.is_alive_phase())
	if _reading_queue.size() > 0:
		var next: Array = _reading_queue.pop_front()
		_show_reading(next[0], next[1])


func _text(text: String, font_size: int = UI.FS_BODY, color: Color = Color.TRANSPARENT) -> Label:
	var l := _label(text, font_size, oc_text if color.a == 0.0 else color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(790, 0)
	return l


func _heading(text: String, font_size: int = UI.FS_HEADING, color: Color = Color.TRANSPARENT) -> Label:
	var l := _label(text, font_size, oc_text if color.a == 0.0 else color)
	l.add_theme_font_override("font", UI.bold_font())
	return l


## Section heading on a sign: big Japanese, small English under it, green rule.
func _section(jp: String, en: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_spacer(0))
	v.add_child(_bilingual(jp, en, UI.FS_HEADING, UI.FS_NOTE, oc_accent, oc_dim))
	var rule := ColorRect.new()
	rule.color = oc_accent
	rule.custom_minimum_size = Vector2(0, 3)
	v.add_child(rule)
	return v


## Poster title: heavy `jp` lettering (yellow, black and white strokes) on a
## starburst, with `en` in heavy display type under it.
func _poster_title(jp: String, en: String, burst: Color) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	var b := UI.starburst(Vector2(360, 190), burst, UI.POSTER_BLACK, 18)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_child(UI.poster_label(jp, 84, UI.SIGN_YELLOW))
	v.add_child(b)
	var e := UI.poster_label(en, 40, UI.WHITE, 7, UI.WHITE, 0)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(e)
	return v


## Poster body: yellow heavy line on the black band.
func _poster_line(text: String, size: int = 26) -> Label:
	var l := _text(text, size, UI.SIGN_YELLOW)
	l.add_theme_font_override("font", UI.bold_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _unhandled_input(event: InputEvent) -> void:
	if overlay_kind == "" and Game.is_alive_phase() and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)
	if event is InputEventKey and not event.pressed:
		return
	match overlay_kind:
		"":
			if event.is_action_pressed("journal") and Game.is_alive_phase():
				_show_journal()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("pause") and Game.is_alive_phase():
				_show_pause()
				get_viewport().set_input_as_handled()
		"reading":
			if event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
				_close()
				get_viewport().set_input_as_handled()
		"journal":
			if event.is_action_pressed("journal") or event.is_action_pressed("pause"):
				_close()
				get_viewport().set_input_as_handled()
		"pause":
			if event.is_action_pressed("pause"):
				_close()
				get_viewport().set_input_as_handled()
		"manual":
			if event.is_action_pressed("pause"):
				_show_pause()
				get_viewport().set_input_as_handled()
		"intro":
			if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
				_start_run()
				get_viewport().set_input_as_handled()
		"scenarios":
			if event.is_action_pressed("pause"):
				_show_title()
				get_viewport().set_input_as_handled()
		"settings", "credits":
			if event.is_action_pressed("pause"):
				var back: Callable = get_meta("settings_back", Callable(self, "_show_pause"))
				back.call()
				get_viewport().set_input_as_handled()


# Intro ------------------------------------------------------------------------

func _show_intro() -> void:
	var s: Script = Game.scenario
	_open("intro", "生きていく", "KEEP LIVING")
	overlay_box.add_child(_label("シナリオ %s   Scenario: %s" % [s.TITLE_JP, s.TITLE.to_upper()], UI.FS_NOTE, oc_dim))
	var body := ""
	var lives: int = Meta.runs_in(s.ID)
	if lives == 0:
		body = s.INTRO_FIRST
	else:
		body = s.INTRO_AGAIN
		var ld: Dictionary = Meta.last_death_in(s.ID)
		if ld.has("cause"):
			body += "\nLast time: %s (day %d)" % [ld["cause"], ld["day"]]
	overlay_box.add_child(_text(body, 22))
	var known := Meta.known_clue_list(s.ID).size()
	if lives > 0:
		overlay_box.add_child(_text("You remember %d of %d clues.  Lives lived: %d  Best: day %d" % [known, s.CLUES.size(), lives, Meta.best_day_in(s.ID)], UI.FS_BODY, oc_dim))
	if Meta.perks.size() > 0:
		var names: Array = []
		for p in Meta.perks:
			names.append(Perks.PERKS[p]["title"])
		overlay_box.add_child(_text("Echoes: " + ", ".join(names), UI.FS_BODY, oc_good))
	overlay_box.add_child(_text(s.GOAL_TEXT % s.NIGHTS_TO_SURVIVE, UI.FS_BODY, oc_dim))
	if s.MODE == "seal":
		overlay_box.add_child(_text("Hold E on a door, window or vent to tape it shut. Press 4 to put on a dust mask.", UI.FS_BODY, oc_good))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("起きる  Get up  [E]", _start_run))
	row.add_child(_button("タイトルへ  Title screen", _go_title))
	overlay_box.add_child(row)
	_fit_overlay()


func _start_run() -> void:
	Game.begin()
	_close()
	Game.say(Game.scenario.WAKE_MESSAGE, "info")


# Reading (clues) ----------------------------------------------------------------

func _on_clue_found(clue_id: String, is_new: bool) -> void:
	if overlay_kind != "":
		_reading_queue.append([clue_id, is_new])
		return
	_show_reading(clue_id, is_new)


func _show_reading(clue_id: String, is_new: bool) -> void:
	var clue: Dictionary = Game.scenario.CLUES[clue_id]
	Sfx.play("paper", null, -4.0)
	_open("reading", "手がかり", "Clue")
	overlay_box.add_child(_heading(clue["title"], UI.FS_HEADING))
	if is_new:
		overlay_box.add_child(_label("NEW. You'll remember this, even next time.", UI.FS_NOTE, oc_good))
	else:
		overlay_box.add_child(_label("You remember this.", UI.FS_NOTE, oc_dim))
	overlay_box.add_child(_text(clue["text"], 22))
	var insight_id: String = clue.get("insight", "")
	if insight_id != "":
		var ins: Dictionary = Game.scenario.INSIGHTS[insight_id]
		overlay_box.add_child(_text("Insight: %s. %s" % [ins["title"], ins["desc"]], UI.FS_BODY, oc_good))
	overlay_box.add_child(_button("閉じる  Close  [E]", _close))
	_fit_overlay()


# Journal ----------------------------------------------------------------------------

func _show_journal() -> void:
	_open("journal", "手帳", "Journal")
	overlay_box.add_child(_label("What you've pieced together (this persists through death)", UI.FS_NOTE, oc_dim))
	overlay_box.add_child(_section("手がかり", "Clues"))
	for clue_id in Game.scenario.CLUES:
		var clue: Dictionary = Game.scenario.CLUES[clue_id]
		if Meta.knows_clue(Game.scenario.ID, clue_id):
			var tag := "  (new this life)" if clue_id in Game.run_new_clues else ""
			overlay_box.add_child(_heading(clue["title"] + tag, 22))
			overlay_box.add_child(_text(clue["text"], UI.FS_BODY, oc_dim))
		else:
			overlay_box.add_child(_label("???", 22, oc_dim))
	overlay_box.add_child(_section("気づき", "Insights"))
	var any := false
	for insight_id in Game.scenario.INSIGHTS:
		if Game.has_insight(insight_id):
			any = true
			var ins: Dictionary = Game.scenario.INSIGHTS[insight_id]
			overlay_box.add_child(_text("%s: %s" % [ins["title"], ins["desc"]], UI.FS_BODY, oc_good))
	if not any:
		overlay_box.add_child(_text("None yet. Clues teach you things that stay useful.", UI.FS_BODY, oc_dim))

	overlay_box.add_child(_section("何が起きている?", "What is happening?"))
	if Meta.is_theory_solved(Game.scenario.ID):
		overlay_box.add_child(_text(Game.scenario.THEORY_KNOWN_TEXT, UI.FS_BODY, oc_good))
	elif Game.can_submit_theory():
		overlay_box.add_child(_text("You have enough to make a guess. You get one guess per life.", UI.FS_BODY, oc_dim))
		for t in Game.scenario.THEORIES:
			var tid: String = t["id"]
			overlay_box.add_child(_button(t["label"], func():
				Game.submit_theory(tid)
				_close()))
	elif Game.theory_attempted:
		overlay_box.add_child(_text("You've already guessed this life.", UI.FS_BODY, oc_dim))
	else:
		overlay_box.add_child(_text("You need at least %d clues before you can name it." % Game.scenario.THEORY_MIN_CLUES, UI.FS_BODY, oc_dim))

	overlay_box.add_child(_section("残響", "Echoes"))
	if Meta.perks.is_empty():
		overlay_box.add_child(_text("None yet. Each death leaves you a small advantage.", UI.FS_BODY, oc_dim))
	for p in Meta.perks:
		overlay_box.add_child(_text("%s: %s" % [Perks.PERKS[p]["title"], Perks.PERKS[p]["desc"]], UI.FS_BODY, oc_good))
	var sid: String = Game.scenario.ID
	overlay_box.add_child(_text("%s: lives %d   Rescues %d   Best: day %d%s" % [Game.scenario.TITLE,
		Meta.runs_in(sid), Meta.wins_in(sid), Meta.best_day_in(sid), _kills_text("   %s this life: %d")], UI.FS_BODY, oc_dim))
	overlay_box.add_child(_button("閉じる  Close  [J]", _close))
	_fit_overlay()


# Pause --------------------------------------------------------------------------------

func _show_pause() -> void:
	_erase_armed = false
	_open("pause", "一時停止", "Paused")
	overlay_box.add_child(_button("再開  Resume", _close))
	overlay_box.add_child(_button("手帳  Journal", _show_journal))
	overlay_box.add_child(_button("取扱説明書  Manual", _show_manual))
	overlay_box.add_child(_button("設定  Settings", func(): _show_settings(_show_pause)))
	overlay_box.add_child(_button("やり直す  Restart this life", _restart))
	_erase_button = _button("全消去  Erase all progress", _on_erase_pressed)
	overlay_box.add_child(_erase_button)
	overlay_box.add_child(_button("タイトルへ  Title screen (ends this life)", _go_title))
	overlay_box.add_child(_button("終了  Quit", func(): get_tree().quit()))
	_fit_overlay()


func _show_manual() -> void:
	_open("manual", "取扱説明書", "Manual")
	overlay_box.add_child(_bilingual("操作方法", "Controls", 26, UI.FS_NOTE, oc_accent, oc_dim))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	for entry in MANUAL:
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 6)
		keys.custom_minimum_size = Vector2(230, 0)
		for k in entry[0]:
			keys.add_child(_keycap(k, UI.FS_BODY))
		grid.add_child(keys)
		var l := _label(entry[1], UI.FS_BODY, oc_text)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
	overlay_box.add_child(grid)
	overlay_box.add_child(_text("Hold E or R on something to use it; the ring around the key fills as you work. Holding takes time and makes noise.", UI.FS_NOTE, oc_dim))
	overlay_box.add_child(_button("戻る  Back  [Esc]", _show_pause))
	_fit_overlay()


func _on_erase_pressed() -> void:
	if _erase_armed:
		Meta.reset_all()
		_restart()
	else:
		_erase_armed = true
		_erase_button.text = "Really erase every clue and Echo? Click again"


func _restart() -> void:
	get_tree().paused = false
	Game.start_run()
	get_tree().reload_current_scene()


## Front-end screens (menus.gd). Smoke-test hooks too.
func _show_title() -> void:
	Menus.show_title(self)


func _show_scenarios() -> void:
	Menus.show_scenarios(self)


func _show_settings(back: Callable = Callable()) -> void:
	Menus.show_settings(self, back if back.is_valid() else _show_pause)


func _show_credits(back: Callable = Callable()) -> void:
	Menus.show_credits(self, back if back.is_valid() else _show_title)


## Play `id` from the title / scenario select. The world is built for one
## scenario, so a different one reloads the scene straight into its intro.
func _title_play(id: String) -> void:
	Game.select_scenario(id)
	Game.show_title = false
	Menus.hide_title(self)
	if id != _built_scenario:
		_restart()
		return
	Menus.restore_camera(self)
	_show_intro()


## Back to the title screen: this life ends (nothing is recorded).
func _go_title() -> void:
	Game.show_title = true
	_restart()


func _kills_text(fmt: String) -> String:
	var label: String = Game.scenario.KILLS_LABEL
	if label == "":
		return ""
	return fmt % [label, Game.zombies_killed]


# Death & rescue -----------------------------------------------------------------------

func _on_player_died(cause: String) -> void:
	await get_tree().create_timer(1.4).timeout
	_open("end")
	_ov_frame_end.bg_color = UI.ALERT_RED
	overlay_box.add_child(_poster_title("死亡", "YOU DIED", UI.ALERT_RED))
	overlay_box.add_child(_poster_line(cause))
	var stats := _text("Day %d, %s.   Clues learned this life: %d%s" % [
		Game.day, Game.clock_string(), Game.run_new_clues.size(), _kills_text("   %s: %d")], UI.FS_BODY, UI.PAPER)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(stats)
	var choices := Game.roll_perk_choices()
	if choices.is_empty():
		overlay_box.add_child(_text("You already carry every Echo there is.", UI.FS_BODY, oc_dim))
		overlay_box.add_child(_button("Wake up again", _restart))
	else:
		var head := _bilingual("残響を選ぶ", "Choose an Echo to carry into your next life", 30, UI.FS_NOTE, UI.SIGN_YELLOW, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
		overlay_box.add_child(head)
		for perk_id in choices:
			var perk: Dictionary = Perks.PERKS[perk_id]
			var pid: String = perk_id
			var b := _button("%s: %s" % [perk["title"], perk["desc"]], func():
				Meta.add_perk(pid)
				_restart())
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(790, 0)
			overlay_box.add_child(b)
	_fit_overlay()


func _on_run_won() -> void:
	var snd: String = Game.scenario.RESCUE_SOUND
	if snd != "" and Sfx.has(snd):
		var heli := AudioStreamPlayer.new()
		heli.stream = Sfx._pick(snd)
		heli.process_mode = Node.PROCESS_MODE_ALWAYS
		heli.volume_db = -6.0
		add_child(heli)
		heli.play()
	_open("end")
	_ov_frame_end.bg_color = UI.JR_GREEN
	overlay_box.add_child(_poster_title(Game.scenario.RESCUE_JP, Game.scenario.RESCUE_EN, UI.JR_GREEN))
	var story := _text(Game.scenario.RESCUE_TEXT % Game.day, 22)
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(story)
	overlay_box.add_child(_text("Clues remembered: %d / %d.   Lives it took: %d.%s" % [
		Meta.known_clue_list(Game.scenario.ID).size(), Game.scenario.CLUES.size(), Meta.runs_in(Game.scenario.ID), _kills_text("   %s this life: %d")], UI.FS_BODY, oc_dim))
	if Meta.known_clue_list(Game.scenario.ID).size() < Game.scenario.CLUES.size():
		overlay_box.add_child(_poster_line("There's still more to learn about what happened.", 22))
	var again := HBoxContainer.new()
	again.add_theme_constant_override("separation", 12)
	again.add_child(_button("Live it again", _restart))
	again.add_child(_button("タイトルへ  Title screen", _go_title))
	overlay_box.add_child(again)
	_fit_overlay()
