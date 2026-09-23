shader_type sky;
// Stylised sky for the route levels: the same two-stop gradient the levels
// already used (ProceduralSkyMaterial), plus flat, hard-edged clouds painted
// on a plane above the camera -- low-poly style, no volume, no lighting noise.
// RouteSky builds this from each level's own ProceduralSkyMaterial colours,
// so the curated route and the darker endless mode keep their palettes.
// GL Compatibility friendly: value noise only, no textures, no loops > 3.

group_uniforms gradient;
uniform vec3 sky_top_color : source_color = vec3(0.23, 0.37, 0.47);
uniform vec3 sky_horizon_color : source_color = vec3(0.50, 0.61, 0.56);
uniform vec3 ground_horizon_color : source_color = vec3(0.50, 0.61, 0.56);
uniform vec3 ground_bottom_color : source_color = vec3(0.24, 0.32, 0.28);
uniform float sky_curve : hint_range(0.01, 1.0) = 0.35;

group_uniforms clouds;
uniform vec3 cloud_color : source_color = vec3(0.93, 0.95, 0.92);
uniform vec3 cloud_shade_color : source_color = vec3(0.72, 0.79, 0.78);
// 0 = clear sky, 1 = overcast.
uniform float coverage : hint_range(0.0, 1.0) = 0.36;
// Width of the soft band at the cloud edge; small keeps them flat and graphic.
uniform float edge_softness : hint_range(0.001, 0.2) = 0.012;
uniform float cloud_scale : hint_range(0.05, 3.0) = 1.1;
uniform vec2 wind = vec2(0.006, 0.002);
// Clouds fade out toward the horizon so they never pile up into a grey band.
uniform float horizon_fade : hint_range(0.01, 0.6) = 0.22;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int octave = 0; octave < 3; octave++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.3);
		amplitude *= 0.5;
	}
	return total;
}

void sky() {
	float up = EYEDIR.y;
	vec3 color;
	if (up >= 0.0) {
		color = mix(sky_horizon_color, sky_top_color, clamp(pow(up, sky_curve), 0.0, 1.0));
		// Project the view ray onto a flat cloud deck overhead.
		vec2 deck = EYEDIR.xz / max(up, 0.06) * cloud_scale + TIME * wind;
		float density = fbm(deck);
		float threshold = 1.0 - coverage;
		float body = smoothstep(threshold, threshold + edge_softness, density);
		// A second, offset sample gives each cloud a flat shaded underside,
		// the two-tone look of low-poly art rather than a gradient.
		float lower = smoothstep(threshold, threshold + edge_softness, fbm(deck + vec2(0.0, 0.18)));
		vec3 cloud = mix(cloud_shade_color, cloud_color, lower);
		float fade = smoothstep(0.02, horizon_fade, up);
		color = mix(color, cloud, body * fade);
	} else {
		color = mix(ground_horizon_color, ground_bottom_color, clamp(pow(-up, 0.5), 0.0, 1.0));
	}
	COLOR = color;
}
