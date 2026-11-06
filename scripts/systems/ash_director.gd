extends Node
## Ash (scenario_ash.gd): ashfall outside, ash leaking in through the gaps,
## the air you breathe, masks wearing out, the balcony filling up, rain, and
## tremors shaking the tape loose. Integrates on Game.minutes_advanced, so a
## rest on the bed costs exactly what staying awake would.

const Props := preload("res://scripts/world/props.gd")
const STEP := 5.0  # integrate in game-minute steps so long skips stay accurate

var seal          # scripts/systems/seal.gd
var apartment: Node3D
var player: Node3D
var looters: Node  # LooterDirector, for shouting through the door

var _air_warned := 0       # 0 fine, 1 gritty, 2 harmful
var _load_warned := 0
var _mask_warned := false
var _raining := false
var _particles: Array = []  # [CPUParticles3D, base amount]
var _ash_layer: MeshInstance3D
var _env: Environment
var _env_t := 0.0
var _cough_t := 0.0


func _ready() -> void:
	Game.minutes_advanced.connect(_on_minutes)
	Game.scenario_event.connect(_on_event)
	Game.earthquake.connect(_on_quake)
	_build_visuals()
	var we := get_parent().find_children("*", "WorldEnvironment", false, false)
	if not we.is_empty():
		_env = (we[0] as WorldEnvironment).environment
	Game.leak = seal.total_leak()


func scenario() -> Script:
	return Game.scenario


## Ashfall right now (0 before the plume arrives).
func ashfall() -> float:
	if not Game.ash_falling or Game.ash_forecast.is_empty():
		return 0.0
	return Game.ash_forecast[clampi(Game.day - 1, 0, Game.ash_forecast.size() - 1)]


func is_raining(total: float) -> bool:
	return Game.rain_window.size() == 2 and total >= Game.rain_window[0] and total < Game.rain_window[1]


func _on_event(ev: Dictionary) -> void:
	if ev["type"] == "ash_begins":
		Game.ash_falling = true
		Sfx.play("quake_rumble", null, -14.0, 0.0)
		Game.say("The sky to the southwest has turned brown. Fine grey ash begins to fall on the city.", "warn")
		Game.world_changed.emit()


func _on_quake(strength: float) -> void:
	await get_tree().create_timer(1.6).timeout
	if not Game.is_alive_phase():
		return
	var peeled: Array = seal.peel(Game.rng, 2 if strength >= 1.0 else 1)
	for id in peeled:
		Game.say("The shaking tore the tape loose on the %s." % seal.lc(seal.name_of(id)), "warn")
	Game.leak = seal.total_leak()


func _on_minutes(m: float) -> void:
	var s := scenario()
	var t0 := Game.total_minutes() - m
	var left := m
	while left > 0.0 and Game.is_alive_phase():
		var dt: float = min(STEP, left)
		left -= dt
		t0 += dt
		var rate := ashfall()
		var rain := is_raining(t0)
		if rain != _raining:
			_raining = rain
			if rain:
				Game.say("It starts to rain. Grey mud streaks the windows, and the ash on the balcony turns to wet cement.", "warn")
			else:
				Game.say("The rain stops. The ash on the balcony has set hard and heavy.", "info")
		Game.leak = seal.total_leak()
		var inflow: float = s.ASH_K_IN * rate * Game.leak * (s.RAIN_AIR_MULT if rain else 1.0)
		var eq: float = inflow / s.ASH_K_OUT
		Game.dust = clamp(eq + (Game.dust - eq) * exp(-s.ASH_K_OUT * dt), 0.0, 100.0)
		Game.ash_cm += rate * s.ASH_CM_PER_MIN * dt
		Game.balcony_load = min(s.LOAD_COLLAPSE, Game.balcony_load + rate * s.LOAD_PER_MIN * dt * (s.RAIN_LOAD_MULT if rain else 1.0))
		if Game.mask_left > 0.0:
			Game.mask_left = max(0.0, Game.mask_left - dt)
			if Game.mask_left <= 0.0:
				Game.say("Your mask is clogged with grey. Breathing through it is pointless now.", "warn")
		var air := Game.air_quality()
		if air < s.HARM_BELOW:
			var harm: float = (s.HARM_BELOW - air) / s.HARM_BELOW * s.HARM_PER_MIN * dt
			if Game.mask_left > 0.0:
				harm *= 1.0 - s.MASK_PROTECTION
			var cause := "ash"
			if Game.player_sleeping:
				cause = "ash_sleep"
			elif Game.leak > 4.5:
				cause = "ash_unsealed"
			Game.wear_down(harm, Game.death_text(cause))
		if Game.balcony_load >= s.LOAD_COLLAPSE:
			_collapse()
	_warnings()


func _warnings() -> void:
	if not Game.is_alive_phase():
		return
	var air := Game.air_quality()
	var lvl := 0
	if air < scenario().HARM_BELOW:
		lvl = 2
	elif air < 82.0:
		lvl = 1
	if lvl > _air_warned:
		if lvl == 1:
			Game.say("You can taste grit in the air. Ash is getting in somewhere.", "warn")
		else:
			var hint := " Put on a mask [%s]." % Game.glyph("mask") if Game.masks > 0 and Game.mask_left <= 0.0 else ""
			Game.say("Your throat burns with every breath. The air in here is hurting you.%s" % hint, "danger")
	if lvl < _air_warned and air > 88.0:
		_air_warned = 0
	else:
		_air_warned = max(_air_warned, lvl)
	var bl := Game.balcony_load
	if bl >= 60.0 and _load_warned < 1:
		_load_warned = 1
		Game.say("The balcony railing creaks under the weight of the ash.", "warn")
	elif bl >= 85.0 and _load_warned < 2:
		_load_warned = 2
		Sfx.play("pipes_knock", Vector3(4.55, 1.2, -0.3), -2.0)
		Game.say("The balcony door frame is groaning. Shovel the ash off before it gives! [%s at the balcony door]" % Game.glyph("interact_alt"), "danger")
	if bl < 50.0:
		_load_warned = 0


