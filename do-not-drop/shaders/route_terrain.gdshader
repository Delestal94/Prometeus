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
// Rain (world_mood.gd): 0 dry, 1 soaked. Darkens and polishes the road so
// it catches the sky and the headlights, with puddle-ish patches.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Season (world_mood.gd, N-305): 0 summer, 1 autumn. Dries the grass toward
// straw, patchily, like LowpolyMaterials does for the grass models on it.
uniform float autumn : hint_range(0.0, 1.0) = 0.0;

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
	vec3 straw = mix(vec3(0.5, 0.45, 0.22), vec3(0.62, 0.5, 0.26), broad * 0.5 + 0.5) * lawn_grain * detail_gain * detail_gain;
	lawn = mix(lawn, straw, autumn * (0.45 + 0.25 * smoothstep(-0.3, 0.5, broad)));
	vec3 ground = mix(mix(asphalt, earth, shoulder), lawn, grass);
	ground = mix(ground, earth, COLOR.r * smoothstep(5.7, 7.2, edge));
	float road = (1.0 - shoulder) * (1.0 - grass);
	float puddles = smoothstep(-0.1, 0.45, broad + grain * 0.15);
	float wet_road = wetness * road * mix(0.65, 1.0, puddles) * (1.0 - gravel_mix * 0.6);
	float wet_ground = wetness * (1.0 - road) * 0.35;
	ground *= 1.0 - wet_road * 0.32 - wet_ground * 0.25;
	ALBEDO = ground;
	ROUGHNESS = mix(0.96, 0.16, wet_road);
	SPECULAR = mix(0.5, 0.75, wet_road);
}
