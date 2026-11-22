shader_type canvas_item;

// Mist creeping in at the screen's edges, with a faint flicker of the void's blue
// light in it (HUD art pass, Nathan's mockup). Drawn on a full-screen ColorRect
// above the map and below the HUD; it never takes clicks.

uniform vec4 mist_dark : source_color = vec4(0.03, 0.035, 0.05, 1.0);
uniform vec4 mist_light : source_color = vec4(0.34, 0.36, 0.42, 1.0);
uniform vec4 void_glow : source_color = vec4(0.25, 0.5, 1.0, 1.0);
uniform float width = 0.17; // how far the mist reaches in from the edge (share of the screen height)
uniform float strength = 0.8; // how thick it is at the very edge
uniform float aspect = 1.78; // screen width / height (set by main.gd)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	// distance to the nearest edge, in screen heights
	float d = min(min(uv.x, 1.0 - uv.x) * aspect, min(uv.y, 1.0 - uv.y));
	float n = fbm(p * 3.2 + vec2(TIME * 0.025, -TIME * 0.018));
	float m = fbm(p * 7.0 - vec2(TIME * 0.04, TIME * 0.03));
	float edge = 1.0 - smoothstep(0.0, width, d + (n - 0.5) * 0.09);
	float mist = edge * edge * strength * (0.55 + 0.6 * m);
	vec3 col = mix(mist_dark.rgb, mist_light.rgb, clamp(n * 1.3 - 0.2, 0.0, 1.0) * edge);
	// the void's light: thin flickering veins close to the edge
	float vein = 1.0 - smoothstep(0.0, 0.035, abs(fbm(p * 5.0 + TIME * 0.05) - 0.5) + d * 0.6);
	float flicker = 0.55 + 0.45 * sin(TIME * 1.3 + n * 9.0);
	float glow = vein * flicker * (1.0 - smoothstep(0.0, width * 0.55, d));
	col = mix(col, void_glow.rgb, clamp(glow, 0.0, 1.0));
	COLOR = vec4(col, clamp(mist + glow * 0.7, 0.0, 0.92));
}
