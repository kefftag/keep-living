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
var hold_bar: ProgressBar
var barricade_rows := {}

var overlay: ColorRect
var overlay_box: VBoxContainer
var overlay_kind := ""  # intro | reading | journal | pause | end
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
	_build_status()
	_build_barricade_panel()
	_build_feed()
	_build_prompt()
	_build_help()
	_build_crosshair()
	_build_overlay()

	Game.message.connect(_on_message)
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


func _label(text: String, font_size: int = 16, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _bar(color: Color, width: float = 200.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 8)
	b.max_value = 100
	b.add_theme_stylebox_override("fill", UI.bar_box(color))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _stat_row(parent: Node, title: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(title, 14, C_DIM)
	l.custom_minimum_size = Vector2(118, 0)
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
	day_label = _label("1日目", 16, C_DIM)
	day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 7-segment clock over its own faint unlit "88:88", like a bedside LCD.
	var unlit := _label("88:88", 26, Color(UI.PAPER, 0.08))
	unlit.add_theme_font_override("font", UI.clock_font())
	unlit.add_theme_constant_override("outline_size", 0)
	clock_label = _label("08:00", 26)
	clock_label.add_theme_font_override("font", UI.clock_font())
	clock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unlit.add_child(clock_label)
	phase_label = _label("日中 DAY", 14, C_WARN)
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
	inv_label = _label("", 15)
	v.add_child(inv_label)
	info_label = _label("", 14, C_WARN)
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
	v.add_child(_label("出入口  ENTRANCES", 13, C_DIM))
	for id in barricades:
		var b = barricades[id]
		var name_l := _label(b.display_name, 14)
		var bar := _bar(UI.BAR_NOISE, 170)
		v.add_child(name_l)
		v.add_child(bar)
		barricade_rows[id] = {"label": name_l, "bar": bar}


func _build_feed() -> void:
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_CENTER_TOP)
	feed.position = Vector2(-360, 18)
	feed.custom_minimum_size = Vector2(720, 0)
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)


func _build_prompt() -> void:
	prompt_box = _panel()
	prompt_box.set_anchors_preset(Control.PRESET_CENTER)
	prompt_box.position = Vector2(-230, 40)
	prompt_box.custom_minimum_size = Vector2(460, 0)
	prompt_box.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.07, 0.08, 0.62)))
	root.add_child(prompt_box)
	var v := VBoxContainer.new()
	prompt_box.add_child(v)
	prompt_label = RichTextLabel.new()
	prompt_label.bbcode_enabled = true
	prompt_label.fit_content = true
	prompt_label.scroll_active = false
	prompt_label.add_theme_font_size_override("normal_font_size", 17)
	prompt_label.add_theme_font_size_override("bold_font_size", 17)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(prompt_label)
	hold_bar = _bar(UI.SIGN_YELLOW, 436)
	v.add_child(hold_bar)
	prompt_box.visible = false


func _build_help() -> void:
	var l := _label("Mouse look   WASD move   Shift walk quietly   E / R hold to use   LMB / Space swing   F phone light   1 eat  2 drink  3 first aid   J journal   Esc menu", 13, C_DIM)
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.position = Vector2(16, -30)
	root.add_child(l)


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

func _process(_delta: float) -> void:
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
	inv_label.text = "Food %d    Water %d    Materials %d    First aid %d\n%s" % [
		Game.food, Game.water, Game.materials, Game.medkits, "Metal bat" if Game.has_weapon else "Bare hands"]
	info_label.text = _info_text()
	_refresh_prompt()
	_refresh_barricades()


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
	var text := "[b]%s[/b]  [color=%s]%s[/color]" % [f.display_name, UI.hex(C_DIM), f.get_status()]
	var p1: String = f.get_prompt(false)
	var p2: String = f.get_prompt(true)
	if p1 != "":
		text += "\n[color=%s][b]E[/b] 長押し[/color]  %s" % [UI.hex(C_WARN), p1]
	if p2 != "":
		text += "\n[color=%s][b]R[/b] 長押し[/color]  %s" % [UI.hex(C_WARN), p2]
	prompt_label.text = text
	hold_bar.value = player.hold_fraction() * 100.0
	hold_bar.visible = hold_bar.value > 0.0


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
	var colors := {"info": C_TEXT, "good": C_GOOD, "warn": C_WARN, "danger": C_DANGER}
	var l := _label(text, 17, colors.get(kind, C_TEXT))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(720, 0)
	feed.add_child(l)
	while feed.get_child_count() > 5:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()
	var tween := l.create_tween()
	tween.tween_interval(5.0 if kind != "danger" else 7.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(l.queue_free)


# --- Overlays ---------------------------------------------------------------------------------

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.02, 0.04, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := PanelContainer.new()
	_overlay_box_style = UI.box(Color(0.11, 0.12, 0.13, 0.98), UI.SIGN_YELLOW, 4, 20)
	p.add_theme_stylebox_override("panel", _overlay_box_style)
	p.custom_minimum_size = Vector2(760, 0)
	center.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 0)
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


