// Keep Living: window glass. Two passes: this one tints and slightly darkens
// what's behind (float glass transmits ~85-90%), glass_reflect.gdshader adds
// the Fresnel reflection additively so it isn't faded out by the low alpha.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.68, 0.66, 1.0);
uniform float absorb = 0.12;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb * 0.25;
	// Thicker optical path at grazing angles reads as a greener, darker edge.
	ALPHA = clamp(absorb / max(facing, 0.25), 0.0, 0.6);
}
