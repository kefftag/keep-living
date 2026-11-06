extends Node3D
## Sky, sun, global illumination, exposure and post-processing.
##
## The sky blends three CC0 Poly Haven HDRIs (day / dusk / night, see
## assets/sky/CREDITS.md). Each is rotated so its sun lines up with the
## DirectionalLight, and the sun disc is clamped out of the sky so the
## DirectionalLight alone carries direct sunlight. Indoor bounce light is
## SDFGI; exposure adapts like an eye.
##
## Budget (1600x900, M1 Pro, vsync off): ~60-75 fps. Measured costs that
## shaped this: SSIL ~6 ms (off, SDFGI covers bounce), PCSS soft shadows on the
## sun ~5 ms and ~1 ms per ceiling light (off, PCF + blur instead), volumetric
## fog ~2 ms (off), half-resolution GI ~3 ms cheaper but dotted edge artifacts
## (off). project.godot: TAA, 8 SDFGI rays, 4k shadow maps, soft filter high.
##
## Sun path: the balcony (-Z) is the sunny side, +X east. Morning sun comes
## from the +X side of the balcony, evening sun from the -X side.

const SKY_SHADER := """
shader_type sky;

uniform sampler2D day_tex : filter_linear, repeat_enable;
uniform sampler2D dusk_tex : filter_linear, repeat_enable;
uniform sampler2D night_tex : filter_linear, repeat_enable;
uniform vec3 weights = vec3(1.0, 0.0, 0.0);   // day, dusk, night
uniform vec3 rotations = vec3(0.0);           // per-texture yaw, in turns
uniform vec3 tint : source_color = vec3(1.0);
uniform float sun_clamp = 24.0;               // keeps the HDRI sun out of GI / reflections
uniform float saturation = 0.7;               // Tokyo haze: less saturated than a clear veld sky

vec3 pano(sampler2D t, vec3 d, float rot) {
	vec2 uv = vec2(fract(atan(d.x, -d.z) / TAU + 0.5 + rot), acos(clamp(d.y, -1.0, 1.0)) / PI);
	return min(textureLod(t, uv, 0.0).rgb, vec3(sun_clamp));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 c = vec3(0.0);
	if (weights.x > 0.001) c += weights.x * pano(day_tex, d, rotations.x);
	if (weights.y > 0.001) c += weights.y * pano(dusk_tex, d, rotations.y);
	if (weights.z > 0.001) c += weights.z * pano(night_tex, d, rotations.z);
	// Below the horizon: darken towards the street (the skyline boxes cover most of it).
	c *= mix(0.35, 1.0, smoothstep(-0.25, 0.02, d.y));
	c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, saturation);
	COLOR = c * tint;
}
"""

# Where each HDRI's sun sits, as the panorama u coordinate (measured offline).
const DAY_SUN_U := 0.5947
const DUSK_SUN_U := 0.6113
const NIGHT_GLOW_U := 0.5977
# Outdoors is far brighter than a lamp-lit room (10 000+ lux vs ~300); auto
# exposure brings the interior back up, so windows read bright like in a photo.
const SKY_ENERGY := 8.0
const SUN_ENERGY := 14.0

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var cam_attr: CameraAttributesPractical
var _last_key := Vector4(-1, -1, -1, -1)
var _last_haze := -1.0
var _last_minutes := 0.0
var haze := 0.0  # 0 clear .. 1 thick volcanic ash overhead (Ash scenario); eased


