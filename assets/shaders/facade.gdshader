// Keep Living: distant apartment blocks. A box mesh whose side faces get a
// facade texture (2 bays x 2 floors per tile) fitted so a whole number of
// bays and floors spans each face, a plainer ground floor, a concrete roof,
// and night-lit windows picked per window from the instance seed.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float floor_h = 2.9;
uniform float bay_w = 3.4;
uniform float ground_h = 3.4;

instance uniform vec3 bsize = vec3(10.0, 20.0, 10.0);
instance uniform vec4 tone : source_color = vec4(1.0);
instance uniform float seed = 0.0;
instance uniform float lit = 0.3;   // fraction of windows lit

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(ln);
	vec3 macro = texture(macro_tex, wp.xz * 0.02 + wp.y * 0.013).rgb;
	if (abs(n.y) > 0.5) {
		ALBEDO = texture(roof_tex, lp.xz * 0.3).rgb * 0.8 * tone.rgb;
		ROUGHNESS = 0.9;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		float face_w = abs(n.z) > 0.5 ? bsize.x : bsize.z;
		float u = abs(n.z) > 0.5 ? lp.x * sign(n.z) : -lp.z * sign(n.x);
		u += face_w * 0.5;
		float v = lp.y + bsize.y * 0.5 - ground_h;  // metres above the ground floor
		float bays = max(1.0, floor(face_w / bay_w + 0.5));
		float bw = face_w / bays;
		vec2 uv = vec2(u / (bw * 2.0), 1.0 - v / (floor_h * 2.0));
		vec3 alb = texture(albedo_tex, uv).rgb;
		vec3 orm = texture(orm_tex, uv).rgb;
		float glass = orm.b;
		// Lace curtains / blinds behind some of the glass, per window.
		vec2 wcell = vec2(floor(u / bw * 2.0), floor(v / floor_h));
		float ch = fract(sin(dot(wcell, vec2(41.3, 289.1)) + seed * 7.7) * 15731.743);
		vec3 curtain = mix(vec3(0.42, 0.4, 0.36), vec3(0.3, 0.32, 0.33), step(0.5, fract(ch * 7.0)));
		alb = mix(alb, curtain, step(ch, 0.45) * glass * 0.55);
		// Ground floor: entrance hall / shutters, darker plain band.
		float ground = 1.0 - step(0.0, v);
		// Don't put half-windows on the top floor: plain parapet above the last full floor.
		float floors = floor((bsize.y - ground_h) / floor_h);
		float top = step(floors * floor_h, v);
		float plain = max(ground, top);
		vec3 wall = texture(roof_tex, vec2(u, v) * 0.4).rgb;
		alb = mix(alb, wall * (ground > 0.5 ? 0.45 : 0.85), plain);
		glass *= 1.0 - plain;
		alb *= tone.rgb * (0.92 + macro.r * 0.16);
		ALBEDO = alb;
		ROUGHNESS = mix(orm.g, 0.9, plain);
		NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), plain);
		vec2 cell = vec2(floor(u / bw * 2.0), floor(v / floor_h));
		float h = hash(cell + n.xz * 13.0);
		float on = step(h, lit) * glass;
		vec3 warm = vec3(1.0, 0.78, 0.5);
		vec3 cool = vec3(0.8, 0.9, 1.0);
		vec3 lc = mix(warm, cool, step(0.5, hash(cell * 1.7 + 3.1)));
		EMISSION = lc * on * (0.6 + 0.8 * hash(cell + 9.0)) * 0.8;
	}
	SPECULAR = 0.5;
}