func _text(text: String, font_size: int = 17, color: Color = C_TEXT) -> Label:
	var l := _label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	return l


func _heading(text: String, font_size: int = 30, color: Color = C_TEXT) -> Label:
	return _label(text, font_size, color)


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
		"intro":
			if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
				_start_run()
				get_viewport().set_input_as_handled()


# Intro ------------------------------------------------------------------------

func _show_intro() -> void:
	_open("intro")
	overlay_box.add_child(_heading("KEEP LIVING", 44, C_ACCENT))
	overlay_box.add_child(_label("生きていく", 18, C_DIM))
	overlay_box.add_child(_label("Scenario %s" % Scenario.TITLE.to_upper(), 14, C_DIM))
	var body := ""
	if Meta.runs == 0:
		body = "Tokyo. A third-floor 1LDK in a quiet part of the city.\n\nIt's 07:58, and your phone is screaming. Outside, something has happened. You don't know what yet.\n\nStay inside. Make this apartment safe. Find out what's going on. Keep living."
	else:
		body = "You wake up. 07:58. Your phone is screaming.\n\nAgain.\n\nYou remember dying."
		if Meta.last_death.has("cause"):
			body += "\nLast time: %s (day %d)" % [Meta.last_death["cause"], Meta.last_death["day"]]
	overlay_box.add_child(_text(body, 18))
	var known := Meta.known_clue_list(Scenario.ID).size()
	if Meta.runs > 0:
		overlay_box.add_child(_text("You remember %d of %d clues.  Lives lived: %d  Best: day %d" % [known, Scenario.CLUES.size(), Meta.runs, Meta.best_day], 15, C_DIM))
	if Meta.perks.size() > 0:
		var names: Array = []
		for p in Meta.perks:
			names.append(Perks.PERKS[p]["title"])
		overlay_box.add_child(_text("Echoes: " + ", ".join(names), 15, C_GOOD))
	overlay_box.add_child(_text("Survive %d nights. Days: scavenge, secure and barricade. Nights: they come for the doors and windows.\nAnything you don't secure can kill you too." % Scenario.NIGHTS_TO_SURVIVE, 15, C_DIM))
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
	overlay_box.add_child(_heading(clue["title"], 26))
	if is_new:
		overlay_box.add_child(_label("NEW. You'll remember this, even next time.", 13, C_GOOD))
	else:
		overlay_box.add_child(_label("You remember this.", 13, C_DIM))
	overlay_box.add_child(_text(clue["text"], 18))
	var insight_id: String = clue.get("insight", "")
	if insight_id != "":
		var ins: Dictionary = Scenario.INSIGHTS[insight_id]
		overlay_box.add_child(_text("Insight: %s. %s" % [ins["title"], ins["desc"]], 15, C_GOOD))
	overlay_box.add_child(_button("Close  [E]", _close))
	_fit_overlay()


# Journal ----------------------------------------------------------------------------

