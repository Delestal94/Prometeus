shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.27-34: GL Compatibility gelatin with a clear centre, a denser Fresnel
// edge, real screen-space refraction, studio highlights and Beer-Lambert-style
// absorption driven by the baked base-body thickness map. Wrapped diffuse and
// back-light transmission add a single-pass fake subsurface glow. Sparse 3D
// object-space noise adds internal motes without camera or UV swimming. An
// alpha depth pre-pass stabilizes self-overlap and a thinner shadow pass keeps
// the translucent body's shadow lighter than an opaque character's. Per-instance
// colour, opacity and brightness keep one shared material for every player.

instance uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
instance uniform float gel_opacity : hint_range(0.0, 1.0) = 1.0;
instance uniform float gel_brightness : hint_range(0.5, 1.5) = 1.0;

group_uniforms gel;
uniform float center_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float edge_density : hint_range(0.0, 1.0) = 0.38;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;

group_uniforms refraction;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float refraction_strength : hint_range(0.0, 0.08) = 0.018;
uniform float refraction_mix : hint_range(0.0, 1.0) = 0.9;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float specular : hint_range(0.0, 1.0) = 0.9;

group_uniforms subsurface_backlight;
uniform float subsurface_wrap : hint_range(0.0, 1.0) = 0.42;
uniform float backlight_strength : hint_range(0.0, 3.0) = 1.35;
uniform float backlight_power : hint_range(1.0, 8.0) = 2.4;

group_uniforms internal_inclusions;
uniform float inclusion_density : hint_range(0.0, 0.4) = 0.18;
uniform float inclusion_scale : hint_range(8.0, 128.0) = 72.0;
uniform float inclusion_contrast : hint_range(0.0, 0.3) = 0.07;

group_uniforms transparency_shadows;
uniform float shadow_density : hint_range(0.1, 1.0) = 0.32;

group_uniforms thickness_absorption;
uniform sampler2D thickness_map : repeat_disable, filter_linear;
uniform float thickness_decode_meters : hint_range(0.0, 3.0) = 2.0;
uniform float absorption_coefficient : hint_range(0.0, 8.0) = 2.4;
uniform float absorption_color_mix : hint_range(0.0, 1.0) = 0.62;
uniform float absorption_opacity : hint_range(0.0, 1.0) = 0.34;

group_uniforms studio_reflection;
uniform vec4 studio_reflection_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float studio_reflection_strength : hint_range(0.0, 2.0) = 1.1;
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
	vec3 player_tint = gel_color.rgb * gel_brightness;
	vec2 refraction_offset = NORMAL.xy * refraction_strength * (0.55 + fresnel * 0.45);
	vec2 refraction_uv = clamp(SCREEN_UV + refraction_offset, vec2(0.001), vec2(0.999));
	vec3 refracted_background = texture(screen_texture, refraction_uv).rgb;
	vec3 surface_tint = mix(player_tint, vec3(1.0), density * 0.48);
	float thickness_meters = texture(thickness_map, UV).r * thickness_decode_meters;
	float thickness_transmission = exp(-absorption_coefficient * thickness_meters);
	float thickness_absorption = 1.0 - thickness_transmission;
	vec3 absorbed_tint = mix(
		surface_tint,
		player_tint,
		thickness_absorption * absorption_color_mix
	);
	float background_mix = refraction_mix * (1.0 - fresnel * 0.35);
	background_mix *= mix(1.0, thickness_transmission, absorption_color_mix);
	ALBEDO = mix(absorbed_tint, refracted_background, background_mix);
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
	ALBEDO = mix(ALBEDO, studio_reflection_color.rgb, studio_mask * 0.4);
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
	float surface_alpha = gel_color.a * gel_opacity * mix(center_opacity, edge_opacity, fresnel);
	float final_alpha = clamp(
		surface_alpha + thickness_absorption * absorption_opacity + inclusion_mask * inclusion_contrast,
		0.0,
		1.0
	);
	if (IN_SHADOW_PASS) {
		float shadow_coverage = mix(final_alpha, 1.0, shadow_density);
		float shadow_hash = hash_object_cell(floor(model_position * 180.0));
		if (shadow_hash > shadow_coverage) {
			discard;
		}
		ALPHA = 1.0;
	} else {
		ALPHA = final_alpha;
	}
}

void light() {
	float normal_light = dot(NORMAL, LIGHT);
	float wrapped_light = clamp(
		(normal_light + subsurface_wrap) / (1.0 + subsurface_wrap),
		0.0,
		1.0
	);
	float back_light = pow(clamp(-normal_light, 0.0, 1.0), backlight_power);
	vec3 half_vector = normalize(LIGHT + VIEW);
	float specular_power = mix(128.0, 8.0, roughness);
	float specular_lobe = pow(clamp(dot(NORMAL, half_vector), 0.0, 1.0), specular_power);
	vec3 wrapped_diffuse = ALBEDO * LIGHT_COLOR * wrapped_light;
	vec3 back_scatter = gel_color.rgb * gel_brightness * LIGHT_COLOR * back_light * backlight_strength;
	DIFFUSE_LIGHT += (wrapped_diffuse + back_scatter) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * specular_lobe * specular * ATTENUATION;
}
