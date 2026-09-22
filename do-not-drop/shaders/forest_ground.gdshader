shader_type spatial;
render_mode diffuse_burley, cull_disabled;

// Seamless albedo maps authored in Blender. The masks below work in world
// space, so the colour transition does not reveal a repeating tile grid.
uniform sampler2D soil_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D moss_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D gravel_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform float texture_tiling = 18.0;

varying vec3 terrain_world_position;

float terrain_noise(vec2 point) {
	return sin(point.x * 0.73 + sin(point.y * 0.31)) * 0.42
		+ cos(point.y * 0.61 - point.x * 0.17) * 0.33
		+ sin((point.x + point.y) * 1.47) * 0.25;
}

void vertex() {
	// The relief is intentionally shallow: it breaks the perfectly flat visual
	// plane while keeping the vehicle's existing flat collision dependable.
	VERTEX.y += terrain_noise(VERTEX.xz) * 0.045;
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tiled_uv = UV * texture_tiling;
	vec3 soil = texture(soil_texture, tiled_uv).rgb;
	vec3 moss = texture(moss_texture, tiled_uv * 0.82 + vec2(0.17, 0.41)).rgb;
	vec3 gravel = texture(gravel_texture, tiled_uv * 1.24 + vec2(0.53, 0.12)).rgb;
	float broad_mask = terrain_noise(terrain_world_position.xz * 0.20) * 0.5 + 0.5;
	float detail_mask = terrain_noise(terrain_world_position.xz * 0.63 + vec2(7.0, 3.0)) * 0.5 + 0.5;
	float moss_weight = smoothstep(0.38, 0.74, broad_mask);
	float gravel_weight = smoothstep(0.66, 0.91, detail_mask) * (1.0 - moss_weight * 0.65);
	vec3 blended = mix(soil, moss, moss_weight);
	ALBEDO = mix(blended, gravel, gravel_weight);
	ROUGHNESS = 0.94;
}
