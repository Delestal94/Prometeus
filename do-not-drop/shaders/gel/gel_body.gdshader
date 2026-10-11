shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.27-30: GL Compatibility gelatin with a clear centre, a denser Fresnel
// edge, real screen-space refraction, studio highlights and Beer-Lambert-style
// absorption driven by the baked base-body thickness map.

group_uniforms gel;
uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
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

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float density = fresnel * edge_density;
	vec2 refraction_offset = NORMAL.xy * refraction_strength * (0.55 + fresnel * 0.45);
	vec2 refraction_uv = clamp(SCREEN_UV + refraction_offset, vec2(0.001), vec2(0.999));
	vec3 refracted_background = texture(screen_texture, refraction_uv).rgb;
	vec3 surface_tint = mix(gel_color.rgb, vec3(1.0), density * 0.48);
	float thickness_meters = texture(thickness_map, UV).r * thickness_decode_meters;
	float thickness_transmission = exp(-absorption_coefficient * thickness_meters);
	float thickness_absorption = 1.0 - thickness_transmission;
	vec3 absorbed_tint = mix(
		surface_tint,
		gel_color.rgb,
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
	ROUGHNESS = roughness;
	SPECULAR = specular;
	float surface_alpha = gel_color.a * mix(center_opacity, edge_opacity, fresnel);
	ALPHA = clamp(surface_alpha + thickness_absorption * absorption_opacity, 0.0, 1.0);
}