func _collapse() -> void:
	var s := scenario()
	Game.balcony_load = 30.0  # a slab of it slides off with the glass
	var door = apartment.barricades.get("balcony_door")
	Game.shake.emit(0.5, 0.6)
	if door and not door.broken:
		door.take_damage(99999.0)
	if player and door and player.global_position.distance_to(door.global_position) < 2.2:
		Game.damage(s.COLLAPSE_DAMAGE, Game.death_text("balcony"))
	Game.make_noise(door.global_position if door else Vector3.ZERO, 10.0)
	Game.leak = seal.total_leak()


## R at the balcony door: open it and shovel the ash over the railing.
func shovel_balcony() -> void:
	var s := scenario()
	var removed := Game.balcony_load
	Game.balcony_load = 0.0
	_load_warned = 0
	if ashfall() > 0.0:
		Game.dust = min(100.0, Game.dust + s.SWEEP_DUST)
	if seal.levels.get("balcony_door", 0) > 0:
		seal.set_level("balcony_door", seal.levels["balcony_door"] - 1)
	if Game.mask_left <= 0.0:
		Game.wear_down(6.0, Game.death_text("ash"))
		Game.say("You shovel the ash over the railing, coughing, eyes streaming. (%d%% load cleared)" % int(removed), "warn")
	else:
		Game.say("Behind your mask, you shovel the grey sludge over the railing. (%d%% load cleared)" % int(removed), "good")
	Game.leak = seal.total_leak()
	Game.stats_changed.emit()


func shout_at_looters() -> void:
	if looters:
		looters.shout()


# --- Visuals -------------------------------------------------------------------

func _build_visuals() -> void:
	# Falling ash: soft grey flakes in front of the balcony and past the corridor railing.
	var flake := QuadMesh.new()
	flake.size = Vector2(0.025, 0.025)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.6, 0.57, 0.85)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = fm
	for spec in [
		[Vector3(3.2, 4.5, -4.0), Vector3(9.0, 0.2, 3.5), 900],   # beyond the balcony
		[Vector3(3.2, 2.6, -1.9), Vector3(4.0, 0.1, 0.35), 160],  # just past the railing
		[Vector3(5.0, 4.0, 10.5), Vector3(9.0, 0.2, 1.5), 300],   # beyond the corridor
	]:
		var p := CPUParticles3D.new()
		p.mesh = flake
		p.amount = spec[2]
		p.lifetime = 9.0
		p.preprocess = 9.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = spec[1]
		p.direction = Vector3(0.15, -1, 0.05)
		p.spread = 12.0
		p.gravity = Vector3(0, -0.35, 0)
		p.initial_velocity_min = 0.35
		p.initial_velocity_max = 0.6
		p.position = spec[0]
		p.emitting = false
		p.local_coords = false
		add_child(p)
		_particles.append([p, spec[2]])
	# The grey layer building up on the balcony floor (top at -0.02).
	_ash_layer = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.3, 1.0, 1.42)
	_ash_layer.mesh = bm
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.5, 0.49, 0.47)
	am.roughness = 1.0
	_ash_layer.material_override = am
	_ash_layer.position = Vector3(3.185, -0.02, -0.76)
	_ash_layer.visible = false
	add_child(_ash_layer)


func _process(delta: float) -> void:
	var rate := ashfall()
	for entry in _particles:
		var p: CPUParticles3D = entry[0]
		p.emitting = rate > 0.0
		p.speed_scale = 0.8 + rate * 0.4
	var depth: float = clamp(Game.ash_cm * 0.01, 0.0, 0.14)
	_ash_layer.visible = depth > 0.002
	if _ash_layer.visible:
		_ash_layer.scale.y = depth
		_ash_layer.position.y = -0.02 + depth * 0.5
	_env_t -= delta
	if _env and _env_t <= 0.0:
		# Haze: thin brown-grey fog that thickens with the ashfall and the ash indoors.
		_env_t = 0.25
		_env.fog_enabled = Game.ash_falling
		_env.fog_light_color = Color(0.62, 0.46, 0.3)  # brown volcanic haze
		_env.fog_light_energy = 0.9
		_env.fog_density = 0.008 + rate * 0.02 + Game.dust * 0.0003
		_env.fog_sky_affect = 0.6
	# A cough now and then while the air is bad.
	if Game.is_alive_phase() and Game.air_quality() < scenario().HARM_BELOW and Game.mask_left <= 0.0:
		_cough_t -= delta
		if _cough_t <= 0.0:
			_cough_t = randf_range(14.0, 26.0)
			Sfx.play("cough", null, -4.0, 0.1)
			Game.say(["You cough. It tastes like a building site.", "Your eyes sting. Everything has a grey film on it.", "A coughing fit doubles you over."].pick_random(), "warn")
