// The 3D view's water: one flat plane under the whole map (view only: no rules here).
// Dark, cold blue-grey, smooth enough to catch a little light, with gentle waves.
// Land tiles stand up through it, so their sides are the shoreline.
shader_type spatial;

uniform vec3 water_colour : source_color = vec3(0.118, 0.165, 0.2); // #1E2A33
uniform float roughness_value = 0.15;
uniform float wave_height = 0.015; // how far the surface rises and falls
uniform float wave_speed = 0.6;

float waves(vec2 p, float t) {
	return sin(p.x * 2.1 + t) * 0.5 + sin(p.y * 1.7 - t * 0.8) * 0.35
		+ sin((p.x + p.y) * 3.3 + t * 1.3) * 0.15;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	// the slope of the waves tilts the surface normal, so the light glints a little
	float e = 0.05;
	float dx = (waves(p + vec2(e, 0.0), t) - waves(p - vec2(e, 0.0), t)) / (2.0 * e);
	float dz = (waves(p + vec2(0.0, e), t) - waves(p - vec2(0.0, e), t)) / (2.0 * e);
	vec3 n = normalize(vec3(-dx * wave_height * 4.0, 1.0, -dz * wave_height * 4.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = water_colour;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.6;
}
