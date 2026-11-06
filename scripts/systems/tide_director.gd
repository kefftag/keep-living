extends Node
## Tide (scenario_tide.gd): the typhoon, the flood, the phone and Tanaka.
##
## - Wind follows Game.storm_curve. Gusts throw debris at the balcony side
##   (storm_guard.gd takes the hits); a blown-in window cuts whoever is near,
##   soaks things and lets the storm in until it's boarded over.
## - The flood rises in the street (a water plane over apartment.gd's street).
## - The phone battery drains with standby, the phone light and every alert
##   you read; it charges while the power lasts (plugged in at the bedside),
##   from the crank charger (key 4) and from mobile batteries.
## - Tap water turns brown on day 2: boil it at the sink while the gas lasts,
##   or drink it raw and get sick.
## - Tanaka from 202 knocks one night. Letting him in costs food and water
##   each morning but brings materials and what he knows; refusing leaves a
##   note under the door.
## Integrates on Game.minutes_advanced, like the AshDirector.

const Props := preload("res://scripts/world/props.gd")
const STEP := 5.0
const STREET_Y := -9.2       # top of apartment.gd's street slab
## The skyline is built a little taller than life: 3F sits 9.3 m over the
## street there, 6.3 m in the story. Scale the water so the depths match.
const FLOOD_VIS_SCALE := 9.2 / 6.3

var guard            # scripts/systems/storm_guard.gd
var apartment: Node3D
var player: Node3D

var _loose := true           # the balcony things are still outside
var _loose_nodes: Array = []
var _warned := {}
var _peak_seen := false
var _boils := {}             # day -> boils
# Tanaka
var _knock_at := -1.0        # night seconds when he knocks (-1: not tonight)
var _night_t := 0.0
var _knocking := false
var _knock_left := 0.0
var _knock_snd_t := 0.0
var _plea_t := 0.0
# Visuals and sound
var _rain: Array = []        # [particles, wind threshold]
var _debris: Array = []
var _water: MeshInstance3D
var _water_mat: StandardMaterial3D
var _water_y := STREET_Y - 0.5
var _env: Environment
var _env_t := 0.0
var _wind_snd: AudioStreamPlayer
var _rain_snd: AudioStreamPlayer3D
var _light_warned := 0


func _ready() -> void:
	Game.minutes_advanced.connect(_on_minutes)
	Game.scenario_event.connect(_on_event)
	Game.phase_changed.connect(_on_phase)
	Game.world_changed.connect(_on_world_changed)
	_build_visuals()
	var we := get_parent().find_children("*", "WorldEnvironment", false, false) if get_parent() else []
	if not we.is_empty():
		_env = (we[0] as WorldEnvironment).environment
	Game.storm_level = storm_at(Game.total_minutes())
	Game.flood_depth = flood_at(Game.total_minutes())
	for id in guard.nodes:
		guard.refresh_visual(guard.nodes[id])


func scenario() -> Script:
	return Game.scenario


func storm_at(total: float) -> float:
	return scenario().curve_at(Game.storm_curve, total)


func flood_at(total: float) -> float:
	return scenario().curve_at(scenario().FLOOD_CURVE, total)


static func _is_night_minute(total: float) -> bool:
	var m := fmod(total, 1440.0)
	return m >= Game.NIGHT_START or m < 6 * 60


## Battery drain multiplier from what you know.
func battery_mult() -> float:
	var s := scenario()
	var m := 1.0
	if Game.has_insight("low_power"):
		m *= s.LOW_POWER_MULT
	if s.THEORY_BONUS == "battery" and Meta.is_theory_solved(s.ID):
		m *= s.THEORY_BATTERY_MULT
	return m


func drain_battery(amount: float) -> void:
	Game.phone_battery = clampf(Game.phone_battery - amount * battery_mult(), 0.0, 100.0)
	_check_battery()


func _check_battery() -> void:
	var s := scenario()
	if Game.phone_battery <= s.POWER_BANK_AT and Game.power_banks > 0:
		Game.power_banks -= 1
		Game.phone_battery = min(100.0, Game.phone_battery + s.POWER_BANK_GAIN)
		Game.say("You plug the phone into the mobile battery. (Phone %d%%)" % int(Game.phone_battery), "good")
	if Game.phone_battery <= 0.0:
		Game.phone_battery = 0.0
		if player and player.flashlight.visible:
			player.flashlight.visible = false
			Game.light_on = false
		if not _warned.get("dead", false):
			_warned["dead"] = true
			Game.say("The phone screen goes black. No light, no news.%s" % (" Wind the crank charger [%s]." % Game.glyph("mask") if Game.has_crank else ""), "danger")
	elif Game.phone_battery > 5.0:
		_warned["dead"] = false


