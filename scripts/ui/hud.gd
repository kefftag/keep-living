extends CanvasLayer
## All UI, built in code: status, prompts, message feed, clue popups, the
## journal (clues / insights / theory board / Echoes), intro, death & win
## screens and the pause menu.

const Scenario := preload("res://scripts/data/scenario_zombie.gd")
const Perks := preload("res://scripts/data/perks.gd")

const C_TEXT := Color(0.92, 0.92, 0.9)
const C_DIM := Color(0.6, 0.62, 0.65)
const C_GOOD := Color(0.55, 0.9, 0.6)
const C_WARN := Color(1.0, 0.8, 0.35)
const C_DANGER := Color(1.0, 0.4, 0.35)
const C_ACCENT := Color(0.95, 0.35, 0.45)

var player: Node
var barricades := {}

var root: Control
var clock_label: Label
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _style(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.07, 0.09, 0.82), Color(1, 1, 1, 0.08)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, font_size: int = 16, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _bar(color: Color, width: float = 200.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 12)
	b.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _stat_row(parent: Node, title: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(title, 14, C_DIM)
	l.custom_minimum_size = Vector2(62, 0)
	row.add_child(l)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	parent.add_child(row)
	return row


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _style(Color(0.16, 0.17, 0.2), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", _style(Color(0.26, 0.2, 0.24), C_ACCENT))
	b.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.18, 0.22), C_ACCENT))
	b.add_theme_stylebox_override("focus", _style(Color(0.26, 0.2, 0.24), C_ACCENT))
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
	top.add_theme_constant_override("separation", 14)
	clock_label = _label("Day 1  08:00", 24)
	phase_label = _label("DAY", 14, C_WARN)
	phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock_label)
	top.add_child(phase_label)
	v.add_child(top)
	health_bar = _bar(Color(0.85, 0.25, 0.3))
	hunger_bar = _bar(Color(0.9, 0.65, 0.25))
	thirst_bar = _bar(Color(0.3, 0.6, 0.95))
	noise_bar = _bar(Color(0.8, 0.8, 0.85))
	_stat_row(v, "Health", health_bar)
	_stat_row(v, "Hunger", hunger_bar)
	_stat_row(v, "Thirst", thirst_bar)
	noise_row = _stat_row(v, "Noise", noise_bar)
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
	v.add_child(_label("ENTRANCES", 13, C_DIM))
	for id in barricades:
		var b = barricades[id]
		var name_l := _label(b.display_name, 14)
		var bar := _bar(Color(0.7, 0.72, 0.75), 170)
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
	prompt_box.add_theme_stylebox_override("panel", _style(Color(0.04, 0.05, 0.06, 0.55)))
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
	hold_bar = _bar(C_ACCENT, 436)
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
	clock_label.text = "Day %d   %s" % [Game.day, Game.clock_string()]
	match Game.phase:
		Game.Phase.NIGHT:
			phase_label.text = "NIGHT %d / %d" % [Game.day, Scenario.NIGHTS_TO_SURVIVE]
			phase_label.add_theme_color_override("font_color", C_DANGER)
		Game.Phase.DAY:
			phase_label.text = "DAY"
			phase_label.add_theme_color_override("font_color", C_WARN)
		_:
			phase_label.text = ""
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
	var text := "[b]%s[/b]  [color=#9aa]%s[/color]" % [f.display_name, f.get_status()]
	var p1: String = f.get_prompt(false)
	var p2: String = f.get_prompt(true)
	if p1 != "":
		text += "\n[color=#f6a]Hold E[/color]  " + p1
	if p2 != "":
		text += "\n[color=#f6a]Hold R[/color]  " + p2
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
	p.add_theme_stylebox_override("panel", _style(Color(0.08, 0.09, 0.11, 0.98), Color(1, 1, 1, 0.1)))
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
	overlay_box.add_child(_heading("Journal", 30))
	overlay_box.add_child(_label("What you've pieced together (this persists through death)", 13, C_DIM))
	overlay_box.add_child(_heading("Clues", 20, C_ACCENT))
	for clue_id in Scenario.CLUES:
		var clue: Dictionary = Scenario.CLUES[clue_id]
		if Meta.knows_clue(Scenario.ID, clue_id):
			var tag := "  (new this life)" if clue_id in Game.run_new_clues else ""
			overlay_box.add_child(_label(clue["title"] + tag, 16, C_TEXT))
			overlay_box.add_child(_text(clue["text"], 14, C_DIM))
		else:
			overlay_box.add_child(_label("???", 16, C_DIM))
	overlay_box.add_child(_heading("Insights", 20, C_ACCENT))
	var any := false
	for insight_id in Scenario.INSIGHTS:
		if Game.has_insight(insight_id):
			any = true
			var ins: Dictionary = Scenario.INSIGHTS[insight_id]
			overlay_box.add_child(_text("%s: %s" % [ins["title"], ins["desc"]], 15, C_GOOD))
	if not any:
		overlay_box.add_child(_text("None yet. Clues teach you things that stay useful.", 15, C_DIM))

	overlay_box.add_child(_heading("What is happening?", 20, C_ACCENT))
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

	overlay_box.add_child(_heading("Echoes", 20, C_ACCENT))
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
	overlay_box.add_child(_heading("Paused", 30))
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
	_open("end")
	overlay_box.add_child(_heading("RESCUED", 44, C_GOOD))
	overlay_box.add_child(_text("Dawn, day %d. Rotor noise grows over the rooftops, and a rope ladder drops past your balcony.\n\nYou kept living." % Game.day, 18))
	overlay_box.add_child(_text("Clues remembered: %d / %d.   Lives it took: %d.   Infected put down this life: %d" % [
		Meta.known_clue_list(Scenario.ID).size(), Scenario.CLUES.size(), Meta.runs, Game.zombies_killed], 15, C_DIM))
	if Meta.known_clue_list(Scenario.ID).size() < Scenario.CLUES.size():
		overlay_box.add_child(_text("There's still more to learn about what happened.", 15, C_WARN))
	overlay_box.add_child(_button("Live it again", _restart))
	_fit_overlay()
