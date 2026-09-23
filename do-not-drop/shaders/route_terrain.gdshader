shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

// Greyscale grain maps (art/tools/make_detail_textures.py): each multiplies
// its surface's palette colour, so they add texture without changing the
// look. Set by route_terrain.gd; white (no-op) when missing.
uniform sampler2D asphalt_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metres covered by one repeat of each map.
uniform float asphalt_tile = 4.0;
uniform float earth_tile = 3.0;
uniform float grass_tile = 3.5;
uniform float gravel_tile = 2.0;
// Detail maps average ~0.86; this brings the average back to 1.
uniform float detail_gain = 1.16;

float noise2(vec2 p) {
	return sin(p.x * 1.17 + sin(p.y * 0.83)) * 0.5 + sin(p.y * 1.61 - p.x * 0.71) * 0.25;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float broad = noise2(p * 0.15);
	float grain = noise2(p * 7.0);
	// UV.x contains distance to the road edge; transitions share one surface.
	float edge = UV.x + noise2(p * 1.1) * 0.18;
	float shoulder = smoothstep(5.65, 6.45, edge);
	float grass = smoothstep(6.6, 9.2, edge + broad * 0.65);
	float gravel_mix = smoothstep(0.1, 0.9, UV.y);
	float asphalt_grain = texture(asphalt_detail, p / asphalt_tile).r * detail_gain;
	float gravel_grain = texture(gravel_detail, p / gravel_tile).r * detail_gain;
	vec3 asphalt = mix(vec3(0.205, 0.244, 0.251) * asphalt_grain, vec3(0.48, 0.415, 0.30) * gravel_grain, gravel_mix);
	asphalt += grain * 0.009;
	vec3 earth = (vec3(0.46, 0.435, 0.325) + broad * 0.025 + grain * 0.012) * texture(earth_detail, p / earth_tile).r * detail_gain;
	vec3 lawn = mix(vec3(0.285, 0.43, 0.205), vec3(0.41, 0.54, 0.27), broad * 0.5 + 0.5);
	// Two scales of the same grass map, so the repeat never lines up.
	float lawn_grain = texture(grass_detail, p / grass_tile).r * texture(grass_detail, p / (grass_tile * 3.7) + 0.31).r;
	lawn *= lawn_grain * detail_gain * detail_gain;
	lawn += grain * 0.006;
	vec3 ground = mix(mix(asphalt, earth, shoulder), lawn, grass);
	ground = mix(ground, earth, COLOR.r * smoothstep(5.7, 7.2, edge));
	ALBEDO = ground;
	ROUGHNESS = 0.96;
}
