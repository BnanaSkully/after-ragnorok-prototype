// A unit's own colour texture, with its blue arm band (and other strong blues)
// repainted in its faction's colour. Used by view_3d.gd on warrior.glb and scout.glb.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 band_colour : source_color = vec4(0.2, 0.4, 1.0, 1.0);
uniform float roughness_value = 0.85;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 s = pow(c, vec3(1.0 / 2.2)); // back to the picture's own (sRGB) values to judge "blue"
	float hi = max(s.r, max(s.g, s.b));
	float lo = min(s.r, min(s.g, s.b));
	float sat = hi > 0.0 ? (hi - lo) / hi : 0.0;
	float blue = smoothstep(0.06, 0.18, s.b - max(s.r, s.g)) * smoothstep(0.25, 0.45, sat);
	vec3 band = band_colour.rgb * clamp(hi / 0.65, 0.35, 1.4); // keep the band's light and shade
	ALBEDO = mix(c, band, blue);
	ROUGHNESS = roughness_value;
}
