shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
// Vertex colours from make_models.py: alpha 1 = literal colour, otherwise a palette slot (rgb is a shade), slot 15 = self-lit.
uniform vec3 pal[16];
uniform vec3 sun_tint = vec3(1.0);
uniform vec3 ambient = vec3(0.55);
varying vec3 v_col;
varying float v_glow;
vec3 to_output(vec3 c, bool srgb) { return srgb ? c : pow(c, vec3(2.2)); }
void vertex() {
	int i = int(COLOR.a * 16.0);
	v_glow = i == 15 ? 1.0 : 0.0;
	if (i >= 15) { v_col = COLOR.rgb; }
	else { v_col = pal[i] * COLOR.rgb; }
}
void fragment() {
	vec3 c = to_output(v_col, OUTPUT_IS_SRGB);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = mix(c * to_output(ambient, OUTPUT_IS_SRGB), c, v_glow);
}
