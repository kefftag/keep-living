// Keep Living: the reflective second pass of glass.gdshader, added on top.
// Black albedo, so only the specular (sky, lights, probes) is added; Fresnel
// is handled by the Schlick GGX specular term.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, specular_schlick_ggx, shadows_disabled;

uniform float roughness = 0.04;
uniform float strength = 1.0;
uniform float frost = 0.0;

void fragment() {
	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	ROUGHNESS = mix(roughness, 0.45, frost);
	SPECULAR = 0.5 * strength;
}