## How much ash hangs in the sky right now (Ash scenario), 0..1.
static func ash_haze_target() -> float:
	if not Game.ash_falling or Game.ash_forecast.is_empty():
		return 0.0
	var rate: float = Game.ash_forecast[clampi(Game.day - 1, 0, Game.ash_forecast.size() - 1)]
	return clampf(0.45 + rate * 0.45, 0.0, 0.95)


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()

	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("day_tex", load("res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"))
	sky_mat.set_shader_parameter("dusk_tex", load("res://assets/sky/kloppenheim_06_puresky_1k.hdr"))
	sky_mat.set_shader_parameter("night_tex", load("res://assets/sky/kloppenheim_07_puresky_1k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Ambient and reflections come from the sky (SDFGI occludes it indoors).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# Global illumination: SDFGI for room-to-room bounce, fine cells for a 10 m flat.
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	env.sdfgi_bounce_feedback = 0.3  # more feedback snowballs the warm floor bounce onto white walls
	env.sdfgi_energy = 1.0
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1

	env.ssil_enabled = false  # SDFGI already covers bounce; SSIL cost ~6 ms on an M1 Pro
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	# Contact shadows in corners and under furniture.
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.15

	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		env.set_glow_level(i, i >= 2 and i <= 5)

	# Volumetric fog (sun shafts) was tried: barely visible indoors at this
	# exposure and ~2-3 ms a frame, so it stays off.

	we.environment = env

	# Eye-like adaptation from a bright window to a dark hallway.
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.4
	cam_attr.auto_exposure_speed = 0.6
	cam_attr.auto_exposure_min_sensitivity = 60.0
	cam_attr.auto_exposure_max_sensitivity = 1600.0
	we.camera_attributes = cam_attr
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	# Soft edges from the PCF filter + blur. A real angular size (PCSS) looks a bit
	# nicer but costs ~5 ms a frame on an M1 Pro, so the sun stays a point.
	sun.light_angular_distance = 0.0
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.35
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	update_daylight()


func _process(delta: float) -> void:
	# The sky browns over ~30 game minutes (game time, so rests and fast-forward keep up).
	var dm: float = clampf(Game.minutes - _last_minutes, 0.0, 600.0)
	_last_minutes = Game.minutes
	haze = move_toward(haze, ash_haze_target(), dm * 0.035 + delta * 0.02)
	update_daylight()


## Sun position for a clock time: azimuth from the balcony normal (-Z),
## positive towards -X (west), and elevation, both in degrees.
static func sun_angles(hour: float) -> Vector2:
	var az := clampf((hour - 12.0) * 14.0, -75.0, 75.0)
	var el := 52.0 * sin(PI * (hour - 5.5) / 13.5)  # rises 05:30, sets 19:00
	return Vector2(az, el)


static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func _u_of(d: Vector3) -> float:
	return atan2(d.x, -d.z) / TAU + 0.5


## Daylight follows the clock: day, golden dusk, blue twilight, city-lit night.
func update_daylight() -> void:
	var m := fmod(Game.minutes, 1440.0)
	var hour := m / 60.0
	var a := sun_angles(hour)
	var to_sun := _dir(a.x, maxf(a.y, 2.0))

	# Sky blend weights.
	var day_w := 0.0
	var dusk_w := 0.0
	var night_w := 0.0
	var sky_e := 1.0
	if hour >= 6.5 and hour < 16.5:
		day_w = 1.0
	elif hour >= 16.5 and hour < 18.0:
		var t := (hour - 16.5) / 1.5
		day_w = 1.0 - t
		dusk_w = t
		sky_e = lerpf(1.0, 0.7, t)
	elif hour >= 18.0 and hour < 20.0:
		var t := (hour - 18.0) / 2.0
		dusk_w = 1.0 - t
		night_w = t
		sky_e = lerpf(0.7, 0.08, smoothstep(0.0, 1.0, t))
	elif hour >= 5.0 and hour < 6.5:
		var t := (hour - 5.0) / 1.5
		dusk_w = t
		night_w = 1.0 - t
		sky_e = lerpf(0.08, 0.8, t)
	else:
		night_w = 1.0
		sky_e = 0.08

	# Sun (or, at night, a faint moon high over the balcony).
	var sun_dir := to_sun
	var color := Color(1.0, 0.95, 0.88)
	var energy := 0.0
	if a.y > 0.0:
		var low := clampf(1.0 - a.y / 25.0, 0.0, 1.0)  # warm and weak near the horizon
		color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.56, 0.3), low * low)
		energy = SUN_ENERGY * clampf(a.y / 8.0, 0.0, 1.0) * lerpf(1.0, 0.55, low)
	if night_w > 0.5:
		sun_dir = _dir(20.0, 50.0)
		color = Color(0.55, 0.65, 0.9)
		energy = 0.15 * night_w
	# Volcanic ash: a dim, orange-brown sun behind a brown overcast.
	if haze > 0.001:
		color = color.lerp(Color(1.0, 0.62, 0.38), haze)
		energy *= lerpf(1.0, 0.12, haze)
		sky_e *= lerpf(1.0, 0.35, haze)
	sun.light_color = color
	sun.light_energy = energy
	sun.visible = energy > 0.001
	if sun_dir.distance_to(-sun.global_transform.basis.z) > 0.0005:
		sun.global_transform.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)

	# Only touch the sky when it changed visibly (each change re-filters radiance).
	var key := Vector4(snappedf(day_w, 0.02), snappedf(dusk_w, 0.02), snappedf(sky_e, 0.01), snappedf(a.x, 1.0))
	if key != _last_key or absf(haze - _last_haze) > 0.02:
		_last_key = key
		_last_haze = haze
		sky_mat.set_shader_parameter("tint", Vector3(1, 1, 1).lerp(Vector3(0.78, 0.6, 0.44), haze))
		sky_mat.set_shader_parameter("saturation", lerpf(0.7, 0.35, haze))
		var sun_u := _u_of(_dir(a.x, 0.0))
		sky_mat.set_shader_parameter("weights", Vector3(day_w, dusk_w, night_w))
		sky_mat.set_shader_parameter("rotations", Vector3(DAY_SUN_U - sun_u, DUSK_SUN_U - sun_u, NIGHT_GLOW_U - _u_of(_dir(20.0, 0.0))))
		env.background_energy_multiplier = sky_e * SKY_ENERGY