# --- Time ------------------------------------------------------------------------

func _on_minutes(m: float) -> void:
	var s := scenario()
	var t0 := Game.total_minutes() - m
	var left := m
	while left > 0.0 and Game.is_alive_phase():
		var dt: float = min(STEP, left)
		left -= dt
		t0 += dt
		var wind := storm_at(t0)
		Game.storm_level = wind
		Game.flood_depth = flood_at(t0)
		if wind > 0.03:
			var expect: float = s.GUSTS_PER_HOUR * wind * dt / 60.0
			var n := int(expect) + (1 if Game.rng.randf() < fmod(expect, 1.0) else 0)
			for i in n:
				_gust(wind, _is_night_minute(t0))
				if not Game.is_alive_phase():
					return
		var broken := _broken_count()
		if broken > 0 and wind > 0.1:
			Game.wear_down(s.EXPOSURE_HP_PER_MIN * wind * min(broken, 2) * dt, Game.death_text("exposure"))
		if Game.sick_left > 0.0:
			Game.sick_left = max(0.0, Game.sick_left - dt)
			Game.wear_down(s.SICK_HP_PER_MIN * dt, Game.death_text("sick"))
			if Game.sick_left <= 0.0:
				Game.say("The cramps finally ease off.", "good")
		# The phone: charging at the bedside while there's power, otherwise standby.
		if Game.power_on and Game.phone_plugged:
			Game.phone_battery = min(100.0, Game.phone_battery + s.PHONE_CHARGE_PER_MIN * dt)
		else:
			drain_battery(s.PHONE_STANDBY_PER_MIN * dt)
	_warnings()


func _gust(wind: float, night: bool) -> void:
	var s := scenario()
	if _loose and wind >= s.LOOSE_GUST:
		_loose_fly()
		return
	var target := _weighted_pick(s.GUST_WEIGHTS)
	var amount: float = Game.rng.randf_range(s.DEBRIS_DAMAGE[0], s.DEBRIS_DAMAGE[1]) * wind
	if night:
		amount *= s.NIGHT_MULT
	guard.hit(target, amount)


func _weighted_pick(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := Game.rng.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]


func _broken_count() -> int:
	var n := 0
	for id in guard.nodes:
		if guard.is_glass(id) and guard.nodes[id].broken:
			n += 1
	return n


func _warnings() -> void:
	if not Game.is_alive_phase():
		return
	var w := Game.storm_level
	if w >= 0.5 and not _warned.get("storm", false):
		_warned["storm"] = true
		Game.say("The wind is at storm force. Things are flying past the balcony.", "warn")
	if w >= 0.9 and not _warned.get("peak", false):
		_warned["peak"] = true
		_peak_seen = true
		Sfx.play("pipes_knock", Vector3(3.2, 1.2, 3.6), -2.0)
		Game.say("The whole building shudders in the gusts. Keep away from the glass!", "danger")
	if _peak_seen and w < 0.45 and not _warned.get("lull", false):
		_warned["lull"] = true
		Game.say("The wind drops. It's eerie, after the noise. The other side of the storm is still to come.", "info")
	if _warned.get("lull", false) and w >= 0.6 and not _warned.get("back", false):
		_warned["back"] = true
		Game.say("The wind swings round and comes back from the other side (吹き返し).", "warn")
	if _warned.get("back", false) and w < 0.1 and not _warned.get("over", false):
		_warned["over"] = true
		Game.say("The storm has passed. Only the water is left, and it isn't going anywhere.", "good")
	var d := Game.flood_depth
	if d >= 1.0 and not _warned.get("cars", false):
		_warned["cars"] = true
		Game.say("Below, the street has become a river. The water is over the car roofs.", "warn")
	if d >= scenario().SECOND_FLOOR and not _warned.get("2f", false):
		_warned["2f"] = true
		Sfx.play("pipes_knock", Vector3(10.0, -0.5, 8.0), 0.0)
		Game.say("You can hear water slapping in the stairwell. It's in the second-floor flats.", "warn")
	if Game.thirst < 25.0 and Game.water <= 0 and Game.water_note != "" and not _warned.get("thirst", false):
		_warned["thirst"] = true
		Game.say("You're parched. The tap water could be boiled at the sink while the gas works.", "warn")


