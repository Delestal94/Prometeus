shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.35: milky fallback for low quality and accessibility. It preserves
// the gel tint, Fresnel density, baked thickness, inclusions and studio
// accents under regular PBR lighting, without transparency or a screen read.

instance uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
instance uniform float gel_opacity : hint_range(0.0, 1.0) = 1.0;
instance uniform float gel_brightness : hint_range(0.5, 1.5) = 1.0;

group_uniforms gel;
uniform float edge_density : hint_range(0.0, 1.0) = 0.38;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;
uniform float milkiness : hint_range(0.0, 1.0) = 0.24;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float specular : hint_range(0.0, 1.0) = 0.86;

group_uniforms internal_inclusions;
uniform float inclusion_density : hint_range(0.0, 0.4) = 0.18;
uniform float inclusion_scale : hint_range(8.0, 128.0) = 72.0;
uniform float inclusion_contrast : hint_range(0.0, 0.3) = 0.07;

group_uniforms thickness_absorption;
uniform sampler2D thickness_map : repeat_disable, filter_linear;
uniform float thickness_decode_meters : hint_range(0.0, 3.0) = 2.0;
uniform float absorption_coefficient : hint_range(0.0, 8.0) = 2.4;
uniform float absorption_color_mix : hint_range(0.0, 1.0) = 0.62;

group_uniforms studio_reflection;
uniform vec4 studio_reflection_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float studio_reflection_strength : hint_range(0.0, 2.0) = 0.3;
uniform float studio_reflection_softness : hint_range(0.002, 0.08) = 0.008;
uniform float studio_ribbon_width : hint_range(0.005, 0.12) = 0.026;

varying vec3 model_position;

float box_mask(vec2 point, vec2 centre, vec2 half_size, float softness) {
	vec2 delta = abs(point - centre) - half_size;
	float distance_to_box = max(delta.x, delta.y);
	return 1.0 - smoothstep(-softness, softness, distance_to_box);
}

float hash_object_cell(vec3 cell) {
	cell = fract(cell * 0.1031);
	cell += dot(cell, cell.yzx + 33.33);
	return fract((cell.x + cell.y) * cell.z);
}

float object_noise_3d(vec3 point) {
	vec3 cell = floor(point);
	vec3 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float near_z = mix(
		mix(hash_object_cell(cell), hash_object_cell(cell + vec3(1.0, 0.0, 0.0)), blend.x),
		mix(hash_object_cell(cell + vec3(0.0, 1.0, 0.0)), hash_object_cell(cell + vec3(1.0, 1.0, 0.0)), blend.x),
		blend.y
	);
	float far_z = mix(
		mix(hash_object_cell(cell + vec3(0.0, 0.0, 1.0)), hash_object_cell(cell + vec3(1.0, 0.0, 1.0)), blend.x),
		mix(hash_object_cell(cell + vec3(0.0, 1.0, 1.0)), hash_object_cell(cell + vec3(1.0, 1.0, 1.0)), blend.x),
		blend.y
	);
	return mix(near_z, far_z, blend.z);
}

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float density = fresnel * edge_density;
	// The transparent shader is visually darkened by the background behind it.
	// Match that perceived value here before direct opaque lighting is applied.
	vec3 player_tint = gel_color.rgb * gel_brightness * 0.72;
	// A player's opacity becomes milk density in this fully opaque variant,
	// preserving visual distinction without returning to alpha blending.
	vec3 opaque_tint = mix(vec3(1.0), player_tint, mix(0.72, 1.0, gel_opacity));
	vec3 surface_tint = mix(opaque_tint, vec3(1.0), milkiness * (1.0 - fresnel));
	float thickness_meters = texture(thickness_map, UV).r * thickness_decode_meters;
	float thickness_absorption = 1.0 - exp(-absorption_coefficient * thickness_meters);
	ALBEDO = mix(surface_tint, player_tint, thickness_absorption * absorption_color_mix);

	vec2 matcap_uv = normalize(NORMAL).xy * 0.5 + 0.5;
	float window_reflection = 0.0;
	window_reflection += box_mask(matcap_uv, vec2(0.315, 0.695), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.405, 0.695), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.315, 0.815), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.405, 0.815), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection *= smoothstep(1.25, 1.36, model_position.y);
	float ribbon = 1.0 - smoothstep(
		studio_ribbon_width,
		studio_ribbon_width + studio_reflection_softness,
		abs(matcap_uv.x - 0.235)
	);
	float arm_gate = smoothstep(0.22, 0.4, abs(model_position.x)) * smoothstep(0.75, 0.95, model_position.y);
	float leg_gate = 1.0 - smoothstep(0.54, 0.76, model_position.y);
	ribbon *= max(arm_gate, leg_gate);
	float studio_mask = clamp(window_reflection + ribbon * 0.55, 0.0, 1.0) * smoothstep(0.08, 0.32, facing);
	ALBEDO = mix(ALBEDO, studio_reflection_color.rgb, studio_mask * 0.34);
	EMISSION = studio_reflection_color.rgb * studio_mask * studio_reflection_strength;

	float inclusion_threshold = mix(1.0, 0.72, inclusion_density);
	float fine_motes = smoothstep(
		inclusion_threshold,
		inclusion_threshold + 0.018,
		object_noise_3d(model_position * inclusion_scale)
	);
	float bubble_field = object_noise_3d(model_position * inclusion_scale * 0.72 + vec3(17.0));
	float bubble_outer = smoothstep(inclusion_threshold - 0.012, inclusion_threshold, bubble_field);
	float bubble_inner = smoothstep(inclusion_threshold + 0.008, inclusion_threshold + 0.02, bubble_field);
	float inclusion_mask = clamp(fine_motes + (bubble_outer - bubble_inner) * 0.7, 0.0, 1.0);
	ALBEDO = mix(ALBEDO, player_tint * 0.82, inclusion_mask * inclusion_contrast);
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

