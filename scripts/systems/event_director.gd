extends Node
## Fires the run's scheduled events (earthquakes, utilities failing, mail)
## when the clock passes them. Works with time skips: anything passed fires.

const WARNING_SECONDS := 6.0
const PEAK_DELAY := 1.3  # seconds between the quake starting and furniture falling

var player: Node3D
var _warned := {}


func _process(_delta: float) -> void:
	if not Game.is_alive_phase():
		return
	var now := Game.total_minutes()
	var warn_ahead := WARNING_SECONDS * Game.minutes_per_second()
	for ev in Game.scheduled_events:
		if ev["type"] == "quake" and Game.has_insight("aftershocks") and not _warned.has(ev["at"]):
			if now >= ev["at"] - warn_ahead and now < ev["at"]:
				_warned[ev["at"]] = true
				Game.earthquake_warning.emit()
				Sfx.play("eew_alarm", null, -2.0, 0.0)
				Game.say("EARTHQUAKE EARLY WARNING. Strong shaking expected. Get clear of tall furniture!", "danger")
	while Game.scheduled_events.size() > 0 and now >= Game.scheduled_events[0]["at"]:
		var ev: Dictionary = Game.scheduled_events.pop_front()
		_fire(ev)
		if not Game.is_alive_phase():
			return


func _fire(ev: Dictionary) -> void:
	match ev["type"]:
		"quake":
			_quake(ev.get("strength", 1.0))
		"water_cut":
			Game.water_running = false
			Sfx.play("pipes_knock", Vector3(1.0, 1.5, 4.5), 0.0)
			Game.say("The pipes knock and shudder. The water has stopped.", "warn")
			Game.world_changed.emit()
		"power_cut":
			Game.power_on = false
			Sfx.play("power_down", null, -4.0, 0.0)
			Game.say("The lights die. The fridge falls silent. The city goes dark around you.", "warn")
			Game.world_changed.emit()
		"water_taint":
			# The tap still runs, but what comes out isn't safe any more.
			Game.water_running = false
			Game.water_note = ev.get("note", "undrinkable")
			Sfx.play("pipes_knock", Vector3(4.65, 1.0, 5.06), -4.0)
			Game.say(ev.get("text", "The water from the tap has turned grey and gritty. It isn't safe to drink any more."), "warn")
			Game.world_changed.emit()
		"mail":
			Game.say(ev.get("text", ""), "info")
		"say":
			Game.say(ev.get("text", ""), ev.get("kind", "info"))
		_:
			Game.scenario_event.emit(ev)


func _quake(strength: float) -> void:
	Game.say("The building lurches. EARTHQUAKE!", "danger")
	if Game.player_sleeping:
		Game.say("You jolt awake on the bed. MOVE!", "danger")
	Game.earthquake.emit(strength)
	Sfx.play("quake_rumble", null, 2.0 * strength, 0.03)
	Game.shake.emit(0.35 * strength, 3.5)
	await get_tree().create_timer(PEAK_DELAY).timeout
	if not Game.is_alive_phase():
		return
	for h in get_tree().get_nodes_in_group("hazard"):
		h.on_quake(player)
		if not Game.is_alive_phase():
			return
	if Game.gas_valve_open and not Game.gas_leaking:
		Game.gas_leaking = true
		Game.gas_leak_left = Game.GAS_LEAK_SECONDS
		Game.say("When the shaking stops, you smell gas.", "danger")
	Game.stats_changed.emit()