func _on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"gas_cut":
			Game.gas_valve_open = false
			Game.gas_leaking = false
			Game.say("The blue flame dies on the stove. The gas meter in the flooded basement has cut out.", "warn")
			Game.world_changed.emit()
		"flood_rising":
			Game.say("The surge has come in with the tide. Brown water is pouring down the street below.", "danger")


func _on_world_changed() -> void:
	if not Game.power_on and Game.phone_plugged:
		Game.phone_plugged = false
		Game.say("The charging light on the phone goes out. (Phone %d%%)" % int(Game.phone_battery), "warn")


func _on_phase(phase: int) -> void:
	var s := scenario()
	if phase == Game.Phase.NIGHT:
		_night_t = 0.0
		_knock_at = -1.0
		if Game.day == Game.tanaka_night and not Game.flags.has("tanaka"):
			var night_len := (Game.NIGHT_END - Game.NIGHT_START) / Game.NIGHT_MIN_PER_SEC
			_knock_at = night_len * Game.rng.randf_range(s.TANAKA_AT[0], s.TANAKA_AT[1])
	elif phase == Game.Phase.DAY:
		if _knocking:
			refuse(true)
		if Game.flags.get("tanaka") == "refused" and not Game.flags.has("tanaka_note"):
			Game.flags["tanaka_note"] = true
			Game.say("Something was pushed under the front door in the night.", "info")
		if Game.flags.get("tanaka") == "in":
			_guest_morning()
	elif phase == Game.Phase.WON:
		match Game.flags.get("tanaka", ""):
			"in":
				Game.end_note = "Tanaka from 202 goes down the ladder first, his tool bag held over his head. In the boat he turns and bows to you, very low."
			"refused":
				Game.end_note = "On the way out you ask the crew about an old man from 202. Nobody has seen him. The stairwell is still under water."


func _guest_morning() -> void:
	var s := scenario()
	var parts: Array = []
	if Game.food >= s.GUEST_FOOD:
		Game.food -= s.GUEST_FOOD
		parts.append("-%d food" % s.GUEST_FOOD)
	if Game.water >= s.GUEST_WATER:
		Game.water -= s.GUEST_WATER
		parts.append("-%d water" % s.GUEST_WATER)
	Game.materials += s.GUEST_DAILY
	if parts.is_empty():
		Game.say("Tanaka says he isn't hungry. He is. He's found you some boards in the stairwell (+%d material)." % s.GUEST_DAILY, "warn")
	else:
		Game.say("You share breakfast with Tanaka (%s). He's pried boards off the stairwell noticeboard (+%d material)." % [", ".join(parts), s.GUEST_DAILY], "info")
	Game.stats_changed.emit()


func _process(delta: float) -> void:
	_update_visuals(delta)
	if not Game.is_alive_phase() or get_tree().paused:
		return
	var s := scenario()
	# The phone light runs on the phone (real seconds).
	if player:
		if player.flashlight.visible and Game.phone_battery <= 0.0:
			player.flashlight.visible = false
		Game.light_on = player.flashlight.visible
		if Game.light_on:
			drain_battery(s.PHONE_LIGHT_PER_SEC * delta)
			if Game.phone_battery < 15.0 and _light_warned < 1:
				_light_warned = 1
				Game.say("Phone battery %d%%. The light eats it." % int(Game.phone_battery), "warn")
	# Tanaka.
	if Game.phase == Game.Phase.NIGHT and _knock_at >= 0.0 and not _knocking and not Game.flags.has("tanaka"):
		_night_t += delta
		if _night_t >= _knock_at:
			begin_knock()
	if _knocking:
		_knock_left -= delta
		_knock_snd_t -= delta
		_plea_t -= delta
		if _knock_snd_t <= 0.0:
			_knock_snd_t = randf_range(5.0, 8.0)
			Sfx.play("knock", _door_pos(), 0.0, 0.05, 30.0)
		if _plea_t <= 0.0:
			_plea_t = randf_range(18.0, 24.0)
			Game.say(["\"Please. It's Tanaka, from 202. The water's in my flat.\"", "\"I've got nowhere to go. Just until the boats come.\"",
				"\"Hello? I can see your light under the door...\"", "The knocking gets weaker."].pick_random(), "warn")
		if _knock_left <= 0.0:
			refuse(true)


# --- Tanaka ----------------------------------------------------------------------

