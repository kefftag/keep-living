extends CanvasLayer
## All UI, built in code: status, prompts, message feed, clue popups, the
## journal (clues / insights / theory board / Echoes), intro, death & win
## screens and the pause menu.

const Scenario := preload("res://scripts/data/scenario_zombie.gd")
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

const EEW_HEIGHT := 112.0
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
var _overlay_box_style: StyleBoxFlat
var _shown_phase := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build_theme()
	add_child(root)
	_build_vignette()
	_build_status()
	_build_barricade_panel()
	_build_feed()
	_build_prompt()
	_build_help()
	_build_crosshair()
	_build_eew()
	_build_overlay()

	Game.message.connect(_on_message)
	Game.earthquake_warning.connect(_on_earthquake_warning)
	Game.earthquake.connect(_on_earthquake)
	Game.clue_found.connect(_on_clue_found)
	Game.player_died.connect(_on_player_died)
	Game.run_won.connect(_on_run_won)

	if Game.phase == Game.Phase.INTRO:
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
	inv_label = _label("", UI.FS_HUD)
	v.add_child(inv_label)
	info_label = _label("", UI.FS_HUD, C_WARN)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(360, 0)
	v.add_child(info_label)


func _build_barricade_panel() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-16, 16)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(_label("出入口  ENTRANCES", UI.FS_HUD, C_DIM))
	for id in barricades:
		var b = barricades[id]
		var name_l := _label(b.display_name, UI.FS_HUD)
		var bar := _bar(UI.BAR_NOISE, 250)
		v.add_child(name_l)
		v.add_child(bar)
		barricade_rows[id] = {"label": name_l, "bar": bar}


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
		c.draw_arc(centre, r, 0.0, TAU, 48, UI.RING_TRACK, 3.0, true)
		c.draw_arc(centre, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, UI.SIGN_YELLOW, 5.0, true)
	var half := 15.0
	var rect := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
	c.draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), UI.SIGN_YELLOW.darkened(0.45))
	c.draw_rect(rect, UI.SIGN_YELLOW)
	var font := UI.bold_font()
	var fs := UI.FS_PROMPT
	var key: String = c.get_meta("key", "")
	var w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := centre.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	c.draw_string(font, Vector2(centre.x - w * 0.5, base), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.KEYCAP_TEXT)