func _show_journal() -> void:
	_open("journal")
	overlay_box.add_child(_heading("手帳  Journal", 30))
	overlay_box.add_child(_label("What you've pieced together (this persists through death)", 13, C_DIM))
	overlay_box.add_child(_heading("手がかり  Clues", 20, C_ACCENT))
	for clue_id in Scenario.CLUES:
		var clue: Dictionary = Scenario.CLUES[clue_id]
		if Meta.knows_clue(Scenario.ID, clue_id):
			var tag := "  (new this life)" if clue_id in Game.run_new_clues else ""
			overlay_box.add_child(_label(clue["title"] + tag, 16, C_TEXT))
			overlay_box.add_child(_text(clue["text"], 14, C_DIM))
		else:
			overlay_box.add_child(_label("???", 16, C_DIM))
	overlay_box.add_child(_heading("気づき  Insights", 20, C_ACCENT))
	var any := false
	for insight_id in Scenario.INSIGHTS:
		if Game.has_insight(insight_id):
			any = true
			var ins: Dictionary = Scenario.INSIGHTS[insight_id]
			overlay_box.add_child(_text("%s: %s" % [ins["title"], ins["desc"]], 15, C_GOOD))
	if not any:
		overlay_box.add_child(_text("None yet. Clues teach you things that stay useful.", 15, C_DIM))

	overlay_box.add_child(_heading("何が起きている?  What is happening?", 20, C_ACCENT))
	if Meta.is_theory_solved(Scenario.ID):
		overlay_box.add_child(_text("You know what this is: an infection. The bitten turn. (+15% damage)", 15, C_GOOD))
	elif Game.can_submit_theory():
		overlay_box.add_child(_text("You have enough to make a guess. You get one guess per life.", 15, C_DIM))
		for t in Scenario.THEORIES:
			var tid: String = t["id"]
			overlay_box.add_child(_button(t["label"], func():
				Game.submit_theory(tid)
				_close()))
	elif Game.theory_attempted:
		overlay_box.add_child(_text("You've already guessed this life.", 15, C_DIM))
	else:
		overlay_box.add_child(_text("You need at least %d clues before you can name it." % Scenario.THEORY_MIN_CLUES, 15, C_DIM))

	overlay_box.add_child(_heading("残響  Echoes", 20, C_ACCENT))
	if Meta.perks.is_empty():
		overlay_box.add_child(_text("None yet. Each death leaves you a small advantage.", 15, C_DIM))
	for p in Meta.perks:
		overlay_box.add_child(_text("%s: %s" % [Perks.PERKS[p]["title"], Perks.PERKS[p]["desc"]], 15, C_GOOD))
	overlay_box.add_child(_text("Lives: %d   Deaths: %d   Rescues: %d   Best: day %d   Infected put down this life: %d" % [
		Meta.runs, Meta.deaths, Meta.wins, Meta.best_day, Game.zombies_killed], 13, C_DIM))
	overlay_box.add_child(_button("Close  [J]", _close))
	_fit_overlay()


# Pause --------------------------------------------------------------------------------

func _show_pause() -> void:
	_erase_armed = false
	_open("pause")
	overlay_box.add_child(_heading("一時停止  Paused", 30))
	overlay_box.add_child(_button("Resume", _close))
	overlay_box.add_child(_button("Journal", _show_journal))
	overlay_box.add_child(_button("Restart this life", _restart))
	_erase_button = _button("Erase all progress", _on_erase_pressed)
	overlay_box.add_child(_erase_button)
	overlay_box.add_child(_button("Quit", func(): get_tree().quit()))
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
	overlay_box.add_child(_heading("YOU DIED", 44, C_DANGER))
	overlay_box.add_child(_text(cause, 20))
	overlay_box.add_child(_text("Day %d, %s.   Clues learned this life: %d   Infected put down: %d" % [
		Game.day, Game.clock_string(), Game.run_new_clues.size(), Game.zombies_killed], 15, C_DIM))
	var choices := Game.roll_perk_choices()
	if choices.is_empty():
		overlay_box.add_child(_text("You already carry every Echo there is.", 15, C_DIM))
		overlay_box.add_child(_button("Wake up again", _restart))
	else:
		overlay_box.add_child(_heading("Choose an Echo to carry into your next life", 18, C_ACCENT))
		for perk_id in choices:
			var perk: Dictionary = Perks.PERKS[perk_id]
			var pid: String = perk_id
			var b := _button("%s: %s" % [perk["title"], perk["desc"]], func():
				Meta.add_perk(pid)
				_restart())
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(700, 0)
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
	overlay_box.add_child(_heading("RESCUED", 44, C_GOOD))
	overlay_box.add_child(_text("Dawn, day %d. Rotor noise grows over the rooftops, and a rope ladder drops past your balcony.\n\nYou kept living." % Game.day, 18))
	overlay_box.add_child(_text("Clues remembered: %d / %d.   Lives it took: %d.   Infected put down this life: %d" % [
		Meta.known_clue_list(Scenario.ID).size(), Scenario.CLUES.size(), Meta.runs, Game.zombies_killed], 15, C_DIM))
	if Meta.known_clue_list(Scenario.ID).size() < Scenario.CLUES.size():
		overlay_box.add_child(_text("There's still more to learn about what happened.", 15, C_WARN))
	overlay_box.add_child(_button("Live it again", _restart))
	_fit_overlay()