func _door_pos() -> Vector3:
	var d = guard.nodes.get("front_door")
	return (d.global_position if d else Vector3(3.3, 0, 7.3)) + Vector3(0, 1.2, 0.3)


func is_knocking() -> bool:
	return _knocking


## Smoke test / debugging: he knocks right now.
func begin_knock() -> void:
	_knocking = true
	Game.flags["tanaka"] = "knocking"
	_knock_left = scenario().TANAKA_WAIT
	_knock_snd_t = 0.0
	_plea_t = 6.0
	Sfx.play("knock", _door_pos(), 2.0, 0.05, 30.0)
	Game.say("Someone is knocking at the front door. A man's voice, hoarse: \"Hello? Is anyone in 303?\"", "danger")


func door_prompt(alt: bool) -> String:
	if alt or not _knocking:
		return ""
	return "Talk to him through the door"


func door_status() -> String:
	if _knocking:
		return "(someone is knocking)"
	if Game.flags.get("tanaka") == "in":
		return "(locked; Tanaka is with you)"
	return "(steel, locked)"


func door_perform(alt: bool) -> void:
	if alt or not _knocking:
		return
	open_choice()


## The moral choice: a sign-style card with both options and what they cost.
func open_choice() -> void:
	var s := scenario()
	var night2 := Game.day >= 2
	var text := ("Through the peephole: an old man in a soaked cardigan, holding a plastic bag of photographs over his head. Behind him the stairwell light is out and you can hear water.\n\n\"It's Tanaka, from 202, below you. The water came in an hour ago. It's over the kotatsu. Please. Just until the boats come.\"" if not night2 else
		"Through the peephole: an old man in a soaked cardigan, shivering, holding a plastic bag over his head.\n\n\"It's Tanaka, from 202. I've been on the stairs since last night. The water's still coming up. Please. Just until the boats come.\"")
	Game.choice_requested.emit({
		"jp": "隣人",
		"en": "Someone at the door",
		"text": text,
		"options": [
			{"label": "ドアを開ける   Let him in", "note": "Every morning: -%d food, -%d water. He brings %d materials, finds %d more each day, and knows things." % [s.GUEST_FOOD, s.GUEST_WATER, s.GUEST_GIFT, s.GUEST_DAILY], "call": let_in, "kind": "good"},
			{"label": "開けない   Keep the door shut", "note": "Your supplies stay yours. He'll have to find somewhere else.", "call": refuse.bind(false), "kind": "warn"},
		],
	})


func let_in() -> void:
	if not _knocking:
		return
	_knocking = false
	Game.flags["tanaka"] = "in"
	Game.materials += scenario().GUEST_GIFT
	Sfx.play("door_open", _door_pos(), -2.0)
	Game.say("You unhook the door guard. Tanaka steps into the genkan, dripping, and bows again and again. He's brought his tool bag (+%d materials)." % scenario().GUEST_GIFT, "good")
	Game.stats_changed.emit()
	await get_tree().create_timer(1.2).timeout
	if Game.is_alive_phase():
		Game.find_clue("tanaka_story")


func refuse(timed_out: bool) -> void:
	if not _knocking:
		return
	_knocking = false
	Game.flags["tanaka"] = "refused"
	if timed_out:
		Game.say("The knocking stops. Slow, wet footsteps go back down the stairs, towards the water.", "warn")
	else:
		Game.say("\"...I understand. I'm sorry to have bothered you.\" Slow, wet footsteps go back down the stairs.", "warn")
	Game.stats_changed.emit()


# --- The balcony ---------------------------------------------------------------------

func loose_on_balcony() -> bool:
	return _loose


func _can_signal() -> bool:
	var s := scenario()
	return (Game.has_insight("signal") and not Game.flags.has("signal")
		and Game.storm_level < 0.35 and Game.total_minutes() > 1440.0 and Game.total_minutes() < s.SIGNAL_BY)


func balcony_prompt() -> String:
	if _loose:
		return "Bring the pots and drying rack inside"
	if _can_signal():
		if Game.phase == Game.Phase.DAY:
			return "Hang a white sheet from the railing (rescue signal)"
		if Game.phone_battery >= scenario().SIGNAL_LIGHT_COST:
			return "Flash SOS at the street with the phone light (%d%% battery)" % int(scenario().SIGNAL_LIGHT_COST)
	return ""


func balcony_duration() -> float:
	return 5.0 if _loose else 3.5


