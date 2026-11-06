// Keep Living: triplanar PBR surface for boxes and untextured meshes.
//
// Texture set from assets/textures (albedo, OpenGL normal, ORM = AO/rough/metal)
// projected along the three axes, in world space (static architecture: lines up
// across pieces) or object space (things that move). A low-frequency "macro"
// noise, sampled at a much larger scale, varies tone and roughness so big
// surfaces don't show the tile repeating; `detile` also blends in a second,
// rotated and rescaled sample of the albedo for unstructured materials.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 1.0;          // tiles per metre
uniform bool world_space = true;
uniform float sharpness = 8.0;
uniform float normal_strength = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metallic = 0.0;
uniform bool metal_from_tex = false;   // ORM.b * metallic
uniform float specular = 0.5;
uniform float ao_strength = 1.0;
uniform float macro_scale = 0.12;      // macro tiles per metre
uniform float macro_tone = 0.06;       // +- albedo brightness
uniform float macro_dirt = 0.0;        // darker, rougher patches (outdoor grime, traffic)
uniform float macro_rough = 0.06;
uniform float detile = 0.0;
uniform float clearcoat = 0.0;
uniform float clearcoat_roughness = 0.2;
uniform float rim = 0.0;               // fabric sheen

varying vec3 tp_pos;
varying vec3 tp_nrm;
varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (world_space) {
		tp_pos = w_pos;
		tp_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		tp_pos = VERTEX;
		tp_nrm = NORMAL;
	}
}

vec3 unpack_n(vec4 t) {
	vec3 n = t.xyz * 2.0 - 1.0;
	n.y = -n.y;  // OpenGL map, v grows along the world axis
	n.xy *= normal_strength;
	return n;
}

void fragment() {
	vec3 n = normalize(tp_nrm);
	vec3 w = pow(abs(n), vec3(sharpness));
	w /= (w.x + w.y + w.z);
	vec3 s = sign(n + vec3(1e-4));
	vec3 p = tp_pos * uv_scale;
	vec2 uvx = vec2(p.z * s.x, p.y);
	vec2 uvy = vec2(p.x * s.y, p.z);
	vec2 uvz = vec2(-p.x * s.z, p.y);

	vec4 alb = vec4(0.0);
	vec4 orm = vec4(0.0);
	vec3 tnx = vec3(0.0), tny = vec3(0.0), tnz = vec3(0.0);
	if (w.x > 0.01) {
		alb += texture(albedo_tex, uvx) * w.x;
		orm += texture(orm_tex, uvx) * w.x;
		tnx = unpack_n(texture(normal_tex, uvx));
	}
	if (w.y > 0.01) {
		alb += texture(albedo_tex, uvy) * w.y;
		orm += texture(orm_tex, uvy) * w.y;
		tny = unpack_n(texture(normal_tex, uvy));
	}
	if (w.z > 0.01) {
		alb += texture(albedo_tex, uvz) * w.z;
		orm += texture(orm_tex, uvz) * w.z;
		tnz = unpack_n(texture(normal_tex, uvz));
	}

	// Macro variation, always in world space so neighbouring boxes agree.
	vec3 mn = normalize(tp_nrm);
	vec3 mw = abs(world_space ? mn : normalize((MODEL_MATRIX * vec4(mn, 0.0)).xyz));
	mw = pow(mw, vec3(4.0));
	mw /= (mw.x + mw.y + mw.z);
	vec3 mp = w_pos * macro_scale;
	vec3 macro = texture(macro_tex, mp.zy).rgb * mw.x + texture(macro_tex, mp.xz).rgb * mw.y + texture(macro_tex, mp.xy).rgb * mw.z;

	if (detile > 0.0) {
		// Second sample rotated ~37 deg and scaled by 0.71, blended by the macro noise.
		mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * 0.71;
		vec4 alb2 = texture(albedo_tex, r * uvx + 0.37) * w.x + texture(albedo_tex, r * uvy + 0.37) * w.y + texture(albedo_tex, r * uvz + 0.37) * w.z;
		alb = mix(alb, alb2, smoothstep(0.35, 0.65, macro.g) * detile);
	}

	vec3 col = alb.rgb * tint.rgb;
	col *= 1.0 + (macro.r - 0.5) * 2.0 * macro_tone;
	float dirt = smoothstep(0.45, 0.85, macro.b) * macro_dirt;
	col *= 1.0 - dirt;
	ALBEDO = col;

	float rough = orm.g * rough_mul + rough_add + (macro.g - 0.5) * 2.0 * macro_rough + dirt * 0.3;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal_from_tex ? orm.b * metallic : metallic;
	SPECULAR = specular;
	AO = mix(1.0, orm.r, ao_strength);
	AO_LIGHT_AFFECT = 0.0;
	if (clearcoat > 0.0) {
		CLEARCOAT = clearcoat;
		CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	}
	if (rim > 0.0) {
		RIM = rim;
		RIM_TINT = 0.6;
	}

	// Whiteout blend of the three tangent-space normals (Golus 2017).
	vec3 bn = vec3(0.0);
	if (w.x > 0.01) {
		tnx.x *= s.x;
		vec3 t = vec3(tnx.xy + n.zy, abs(tnx.z) * n.x);
		bn += t.zyx * w.x;
	}
	if (w.y > 0.01) {
		tny.x *= s.y;
		vec3 t = vec3(tny.xy + n.xz, abs(tny.z) * n.y);
		bn += t.xzy * w.y;
	}
	if (w.z > 0.01) {
		tnz.x *= -s.z;
		vec3 t = vec3(tnz.xy + n.xy, abs(tnz.z) * n.z);
		bn += t.xyz * w.z;
	}
	bn = normalize(bn);
	if (!world_space) {
		bn = normalize((MODEL_MATRIX * vec4(bn, 0.0)).xyz);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
}