func _build_prompt() -> void:
	# Sign plate under the crosshair: target name + status, then one row per
	# action with a key cap whose ring fills while the key is held.
	prompt_box = _panel()
	prompt_box.set_anchors_preset(Control.PRESET_CENTER)
	prompt_box.position = Vector2(-290, 40)
	prompt_box.custom_minimum_size = Vector2(580, 0)
	prompt_box.add_theme_stylebox_override("panel", UI.box(UI.PROMPT_BG, Color(1, 1, 1, 0.08), 0, 10))
	root.add_child(prompt_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	prompt_box.add_child(v)
	prompt_label = RichTextLabel.new()
	prompt_label.bbcode_enabled = true
	prompt_label.fit_content = true
	prompt_label.scroll_active = false
	prompt_label.add_theme_font_size_override("normal_font_size", UI.FS_PROMPT)
	prompt_label.add_theme_font_size_override("bold_font_size", UI.FS_PROMPT)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(prompt_label)
	for key in ["E", "R"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := _ring_cap(key)
		row.add_child(cap)
		var hold := _label("長押し", UI.FS_PROMPT, C_WARN)
		hold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hold)
		var l := _label("", UI.FS_PROMPT)
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
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	eew_banner.add_child(v)
	var l1 := _label("緊急地震速報  EARTHQUAKE EARLY WARNING", 38, UI.WHITE)
	l1.add_theme_font_override("font", UI.bold_font())
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l2 := _label("強い揺れに警戒  Strong shaking expected. Take cover.", 24, UI.WHITE)
	l2.add_theme_font_override("font", UI.bold_font())
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	v.add_child(l2)
	eew_banner.visible = false


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
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


# --- Per-frame refresh ------------------------------------------------------------------

func _process(delta: float) -> void:
	day_label.text = "%d日目" % Game.day
	clock_label.text = Game.clock_string()
	match Game.phase:
		Game.Phase.NIGHT:
			phase_label.text = "夜  NIGHT %d / %d" % [Game.day, Scenario.NIGHTS_TO_SURVIVE]
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
	inv_label.text = "Food %d   Water %d   First aid %d\nMaterials %d   %s" % [
		Game.food, Game.water, Game.medkits, Game.materials, "Metal bat" if Game.has_weapon else "Bare hands"]
	info_label.text = _info_text()
	info_label.visible = info_label.text != ""
	_refresh_prompt()
	_refresh_barricades()
	_refresh_vignette(delta)
	_refresh_eew(delta)


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
	if Game.has_insight("rescue_day"):
		var left: int = Scenario.NIGHTS_TO_SURVIVE - Game.day + (1 if Game.phase == Game.Phase.DAY else 0)
		lines.append("Rescue at dawn on day %d (%d night%s to go)" % [Scenario.NIGHTS_TO_SURVIVE + 1, left, "" if left == 1 else "s"])
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
	prompt_label.text = "[b]%s[/b]  [color=%s]%s[/color]" % [f.display_name, UI.hex(C_DIM), f.get_status()]
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
		var c := C_TEXT
		if b.broken:
			c = C_DANGER
		elif b.is_under_attack():
			c = C_DANGER if blink else C_WARN
		l.add_theme_color_override("font_color", c)


# --- Message feed ------------------------------------------------------------------------

func _on_message(text: String, kind: String) -> void:
	if kind == "danger":
		_ticker_message(text)
		return
	var colors := {"info": C_TEXT, "good": C_GOOD, "warn": C_WARN}
	var l := _label(text, UI.FS_FEED, colors.get(kind, C_TEXT))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(790, 0)
	l.add_theme_constant_override("outline_size", 4)
	feed.add_child(l)
	while feed.get_child_count() > 5:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()
	var tween := l.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(l.queue_free)


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
	tag.add_theme_stylebox_override("panel", UI.tag_box())
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag_l := _label("速報", UI.FS_FEED, UI.ALERT_RED)
	tag_l.add_theme_font_override("font", UI.bold_font())
	tag_l.add_theme_constant_override("outline_size", 0)
	tag.add_child(tag_l)
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

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = UI.OVERLAY_DIM
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := PanelContainer.new()
	_overlay_box_style = UI.box(UI.OVERLAY_BG, UI.SIGN_YELLOW, 4, 24)
	p.add_theme_stylebox_override("panel", _overlay_box_style)
	p.custom_minimum_size = Vector2(860, 0)
	center.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(812, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 10)
	overlay_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(overlay_box)
	scroll.set_meta("panel", p)
	overlay.set_meta("scroll", scroll)


func _open(kind: String) -> void:
	overlay_kind = kind
	_overlay_box_style.border_color = UI.HANKO if kind == "end" else UI.SIGN_YELLOW
	for c in overlay_box.get_children():
		overlay_box.remove_child(c)
		c.queue_free()
	overlay.visible = true
	get_tree().paused = true
	_capture_mouse(false)


func _fit_overlay() -> void:
	# Let short panels shrink; cap tall ones (journal) and scroll.
	await get_tree().process_frame
	var scroll: ScrollContainer = overlay.get_meta("scroll")
	var want: float = overlay_box.get_combined_minimum_size().y
	var max_h: float = root.get_viewport_rect().size.y - 120.0
	scroll.custom_minimum_size.y = min(want, max_h)


func _close() -> void:
	overlay.visible = false
	overlay_kind = ""
	get_tree().paused = false
	_capture_mouse(Game.is_alive_phase())
	if _reading_queue.size() > 0:
		var next: Array = _reading_queue.pop_front()
		_show_reading(next[0], next[1])


func _text(text: String, font_size: int = UI.FS_BODY, color: Color = C_TEXT) -> Label:
	var l := _label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(790, 0)
	return l


func _heading(text: String, font_size: int = UI.FS_HEADING, color: Color = C_TEXT) -> Label:
	var l := _label(text, font_size, color)
	l.add_theme_font_override("font", UI.bold_font())
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


# Intro ------------------------------------------------------------------------

func _show_intro() -> void:
	_open("intro")
	overlay_box.add_child(_heading("KEEP LIVING", UI.FS_TITLE, C_ACCENT))
	overlay_box.add_child(_label("生きていく", 24, C_DIM))
	overlay_box.add_child(_label("Scenario %s" % Scenario.TITLE.to_upper(), UI.FS_NOTE, C_DIM))
	var body := ""
	if Meta.runs == 0:
		body = "Tokyo. A third-floor 1LDK in a quiet part of the city.\n\nIt's 07:58, and your phone is screaming. Outside, something has happened. You don't know what yet.\n\nStay inside. Make this apartment safe. Find out what's going on. Keep living."
	else:
		body = "You wake up. 07:58. Your phone is screaming.\n\nAgain.\n\nYou remember dying."
		if Meta.last_death.has("cause"):
			body += "\nLast time: %s (day %d)" % [Meta.last_death["cause"], Meta.last_death["day"]]
	overlay_box.add_child(_text(body, 22))
	var known := Meta.known_clue_list(Scenario.ID).size()
	if Meta.runs > 0:
		overlay_box.add_child(_text("You remember %d of %d clues.  Lives lived: %d  Best: day %d" % [known, Scenario.CLUES.size(), Meta.runs, Meta.best_day], UI.FS_BODY, C_DIM))
	if Meta.perks.size() > 0:
		var names: Array = []
		for p in Meta.perks:
			names.append(Perks.PERKS[p]["title"])
		overlay_box.add_child(_text("Echoes: " + ", ".join(names), UI.FS_BODY, C_GOOD))
	overlay_box.add_child(_text("Survive %d nights. Days: scavenge, secure and barricade. Nights: they come for the doors and windows.\nAnything you don't secure can kill you too." % Scenario.NIGHTS_TO_SURVIVE, UI.FS_BODY, C_DIM))
	overlay_box.add_child(_button("Get up  [E]", _start_run))
	_fit_overlay()


func _start_run() -> void:
	Game.begin()
	_close()
	Game.say("Your phone is buzzing on the bedside table.", "info")


# Reading (clues) ----------------------------------------------------------------

func _on_clue_found(clue_id: String, is_new: bool) -> void:
	if overlay_kind != "":
		_reading_queue.append([clue_id, is_new])
		return
	_show_reading(clue_id, is_new)


func _show_reading(clue_id: String, is_new: bool) -> void:
	var clue: Dictionary = Scenario.CLUES[clue_id]
	Sfx.play("paper", null, -4.0)
	_open("reading")
	overlay_box.add_child(_heading(clue["title"], UI.FS_HEADING))
	if is_new:
		overlay_box.add_child(_label("NEW. You'll remember this, even next time.", UI.FS_NOTE, C_GOOD))
	else:
		overlay_box.add_child(_label("You remember this.", UI.FS_NOTE, C_DIM))
	overlay_box.add_child(_text(clue["text"], 22))
	var insight_id: String = clue.get("insight", "")
	if insight_id != "":
		var ins: Dictionary = Scenario.INSIGHTS[insight_id]
		overlay_box.add_child(_text("Insight: %s. %s" % [ins["title"], ins["desc"]], UI.FS_BODY, C_GOOD))
	overlay_box.add_child(_button("Close  [E]", _close))
	_fit_overlay()


# Journal ----------------------------------------------------------------------------

func _show_journal() -> void:
	_open("journal")
	overlay_box.add_child(_heading("手帳  Journal", 44))
	overlay_box.add_child(_label("What you've pieced together (this persists through death)", UI.FS_NOTE, C_DIM))
	overlay_box.add_child(_heading("手がかり  Clues", UI.FS_HEADING, C_ACCENT))
	for clue_id in Scenario.CLUES:
		var clue: Dictionary = Scenario.CLUES[clue_id]
		if Meta.knows_clue(Scenario.ID, clue_id):
			var tag := "  (new this life)" if clue_id in Game.run_new_clues else ""
			overlay_box.add_child(_label(clue["title"] + tag, 22, C_TEXT))
			overlay_box.add_child(_text(clue["text"], UI.FS_BODY, C_DIM))
		else:
			overlay_box.add_child(_label("???", 22, C_DIM))
	overlay_box.add_child(_heading("気づき  Insights", UI.FS_HEADING, C_ACCENT))
	var any := false
	for insight_id in Scenario.INSIGHTS:
		if Game.has_insight(insight_id):
			any = true
			var ins: Dictionary = Scenario.INSIGHTS[insight_id]
			overlay_box.add_child(_text("%s: %s" % [ins["title"], ins["desc"]], UI.FS_BODY, C_GOOD))
	if not any:
		overlay_box.add_child(_text("None yet. Clues teach you things that stay useful.", UI.FS_BODY, C_DIM))

	overlay_box.add_child(_heading("何が起きている?  What is happening?", UI.FS_HEADING, C_ACCENT))
	if Meta.is_theory_solved(Scenario.ID):
		overlay_box.add_child(_text("You know what this is: an infection. The bitten turn. (+15% damage)", UI.FS_BODY, C_GOOD))
	elif Game.can_submit_theory():
		overlay_box.add_child(_text("You have enough to make a guess. You get one guess per life.", UI.FS_BODY, C_DIM))
		for t in Scenario.THEORIES:
			var tid: String = t["id"]
			overlay_box.add_child(_button(t["label"], func():
				Game.submit_theory(tid)
				_close()))
	elif Game.theory_attempted:
		overlay_box.add_child(_text("You've already guessed this life.", UI.FS_BODY, C_DIM))
	else:
		overlay_box.add_child(_text("You need at least %d clues before you can name it." % Scenario.THEORY_MIN_CLUES, UI.FS_BODY, C_DIM))

	overlay_box.add_child(_heading("残響  Echoes", UI.FS_HEADING, C_ACCENT))
	if Meta.perks.is_empty():
		overlay_box.add_child(_text("None yet. Each death leaves you a small advantage.", UI.FS_BODY, C_DIM))
	for p in Meta.perks:
		overlay_box.add_child(_text("%s: %s" % [Perks.PERKS[p]["title"], Perks.PERKS[p]["desc"]], UI.FS_BODY, C_GOOD))
	overlay_box.add_child(_text("Lives: %d   Deaths: %d   Rescues: %d   Best: day %d   Infected put down this life: %d" % [
		Meta.runs, Meta.deaths, Meta.wins, Meta.best_day, Game.zombies_killed], UI.FS_BODY, C_DIM))
	overlay_box.add_child(_button("Close  [J]", _close))
	_fit_overlay()


# Pause --------------------------------------------------------------------------------

func _show_pause() -> void:
	_erase_armed = false
	_open("pause")
	overlay_box.add_child(_heading("一時停止  Paused", 44))
	overlay_box.add_child(_button("Resume", _close))
	overlay_box.add_child(_button("Journal", _show_journal))
	overlay_box.add_child(_button("取扱説明書  Manual", _show_manual))
	overlay_box.add_child(_button("Restart this life", _restart))
	_erase_button = _button("Erase all progress", _on_erase_pressed)
	overlay_box.add_child(_erase_button)
	overlay_box.add_child(_button("Quit", func(): get_tree().quit()))
	_fit_overlay()


func _show_manual() -> void:
	_open("manual")
	overlay_box.add_child(_heading("取扱説明書  Manual", 44))
	overlay_box.add_child(_label("Controls", UI.FS_NOTE, C_DIM))
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
		var l := _label(entry[1], UI.FS_BODY)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
	overlay_box.add_child(grid)
	overlay_box.add_child(_text("Hold E or R on something to use it; the ring around the key fills as you work. Holding takes time and makes noise.", UI.FS_NOTE, C_DIM))
	overlay_box.add_child(_button("Back  [Esc]", _show_pause))
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


# Death & rescue -----------------------------------------------------------------------

func _on_player_died(cause: String) -> void:
	await get_tree().create_timer(1.4).timeout
	_open("end")
	overlay_box.add_child(_heading("YOU DIED", UI.FS_TITLE, C_DANGER))
	overlay_box.add_child(_text(cause, 24))
	overlay_box.add_child(_text("Day %d, %s.   Clues learned this life: %d   Infected put down: %d" % [
		Game.day, Game.clock_string(), Game.run_new_clues.size(), Game.zombies_killed], UI.FS_BODY, C_DIM))
	var choices := Game.roll_perk_choices()
	if choices.is_empty():
		overlay_box.add_child(_text("You already carry every Echo there is.", UI.FS_BODY, C_DIM))
		overlay_box.add_child(_button("Wake up again", _restart))
	else:
		overlay_box.add_child(_heading("Choose an Echo to carry into your next life", 28, C_ACCENT))
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
	if Sfx.has("helicopter"):
		var heli := AudioStreamPlayer.new()
		heli.stream = Sfx._pick("helicopter")
		heli.process_mode = Node.PROCESS_MODE_ALWAYS
		heli.volume_db = -6.0
		add_child(heli)
		heli.play()
	_open("end")
	overlay_box.add_child(_heading("RESCUED", UI.FS_TITLE, C_GOOD))
	overlay_box.add_child(_text("Dawn, day %d. Rotor noise grows over the rooftops, and a rope ladder drops past your balcony.\n\nYou kept living." % Game.day, 22))
	overlay_box.add_child(_text("Clues remembered: %d / %d.   Lives it took: %d.   Infected put down this life: %d" % [
		Meta.known_clue_list(Scenario.ID).size(), Scenario.CLUES.size(), Meta.runs, Game.zombies_killed], UI.FS_BODY, C_DIM))
	if Meta.known_clue_list(Scenario.ID).size() < Scenario.CLUES.size():
		overlay_box.add_child(_text("There's still more to learn about what happened.", UI.FS_BODY, C_WARN))
	overlay_box.add_child(_button("Live it again", _restart))
	_fit_overlay()