func balcony_perform() -> void:
	if _loose:
		_loose = false
		for n in _loose_nodes:
			n.visible = false
		Game.say("You drag the flower pots and the drying rack in off the balcony. Nothing of yours will go through the glass tonight.", "good")
		Game.stats_changed.emit()
		return
	if not _can_signal():
		return
	if Game.phase != Game.Phase.DAY:
		drain_battery(scenario().SIGNAL_LIGHT_COST / battery_mult())
	signal_rescue()


## A crew below has seen you: the boat comes a day early.
func signal_rescue() -> void:
	Game.flags["signal"] = true
	Game.nights_override = mini(scenario().NIGHTS_TO_SURVIVE, 3)
	Sfx.play("boat", Vector3(3.2, -6.0, -12.0), -8.0, 0.0, 60.0)
	Game.say("Below, a boat crew in orange waves back and shouts something. You catch \"...tomorrow, first light!\" Rescue at dawn on day %d." % (Game.nights_goal() + 1), "good")
	Game.stats_changed.emit()


func _loose_fly() -> void:
	var s := scenario()
	_loose = false
	for n in _loose_nodes:
		n.visible = false
	var dmg: float = guard.hit("balcony_door", s.LOOSE_HIT)
	Game.say("A gust tears your own flower pots and drying rack off the balcony and hurls them into the glass!", "danger")
	if dmg > 0.0:
		Game.shake.emit(0.3, 0.3)


func on_window_broken(o: Node, lvl: int) -> void:
	var s := scenario()
	Game.shake.emit(0.6, 0.5)
	Game.say("The %s blows in! Rain and wind roar into the flat." % guard.lc(o.display_name), "danger")
	if player and player.global_position.distance_to(o.global_position) < s.SHATTER_RADIUS:
		var hurt: float = s.SHATTER_HURT * s.SHATTER_HURT_MULT[clampi(lvl, 0, 2)]
		if hurt > 0.0:
			var key := "glass_sleep" if Game.player_sleeping else "glass"
			Game.damage(hurt, Game.death_text(key) % guard.lc(o.display_name))
		elif lvl == 1:
			Game.say("The tape holds the shards together. The pane falls in in one sagging sheet.", "info")
	if Game.food > 0 and Game.rng.randf() < 0.5:
		Game.food -= 1
		Game.say("Rain sheets across the floor and soaks a box of food.", "warn")
	Game.stats_changed.emit()


# --- The sink and the phone (fixture hooks) -------------------------------------------

## utilities.gd asks whether Tide takes over this fixture right now.
func handles(o: Node, _alt: bool) -> bool:
	return o.get("kind") == "tap" and Game.water_note != ""


func get_prompt(_o: Node, alt: bool) -> String:
	if alt:
		return "Drink it unboiled (risky)" if Game.sick_left <= 0.0 else ""
	if not Game.gas_valve_open:
		return ""
	if _boils.get(Game.day, 0) >= scenario().BOILS_PER_DAY:
		return ""
	return "Boil a pot of tap water on the stove (+%d water)" % scenario().BOIL_WATER


func get_status(_o: Node) -> String:
	if not Game.gas_valve_open:
		return "(brown water, and no gas to boil it)"
	if _boils.get(Game.day, 0) >= scenario().BOILS_PER_DAY:
		return "(barely a trickle: try tomorrow)"
	return "(brown, smells of drains: boil it)"


func get_duration(_o: Node, alt: bool) -> float:
	return 1.5 if alt else 6.0


func get_noise(_o: Node, _alt: bool) -> float:
	return 1.0


func get_hold_sound(_o: Node, alt: bool) -> String:
	return "" if alt else "water_pour"


func perform(_o: Node, alt: bool) -> void:
	var s := scenario()
	if alt:
		Game.thirst = min(100.0, Game.thirst + s.RAW_THIRST)
		Game.sick_left = s.SICK_MINUTES
		Game.say("You drink the brown water straight from the tap. It tastes of mud and pipes. Within the hour your stomach is cramping.", "warn")
	else:
		_boils[Game.day] = _boils.get(Game.day, 0) + 1
		Game.water += s.BOIL_WATER
		Game.say("You boil a pot of the brown water and strain it through a towel. (+%d water)" % s.BOIL_WATER, "good")
	Game.stats_changed.emit()


## clue_source.gd: the phone's second action is plugging it in.
func alt_prompt(_o: Node) -> String:
	if not Game.power_on:
		return ""
	return "Unplug the phone" if Game.phone_plugged else "Plug the phone in to charge"


