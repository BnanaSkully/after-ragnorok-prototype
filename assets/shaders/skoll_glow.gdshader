// Sköll's own textures, with the brightest orange (eyes, cracks, embers) shifted halfway
// toward gold and made to shine a little; his darker fur keeps its own colour. Used by view_3d.gd on units/skoll.glb.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform vec3 gold = vec3(1.0, 0.84, 0.32); // the colour the glow becomes (sRGB)
uniform float glow_energy = 0.35;
uniform float gold_amount = 0.5; // how far the glow moves from his own orange toward gold (1 = all the way)

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 s = pow(c, vec3(1.0 / 2.2)); // the picture's own (sRGB) values, to judge "orange"
	float hi = max(s.r, max(s.g, s.b));
	float lo = min(s.r, min(s.g, s.b));
	float sat = hi > 0.0 ? (hi - lo) / hi : 0.0;
	// Orange: red the strongest, green between red and blue, bright and saturated.
	float orange = smoothstep(0.45, 0.65, sat) * smoothstep(0.5, 0.75, hi) * step(s.g, s.r) * step(s.b, s.g);
	vec3 golden = pow(gold * (hi / 0.9), vec3(2.2));
	ALBEDO = mix(c, golden, orange * gold_amount);
	EMISSION = golden * orange * glow_energy;
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