func alt_status(_o: Node) -> String:
	var s := "phone %d%%" % int(Game.phone_battery)
	if Game.phone_battery <= 0.0:
		return "(battery dead)"
	if Game.phone_plugged and Game.power_on:
		s += ", charging"
	return "(%s)" % s


func alt_flag(_o: Node) -> String:
	if Game.has_insight("prepared_storm") and Game.power_on and not Game.phone_plugged and Game.phone_battery < 95.0:
		return "UNPLUGGED"
	return ""


func alt_perform(_o: Node) -> void:
	if not Game.power_on:
		return
	Game.phone_plugged = not Game.phone_plugged
	if Game.phone_plugged:
		Game.say("You plug the phone in at the bedside. (%d%%)" % int(Game.phone_battery), "good")
	else:
		Game.say("You unplug the phone. (%d%%)" % int(Game.phone_battery), "info")
	Game.stats_changed.emit()


# --- HUD -------------------------------------------------------------------------

## Warning lines for the HUD, in the order they matter.
func info_lines() -> Array:
	var s := scenario()
	var lines: Array = []
	var now := Game.total_minutes()
	if _knocking:
		lines.append("Someone is knocking at the front door")
	if _broken_count() > 0 and Game.storm_level > 0.1:
		lines.append("A window is open to the storm: board it over")
	if Game.sick_left > 0.0:
		lines.append("Stomach cramps (%dh): the raw water" % int(ceil(Game.sick_left / 60.0)))
	if Game.phone_battery <= 0.0:
		lines.append("Phone dead: no light, no news" + (" · crank it [%s]" % Game.glyph("mask") if Game.has_crank else ""))
	if Game.has_insight("storm_forecast"):
		var txt := "台風 Wind: %s" % s.wind_label(Game.storm_level)
		if now < 28 * 60:
			txt += " · peak tonight 23:00-04:00"
		elif now < 1440 + 26 * 60:
			txt += " · back side: night 2, 20:00-02:00"
		elif Game.storm_level > 0.02:
			txt += " · calm by day 3, 14:00"
		lines.append(txt)
	if Game.has_insight("water_level"):
		var d := Game.flood_depth
		var where := "dry"
		if d >= s.SECOND_FLOOR:
			where = "2F flooded, 3F stays dry"
		elif d >= 0.1:
			where = "ground floor under water"
		lines.append("浸水 Street flood: %.1f m (%s)" % [d, where])
	if Game.has_insight("water_time") and Game.water_running:
		lines.append("Tap water turns bad: day 2, 06:00")
	if Game.has_insight("wind_side") and Game.phase == Game.Phase.DAY:
		var tonight := _tonight_hits()
		var parts: Array = []
		for id in tonight:
			if tonight[id] >= 0.6:
				parts.append("%s ~%d" % [guard.name_of(id), int(round(tonight[id]))])
		if not parts.is_empty():
			lines.append("Tonight's hits: " + ", ".join(parts))
	if Game.flags.has("signal"):
		lines.append("Signalled: the boat comes at dawn on day %d" % (Game.nights_goal() + 1))
	elif Game.has_insight("signal") and now < s.SIGNAL_BY:
		lines.append("Hang a white sheet from the balcony once the wind drops" if not _can_signal() else "The wind has dropped: signal the boats from the balcony door")
	if Game.has_insight("rescue_day"):
		var left: int = Game.nights_goal() - Game.day + (1 if Game.phase == Game.Phase.DAY else 0)
		lines.append("SDF boats at dawn on day %d (%d night%s to go)" % [Game.nights_goal() + 1, left, "" if left == 1 else "s"])
	if Game.flags.get("tanaka") == "in":
		lines.append("Tanaka is staying: -1 food, -1 water each morning")
	return lines


## Expected debris hits tonight per point (the "where the wind hits" insight).
func _tonight_hits() -> Dictionary:
	var s := scenario()
	var start := (Game.day - 1) * 1440.0 + Game.NIGHT_START
	var gusts := 0.0
	var t := start
	while t < start + 600.0:
		gusts += s.GUSTS_PER_HOUR * storm_at(t) * 10.0 / 60.0
		t += 10.0
	var total := 0.0
	for w in s.GUST_WEIGHTS.values():
		total += w
	var out := {}
	for id in s.GUST_WEIGHTS:
		out[id] = gusts * s.GUST_WEIGHTS[id] / total
	return out


# --- Visuals -----------------------------------------------------------------------

func _build_visuals() -> void:
	# Rain: thin streaks driven sideways by the wind, beyond the balcony, just
	# past the railing and beyond the corridor. Two tiers, light and heavy.
	var streak := BoxMesh.new()
	streak.size = Vector3(0.008, 0.55, 0.008)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.7, 0.75, 0.82, 0.3)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = rm
	for spec in [
		[Vector3(3.2, 3.5, -5.0), Vector3(10.0, 4.0, 3.5), 900, 0.03],
		[Vector3(3.2, 2.0, -1.9), Vector3(4.0, 1.4, 0.35), 220, 0.03],
		[Vector3(5.0, 2.5, 10.5), Vector3(9.0, 3.0, 1.5), 300, 0.03],
		[Vector3(3.2, 3.5, -5.0), Vector3(10.0, 4.0, 3.5), 1400, 0.45],
		[Vector3(3.2, 2.0, -1.9), Vector3(4.0, 1.4, 0.35), 260, 0.45],
	]:
		var p := CPUParticles3D.new()
		p.mesh = streak
		p.amount = spec[2]
		p.lifetime = 0.8
		p.preprocess = 0.8
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = spec[1]
		p.direction = Vector3(0.45, -1.0, 0.3)
		p.spread = 6.0
		p.gravity = Vector3(0, -9.8, 0)
		p.initial_velocity_min = 9.0
		p.initial_velocity_max = 12.0
		p.particle_flag_align_y = true
		p.position = spec[0]
		p.emitting = false
		p.local_coords = false
		add_child(p)
		_rain.append([p, spec[3]])
	# Debris: leaves, paper, plastic sheeting and the odd sign panel, tumbling
	# across the gap in front of the balcony.
	var bits := QuadMesh.new()
	bits.size = Vector2(0.14, 0.09)
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.roughness = 0.9
	bits.material = bm
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.32, 0.36, 0.2))   # leaves
	ramp.set_color(1, Color(0.85, 0.85, 0.82))  # paper and plastic
	ramp.add_point(0.4, Color(0.45, 0.33, 0.2))
	ramp.add_point(0.7, Color(0.25, 0.4, 0.6))  # a blue tarp scrap
	var panel := BoxMesh.new()
	panel.size = Vector3(0.45, 0.02, 0.3)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.6, 0.6, 0.62)
	pm.metallic = 0.6
	pm.roughness = 0.4
	panel.material = pm
	for spec in [[bits, 70, 0.4, Vector3(-9.0, 2.5, -4.5), Vector3(1.5, 3.5, 3.0)],
			[panel, 5, 0.75, Vector3(-10.0, 3.0, -6.5), Vector3(1.0, 2.5, 3.0)]]:
		var p := CPUParticles3D.new()
		p.mesh = spec[0]
		p.amount = spec[1]
		p.lifetime = 2.6
		p.preprocess = 2.6
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = spec[4]
		p.direction = Vector3(1.0, 0.12, 0.18)
		p.spread = 18.0
		p.gravity = Vector3(0, -1.5, 0)
		p.initial_velocity_min = 8.0
		p.initial_velocity_max = 15.0
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.angle_max = 360.0
		if spec[0] == bits:
			p.color_initial_ramp = ramp
		else:
			p.particle_flag_rotate_y = true
		p.position = spec[3]
		p.emitting = false
		p.local_coords = false
		add_child(p)
		_debris.append([p, spec[2]])
	# The flood: a dark, glossy, slowly moving sheet over the street.
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(320, 320)
	_water.mesh = plane
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.2, 0.17, 0.12)
	_water_mat.roughness = 0.07
	_water_mat.metallic_specular = 0.7
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = noise
	_water_mat.normal_enabled = true
	_water_mat.normal_texture = nt
	_water_mat.normal_scale = 0.6
	_water_mat.uv1_scale = Vector3(60, 60, 1)
	_water.material_override = _water_mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.position = Vector3(5, _water_y, 0)
	_water.visible = false
	add_child(_water)
	# What's on the balcony before the storm: two flower pots, a bucket and a
	# folding drying rack. R at the balcony door brings them in.
	var pot_tc := Color(0.62, 0.36, 0.24)
	for x in [0.55, 0.95]:
		var pot := Node3D.new()
		pot.add_child(_cyl(0.13, 0.1, 0.24, pot_tc, Vector3(0, 0.12, 0)))
		pot.add_child(_cyl(0.11, 0.11, 0.02, Color(0.25, 0.2, 0.15), Vector3(0, 0.235, 0)))
		pot.add_child(Props.box(Vector3(0.18, 0.28, 0.12), Color(0.3, 0.45, 0.22), Vector3(0, 0.38, 0)))
		pot.position = Vector3(x, -0.02, -1.25)
		add_child(pot)
		_loose_nodes.append(pot)
	var bucket := _cyl(0.15, 0.12, 0.28, Color(0.25, 0.45, 0.75), Vector3(4.2, 0.12, -1.25))
	add_child(bucket)
	_loose_nodes.append(bucket)
	var rack := Node3D.new()
	for sx in [-0.4, 0.4]:
		var leg := Props.fbox(Vector3(0.02, 1.05, 0.02), "aluminium", Vector3(sx, 0.52, 0))
		leg.rotation.x = 0.25
		rack.add_child(leg)
		var leg2 := Props.fbox(Vector3(0.02, 1.05, 0.02), "aluminium", Vector3(sx, 0.52, 0))
		leg2.rotation.x = -0.25
		rack.add_child(leg2)
	for y in [0.75, 1.0]:
		rack.add_child(Props.fbox(Vector3(0.84, 0.015, 0.015), "aluminium", Vector3(0, y, 0)))
	rack.add_child(Props.box(Vector3(0.35, 0.4, 0.01), Color(0.85, 0.85, 0.9), Vector3(-0.15, 0.78, 0.0)))  # a forgotten towel
	rack.position = Vector3(2.4, -0.02, -0.85)
	add_child(rack)
	_loose_nodes.append(rack)
	# Wind around the building (everywhere) and rain on the balcony glass.
	_wind_snd = AudioStreamPlayer.new()
	_wind_snd.stream = Sfx._pick("wind_storm")
	_wind_snd.bus = "Ambience"
	_wind_snd.volume_db = -80.0
	add_child(_wind_snd)
	var door = guard.nodes.get("balcony_door")
	if door:
		_rain_snd = Sfx.loop_on("rain_glass", door, -80.0, Vector3(0, 1.2, 0))
		if _rain_snd:
			_rain_snd.max_distance = 14.0


func _cyl(top: float, bottom: float, h: float, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = Props.mat(c)
	mi.position = pos
	return mi


func _update_visuals(delta: float) -> void:
	var w := Game.storm_level
	for entry in _rain:
		entry[0].emitting = w >= entry[1]
	for entry in _debris:
		entry[0].emitting = w >= entry[1]
	var slant := 0.25 + w * 0.6
	for entry in _rain:
		entry[0].direction = Vector3(slant, -1.0, 0.3)
	var want: float = STREET_Y + Game.flood_depth * FLOOD_VIS_SCALE
	_water_y = move_toward(_water_y, want, delta * 0.4) if absf(_water_y - want) < 2.0 else want
	_water.visible = Game.flood_depth > 0.02
	_water.position.y = _water_y
	var drift := Time.get_ticks_msec() * 0.00002
	_water_mat.uv1_offset = Vector3(drift * (1.0 + w), drift * 0.6, 0)
	if _wind_snd and _wind_snd.stream:
		var vol := -80.0 if not Game.is_alive_phase() or w < 0.02 else linear_to_db(clampf(0.15 + w * 0.85, 0.0, 1.0)) - 4.0
		if _broken_count() > 0:
			vol += 4.0
		if vol > -79.0 and not _wind_snd.playing:
			_wind_snd.play()
		_wind_snd.volume_db = move_toward(_wind_snd.volume_db, vol, 30.0 * delta)
		if _wind_snd.volume_db <= -79.0 and _wind_snd.playing:
			_wind_snd.stop()
	if is_instance_valid(_rain_snd):
		var rv := -80.0 if not Game.is_alive_phase() or w < 0.03 else linear_to_db(clampf(0.2 + w * 0.8, 0.0, 1.0)) - 2.0
		_rain_snd.volume_db = move_toward(_rain_snd.volume_db, rv, 30.0 * delta)
	_env_t -= delta
	if _env and _env_t <= 0.0:
		# Grey rain haze that closes in with the wind; a thin mist over the water after.
		_env_t = 0.25
		_env.fog_enabled = true
		_env.fog_light_color = Color(0.26, 0.29, 0.33)
		_env.fog_light_energy = 0.35
		_env.fog_sun_scatter = 0.0
		_env.fog_density = 0.006 + w * 0.03
		_env.fog_sky_affect = 0.85
